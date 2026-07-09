#!/bin/bash
# build_winpe_wimboot.sh
# Prepares an HTTP directory for iPXE+wimboot from a base WinPE WIM.
#
# The base WIM must be a bootable WinPE image with Setup\CmdLine support.
# This script:
#   1. Extracts boot files from a base zip (or uses a direct WIM path)
#   2. Mounts the WIM read-write at the Boot Index
#   3. Injects peshell.exe, Lua runtime, win-kit, win-utils, test profile
#   4. Injects share/lua/5.1 (prelude, init, lib, plugins, etc.)
#   5. Injects pe_ci_run.cmd that writes all output to the CI result drive
#   6. Modifies SYSTEM\Setup\CmdLine to run pe_ci_run.cmd through cmd.exe
#   7. Commits the WIM and prepares the iPXE HTTP root
#
# Usage:
#   build_winpe_wimboot.sh <base_zip_or_wim> <output_dir> <peshell_build_dir> <winkit_dir> <winutils_dir>

set -euo pipefail

BASE_INPUT="${1:?Usage: build_winpe_wimboot.sh <base_zip_or_wim> <output_dir> <peshell_build_dir> <winkit_dir> <winutils_dir>}"
OUTPUT_DIR="${2:?Missing output dir}"
PESHELL_BUILD="${3:?Missing peshell build dir}"
WINKIT_DIR="${4:?Missing win-kit dir}"
WINUTILS_DIR="${5:?Missing win-utils dir}"

WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
BASE_DIR="$WORK_DIR/base"
MOUNT_DIR="$WORK_DIR/mount"
WORK_WIM="${WORK_WIM:-}"
RESET_WORK_WIM="${RESET_WORK_WIM:-0}"

echo "[INFO] Work dir: $WORK_DIR"
echo "[INFO] Base input: $BASE_INPUT"
echo "[INFO] Output dir: $OUTPUT_DIR"

rm -rf "$BASE_DIR" "$MOUNT_DIR"
mkdir -p "$BASE_DIR" "$MOUNT_DIR" "$OUTPUT_DIR"

# ============================================================================
# Step 1: Obtain boot files (from zip or direct WIM)
# ============================================================================
echo "[1/7] Preparing base WinPE files..."

if [[ "$BASE_INPUT" == *.zip ]]; then
    unzip -q "$BASE_INPUT" -d "$BASE_DIR"
    BOOT_WIM="$BASE_DIR/sources/boot.wim"
    BOOT_SDI="$BASE_DIR/boot/boot.sdi"
    BCD="$BASE_DIR/boot/bcd"
    BOOTMGR="$BASE_DIR/bootmgr"
else
    if [ -n "$WORK_WIM" ]; then
        if [ "$RESET_WORK_WIM" = "1" ] || [ ! -f "$WORK_WIM" ]; then
            mkdir -p "$(dirname "$WORK_WIM")"
            cp "$BASE_INPUT" "$WORK_WIM"
        fi
        BOOT_WIM="$WORK_WIM"
    else
        cp "$BASE_INPUT" "$BASE_DIR/boot.wim"
        BOOT_WIM="$BASE_DIR/boot.wim"
    fi
    # Use boot files from the known base zip if available
    BOOT_SDI="${BOOT_SDI:-/tmp/opencode/winpe_base_extract/boot/boot.sdi}"
    BCD="${BCD:-/tmp/opencode/winpe_base_extract/boot/bcd}"
    BOOTMGR="${BOOTMGR:-/tmp/opencode/winpe_base_extract/bootmgr}"
fi

for f in "$BOOT_WIM" "$BOOT_SDI" "$BCD" "$BOOTMGR"; do
    if [ ! -f "$f" ]; then
        echo "[ERROR] Required WinPE file missing: $f"
        exit 1
    fi
done

chmod u+w "$BOOT_WIM"

