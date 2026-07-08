#!/bin/bash
# build_winpe_wimboot.sh
# Prepares an HTTP directory for iPXE+wimboot from a base WinPE zip.

set -euo pipefail

BASE_ZIP="${1:?Usage: build_winpe_wimboot.sh <base_zip> <output_dir> <peshell_build_dir> <winkit_dir> <winutils_dir>}"
OUTPUT_DIR="${2:?Missing output dir}"
PESHELL_BUILD="${3:?Missing peshell build dir}"
WINKIT_DIR="${4:?Missing win-kit dir}"
WINUTILS_DIR="${5:?Missing win-utils dir}"

WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
BASE_DIR="$WORK_DIR/base"
MOUNT_DIR="$WORK_DIR/mount"

echo "[INFO] Work dir: $WORK_DIR"
echo "[INFO] Base zip: $BASE_ZIP"
echo "[INFO] Output dir: $OUTPUT_DIR"

rm -rf "$BASE_DIR" "$MOUNT_DIR" "$OUTPUT_DIR"
mkdir -p "$BASE_DIR" "$MOUNT_DIR" "$OUTPUT_DIR"

echo "[1/5] Extracting base WinPE bundle..."
unzip -q "$BASE_ZIP" -d "$BASE_DIR"

BOOT_WIM="$BASE_DIR/sources/boot.wim"
BOOT_SDI="$BASE_DIR/boot/boot.sdi"
BCD="$BASE_DIR/boot/bcd"
BOOTMGR="$BASE_DIR/bootmgr"

for f in "$BOOT_WIM" "$BOOT_SDI" "$BCD" "$BOOTMGR"; do
    if [ ! -f "$f" ]; then
        echo "[ERROR] Required WinPE file missing: $f"
        find "$BASE_DIR" -maxdepth 3 -type f | sort | head -80
        exit 1
    fi
done

chmod u+w "$BOOT_WIM"

echo "[2/5] Mounting boot.wim..."
WIM_INDEX=$(wimlib-imagex info "$BOOT_WIM" 2>/dev/null | awk -F: '/Boot Index/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
if [ -z "$WIM_INDEX" ] || [ "$WIM_INDEX" = "0" ]; then
    WIM_INDEX=1
fi
echo "[INFO] boot.wim index: $WIM_INDEX"
wimlib-imagex info "$BOOT_WIM" > "$OUTPUT_DIR/wiminfo.txt"
wimlib-imagex mountrw "$BOOT_WIM" "$WIM_INDEX" "$MOUNT_DIR"

PE_SYSTEM32="$MOUNT_DIR/Windows/System32"
mkdir -p "$PE_SYSTEM32"

echo "[3/5] Injecting peshell and Lua assets..."
cat > "$PE_SYSTEM32/winpeshl.ini" <<'INI'
[LaunchApps]
%SYSTEMROOT%\System32\cmd.exe, "/c %SYSTEMROOT%\System32\winpeshl.cmd"
INI

cat > "$PE_SYSTEM32/winpeshl.cmd" <<'CMD'
@echo off
echo WINPE_CI_WINPESHL_CMD_START > COM1
echo WINPE_CI_WINPESHL_CMD_SYSTEMROOT=%SYSTEMROOT% > COM1
if exist %SYSTEMROOT%\System32\peshell.exe (
  echo WINPE_CI_WINPESHL_CMD_PESHELL_FOUND > COM1
) else (
  echo WINPE_CI_WINPESHL_CMD_PESHELL_MISSING > COM1
)
%SYSTEMROOT%\System32\peshell.exe run %SYSTEMROOT%\System32\winpe_test_profile.lua >> COM1 2>&1
set PESHELL_EXIT=%ERRORLEVEL%
echo WINPE_CI_WINPESHL_CMD_EXIT=%PESHELL_EXIT% > COM1
wpeutil reboot
CMD

cat > "$PE_SYSTEM32/startnet.cmd" <<'CMD'
@echo off
echo WINPE_CI_STARTNET_CMD_START > COM1
wpeinit
echo WINPE_CI_STARTNET_CMD_AFTER_WPEINIT > COM1
CMD

SYNC_ROOT="$WORK_DIR/inject"
rm -rf "$SYNC_ROOT"
mkdir -p "$SYNC_ROOT/Windows/System32"
SYNC_SYSTEM32="$SYNC_ROOT/Windows/System32"

cp "$PE_SYSTEM32/winpeshl.ini" "$SYNC_SYSTEM32/"
cp "$PE_SYSTEM32/winpeshl.cmd" "$SYNC_SYSTEM32/"
cp "$PE_SYSTEM32/startnet.cmd" "$SYNC_SYSTEM32/"

for f in peshell.exe lua51.dll; do
    if [ -f "$PESHELL_BUILD/bin/$f" ]; then
        cp "$PESHELL_BUILD/bin/$f" "$SYNC_SYSTEM32/"
        echo "  [OK] $f"
    elif [ -f "$PESHELL_BUILD/$f" ]; then
        cp "$PESHELL_BUILD/$f" "$SYNC_SYSTEM32/"
        echo "  [OK] $f (from root)"
    else
        echo "  [WARN] $f not found"
    fi
done

LUA_DIR="$SYNC_SYSTEM32/lua"
mkdir -p "$LUA_DIR/ext" "$LUA_DIR/ffi" "$LUA_DIR/win-kit" "$LUA_DIR/win-utils" "$LUA_DIR/jit"

for jit_src in "$PESHELL_BUILD/jit" "$PESHELL_BUILD/share/lua/5.1/jit"; do
    if [ -d "$jit_src" ]; then
        cp "$jit_src"/*.lua "$LUA_DIR/jit/" 2>/dev/null || true
        break
    fi
done

if [ -d "$WINUTILS_DIR/vendor/lua-ext" ]; then
    cp "$WINUTILS_DIR"/vendor/lua-ext/*.lua "$LUA_DIR/ext/" 2>/dev/null || true
    echo "  [OK] lua-ext"
fi

if [ -d "$WINUTILS_DIR/vendor/lua-ffi-bindings" ]; then
    cp -r "$WINUTILS_DIR"/vendor/lua-ffi-bindings/* "$LUA_DIR/ffi/" 2>/dev/null || true
    echo "  [OK] lua-ffi-bindings"
fi

cp -r "$WINKIT_DIR"/* "$LUA_DIR/win-kit/" 2>/dev/null || true
echo "  [OK] win-kit"

mkdir -p "$LUA_DIR/win-utils"
for item in core disk fs net process reg sys tests init.lua; do
    if [ -e "$WINUTILS_DIR/$item" ]; then
        cp -r "$WINUTILS_DIR/$item" "$LUA_DIR/win-utils/" 2>/dev/null || true
    fi
done
echo "  [OK] win-utils"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cp "$REPO_ROOT/scripts/winpe_test_profile.lua" "$PE_SYSTEM32/"
echo "  [OK] winpe_test_profile.lua"

cp "$REPO_ROOT/scripts/winpe_test_profile.lua" "$SYNC_SYSTEM32/"
echo "[INFO] Copying injected files into mounted WIM..."
cp -a "$SYNC_ROOT"/. "$MOUNT_DIR"/

echo "[4/5] Committing boot.wim changes..."
wimlib-imagex unmount "$MOUNT_DIR" --commit

echo "[5/5] Preparing iPXE HTTP root..."
cp "$BOOTMGR" "$OUTPUT_DIR/bootmgr"
cp "$BCD" "$OUTPUT_DIR/BCD"
cp "$BOOT_SDI" "$OUTPUT_DIR/boot.sdi"
cp "$BOOT_WIM" "$OUTPUT_DIR/boot.wim"
printf '%s\n' "$WIM_INDEX" > "$OUTPUT_DIR/wimboot.index"

cat > "$OUTPUT_DIR/boot.ipxe" <<'IPXE'
#!ipxe
echo WINPE_CI_IPXE_START
dhcp || goto failed
set base http://10.0.2.2:8080
kernel ${base}/wimboot index=WIMBOOT_INDEX_PLACEHOLDER
initrd ${base}/bootmgr bootmgr
initrd ${base}/BCD BCD
initrd ${base}/boot.sdi boot.sdi
initrd ${base}/boot.wim boot.wim
echo WINPE_CI_IPXE_BOOT
boot || goto failed
:failed
echo WINPE_CI_IPXE_FAILED
shell
IPXE
sed -i "s/WIMBOOT_INDEX_PLACEHOLDER/$WIM_INDEX/g" "$OUTPUT_DIR/boot.ipxe"

find "$OUTPUT_DIR" -maxdepth 1 -type f -printf "[OUT] %f %s bytes\n" | sort
echo "[DONE] iPXE HTTP root: $OUTPUT_DIR"