# ============================================================================
# Step 2: Mount WIM at Boot Index
# ============================================================================
echo "[2/7] Mounting boot.wim..."
WIM_INDEX=$(wimlib-imagex info "$BOOT_WIM" 2>/dev/null | awk -F: '/Boot Index/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
if [ -z "$WIM_INDEX" ] || [ "$WIM_INDEX" = "0" ]; then
    WIM_INDEX=1
fi
echo "[INFO] boot.wim index: $WIM_INDEX"
wimlib-imagex info "$BOOT_WIM" > "$OUTPUT_DIR/wiminfo.txt"
wimlib-imagex mountrw "$BOOT_WIM" "$WIM_INDEX" "$MOUNT_DIR"

PE_SYSTEM32="$MOUNT_DIR/Windows/System32"
PE_WINDOWS="$MOUNT_DIR/Windows"
mkdir -p "$PE_SYSTEM32"

# ============================================================================
# Step 3: Inject peshell.exe and VC runtime DLLs
# ============================================================================
echo "[3/7] Injecting peshell and runtime DLLs..."

for f in peshell.exe lua51.dll concrt140.dll msvcp140.dll msvcp140_1.dll msvcp140_2.dll \
         msvcp140_atomic_wait.dll msvcp140_codecvt_ids.dll vccorlib140.dll \
         vcruntime140.dll vcruntime140_1.dll vcruntime140_threads.dll; do
    if [ -f "$PESHELL_BUILD/bin/$f" ]; then
        cp "$PESHELL_BUILD/bin/$f" "$PE_SYSTEM32/"
        echo "  [OK] $f"
    elif [ -f "$PESHELL_BUILD/$f" ]; then
        cp "$PESHELL_BUILD/$f" "$PE_SYSTEM32/"
        echo "  [OK] $f (from root)"
    else
        echo "  [WARN] $f not found"
    fi
done

# ============================================================================
# Step 4: Inject Lua runtime (share/lua/5.1 - prelude, init, lib, plugins)
# ============================================================================
echo "[4/7] Injecting Lua runtime and modules..."

# peshell expects share/lua/5.1/prelude.lua
SHARE_LUA="$PE_WINDOWS/share/lua/5.1"
mkdir -p "$SHARE_LUA"
for item in prelude.lua init.lua core lib plugins profiles; do
    if [ -e "$PESHELL_BUILD/share/lua/5.1/$item" ]; then
        cp -r "$PESHELL_BUILD/share/lua/5.1/$item" "$SHARE_LUA/" 2>/dev/null || true
    fi
done
echo "  [OK] share/lua/5.1"

# Also inject Lua modules into System32/lua for require paths
LUA_DIR="$PE_SYSTEM32/lua"
mkdir -p "$LUA_DIR/ext" "$LUA_DIR/ffi" "$LUA_DIR/win-kit" "$LUA_DIR/win-utils" "$LUA_DIR/jit" "$LUA_DIR/tasks"

# JIT stdlib
for jit_src in "$PESHELL_BUILD/jit" "$PESHELL_BUILD/share/lua/5.1/jit"; do
    if [ -d "$jit_src" ]; then
        cp "$jit_src"/*.lua "$LUA_DIR/jit/" 2>/dev/null || true
        break
    fi
done

# lua-ext
if [ -d "$WINUTILS_DIR/vendor/lua-ext" ]; then
    cp "$WINUTILS_DIR"/vendor/lua-ext/*.lua "$LUA_DIR/ext/" 2>/dev/null || true
    echo "  [OK] lua-ext"
fi

# lua-ffi-bindings
if [ -d "$WINUTILS_DIR/vendor/lua-ffi-bindings" ]; then
    cp -r "$WINUTILS_DIR"/vendor/lua-ffi-bindings/* "$LUA_DIR/ffi/" 2>/dev/null || true
    echo "  [OK] lua-ffi-bindings"
fi

# win-kit
cp -r "$WINKIT_DIR"/* "$LUA_DIR/win-kit/" 2>/dev/null || true
echo "  [OK] win-kit"

# win-utils (including deps.lua)
for item in core disk fs net process reg sys tests deps.lua init.lua; do
    if [ -e "$WINUTILS_DIR/$item" ]; then
        cp -r "$WINUTILS_DIR/$item" "$LUA_DIR/win-utils/" 2>/dev/null || true
    fi
done
echo "  [OK] win-utils"

# tasks/runner.lua from peshell
if [ -f "$PESHELL_BUILD/share/lua/5.1/lib/tasks/runner.lua" ]; then
    cp "$PESHELL_BUILD/share/lua/5.1/lib/tasks/runner.lua" "$LUA_DIR/tasks/"
    echo "  [OK] tasks/runner"
fi

# Test profile
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cp "$REPO_ROOT/scripts/winpe_test_profile.lua" "$PE_SYSTEM32/"
echo "  [OK] winpe_test_profile.lua"

if [ -f "$REPO_ROOT/tools/serial_cmd/serial_cmd.exe" ]; then
    cp "$REPO_ROOT/tools/serial_cmd/serial_cmd.exe" "$PE_SYSTEM32/"
    echo "  [OK] serial_cmd.exe"
else
    echo "  [WARN] serial_cmd.exe not found"
fi

# ============================================================================
# Step 5: Inject pe_ci_run.cmd and modify registry
# ============================================================================
echo "[5/7] Creating launcher and modifying registry..."

cp "$REPO_ROOT/scripts/pe_ci_run.cmd" "$PE_SYSTEM32/pe_ci_run.cmd"
echo "  [OK] pe_ci_run.cmd"

# Modify SYSTEM\Setup\CmdLine to run our launcher through cmd.exe.  KuerPE is
# known to start cmd.exe from this key; using /c preserves that launch path.
SYSTEM_HIVE="$PE_SYSTEM32/config/SYSTEM"
if [ -f "$SYSTEM_HIVE" ]; then
    printf 'cd \\Setup\ned CmdLine\ncmd.exe /c X:\\Windows\\System32\\pe_ci_run.cmd\n\nq\ny\n' \
        | chntpw -e "$SYSTEM_HIVE" 2>&1 | grep -E "EDIT|OK|Write" || true
    echo "  [OK] Registry: Setup\\CmdLine = cmd.exe /c X:\\Windows\\System32\\pe_ci_run.cmd"
else
    echo "  [WARN] SYSTEM hive not found, skipping registry modification"
fi

# ============================================================================
# Step 6: Commit WIM changes
# ============================================================================
echo "[6/7] Committing boot.wim changes..."
wimlib-imagex unmount "$MOUNT_DIR" --commit

# ============================================================================
# Step 7: Prepare iPXE HTTP root
# ============================================================================
echo "[7/7] Preparing iPXE HTTP root..."
cp "$BOOTMGR" "$OUTPUT_DIR/bootmgr"
cp "$BCD" "$OUTPUT_DIR/BCD"
cp "$BOOT_SDI" "$OUTPUT_DIR/boot.sdi"
if ! ln -f "$BOOT_WIM" "$OUTPUT_DIR/boot.wim" 2>/dev/null; then
    cp "$BOOT_WIM" "$OUTPUT_DIR/boot.wim"
fi
printf '%s\n' "$WIM_INDEX" > "$OUTPUT_DIR/wimboot.index"

cat > "$OUTPUT_DIR/boot.ipxe" <<IPXE
#!ipxe
echo WINPE_CI_IPXE_START
dhcp || goto failed
set base http://10.0.2.2:8080
kernel \${base}/wimboot index=$WIM_INDEX
initrd \${base}/bootmgr bootmgr
initrd \${base}/BCD BCD
initrd \${base}/boot.sdi boot.sdi
initrd \${base}/boot.wim boot.wim
echo WINPE_CI_IPXE_BOOT
boot || goto failed
:failed
echo WINPE_CI_IPXE_FAILED
shell
IPXE

find "$OUTPUT_DIR" -maxdepth 1 -type f -printf "[OUT] %f %s bytes\n" | sort
echo "[DONE] iPXE HTTP root: $OUTPUT_DIR"
