#!/bin/bash
# build_winpe_iso.sh
# Builds a bootable WinPE ISO with peshell + win-kit + win-utils injected.
# Runs on Linux (GitHub Actions ubuntu-latest).
#
# Usage:
#   ./build_winpe_iso.sh <output_iso> <peshell_build_dir> <winkit_dir> <winutils_dir>
#
# Requires: wimtools (wimlib-imagex), xorriso, curl, python3, cabextract, chntpw

set -euo pipefail

OUTPUT_ISO="${1:?Usage: build_winpe_iso.sh <output_iso> <peshell_build_dir> <winkit_dir> <winutils_dir>}"
PESHELL_BUILD="${2:?Missing peshell build dir}"
WINKIT_DIR="${3:?Missing win-kit dir}"
WINUTILS_DIR="${4:?Missing win-utils dir}"

WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
UUP_BUILD="${UUP_BUILD:-19044.7417}"
UUP_ARCH="${UUP_ARCH:-amd64}"
UUP_LANG="${UUP_LANG:-en-us}"
UUP_EDITION="${UUP_EDITION:-PROFESSIONAL}"

# UUP files cache (persisted across CI runs via actions/cache)
UUP_FILES_DIR="${UUP_FILES_DIR:-/tmp/uup_files}"
# Converter scripts (vendored in repo, no external download needed)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONVERTER_DIR="${CONVERTER_DIR:-$REPO_ROOT/scripts/uup-converter}"

echo "[INFO] Work dir: $WORK_DIR"
echo "[INFO] UUP build: $UUP_BUILD ($UUP_ARCH, $UUP_LANG, $UUP_EDITION)"
echo "[INFO] UUP cache: $UUP_FILES_DIR"
echo "[INFO] Converter: $CONVERTER_DIR"

mkdir -p "$UUP_FILES_DIR" "$WORK_DIR"

# ============================================================================
# Step 1: Verify converter scripts
# ============================================================================
echo "[1/8] Verifying UUP converter scripts..."

if [ ! -f "$CONVERTER_DIR/convert.sh" ]; then
    echo "[ERROR] UUP converter not found at $CONVERTER_DIR/convert.sh"
    exit 1
fi
chmod +x "$CONVERTER_DIR/convert.sh" 2>/dev/null || true
echo "[INFO] Converter ready: $(wc -l < "$CONVERTER_DIR/convert.sh") lines"

# ============================================================================
# Step 2: Query UUP dump API for the UUID
# ============================================================================
echo "[2/8] Querying UUP dump API for build $UUP_BUILD..."

API_RESP=$(curl -s "https://api.uupdump.net/listid.php?sort=build=desc")
UUP_UUID=$(echo "$API_RESP" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for b in data['response']['builds']:
    if b['build'] == '${UUP_BUILD}' and b['arch'] == '${UUP_ARCH}':
        print(b['uuid'])
        break
" 2>/dev/null)

if [ -z "$UUP_UUID" ]; then
    echo "[ERROR] Could not find build $UUP_BUILD ($UUP_ARCH) on UUP dump"
    exit 1
fi
echo "[INFO] UUID: $UUP_UUID"

# ============================================================================
# Step 3: Get file download URLs from UUP dump API
# ============================================================================
echo "[3/8] Getting download URLs from UUP dump..."

GET_RESP=$(curl -s "https://api.uupdump.net/get.php?id=${UUP_UUID}&lang=${UUP_LANG}&edition=${UUP_EDITION}")

echo "$GET_RESP" | python3 -c "
import json, sys
data = json.load(sys.stdin)
resp = data.get('response', data)
files = resp.get('files', {})
with open('${WORK_DIR}/download_list.txt', 'w') as f:
    for name, info in files.items():
        url = info.get('url', '')
        sha1 = info.get('sha1', '')
        size = info.get('size', '0')
        if url:
            f.write(f'{url}\t{name}\t{sha1}\t{size}\n')
file_count = sum(1 for _ in open('${WORK_DIR}/download_list.txt'))
total_mb = sum(int(info.get('size',0)) for info in files.values()) / (1024*1024)
print(f'[INFO] {file_count} files, total ~{total_mb:.0f} MB')
"

# ============================================================================
# Step 4: Download UUP files (with cache via sha1 check)
# ============================================================================
echo "[4/8] Downloading UUP files..."

downloaded=0
skipped=0
while IFS=$'\t' read -r url name sha1 size; do
    dest="$UUP_FILES_DIR/$name"
    if [ -f "$dest" ]; then
        existing_sha1=$(sha1sum "$dest" | awk '{print $1}')
        if [ "$existing_sha1" = "$sha1" ]; then
            skipped=$((skipped + 1))
            continue
        fi
    fi
    size_mb=$((size / 1048576))
    echo "  Downloading: $name (~${size_mb}MB)"
    for attempt in 1 2 3 4 5; do
        aria2c --continue=true --max-tries=5 --retry-wait=5 \
            --console-log-level=warn --summary-interval=0 \
            --connect-timeout=30 --timeout=120 \
            --split=4 --max-connection-per-server=4 \
            --dir="$UUP_FILES_DIR" --out="$name" "$url" && \
            [ "$(sha1sum "$dest" | awk '{print $1}')" = "$sha1" ] && break

        echo "  [WARN] Download or SHA1 check failed for $name (attempt $attempt/5)"
        rm -f "$dest" "$dest.aria2"
        sleep 5
    done

    if [ ! -f "$dest" ] || [ "$(sha1sum "$dest" | awk '{print $1}')" != "$sha1" ]; then
        echo "  [ERROR] Failed to download verified file: $name"
        exit 1
    fi
    downloaded=$((downloaded + 1))
done < "$WORK_DIR/download_list.txt"

echo "[INFO] Downloaded: $downloaded, Skipped (cached): $skipped"

# ============================================================================
# Step 5: Run UUP converter to build ISO
# ============================================================================
echo "[5/8] Running UUP converter to build base ISO..."

BASE_ISO="$WORK_DIR/winpe_base.iso"

# Create a minimal convert config for non-interactive mode
cat > "$CONVERTER_DIR/convert_config_linux" <<'CFG'
AUTO_START=1
ADD_UPDATES=0
CLEANUP=0
RESET_BASE=0
NETFX3=0
START_VIRTUAL=0
WIM2ESD=0
WIM2SWM=0
SKIP_ISO=0
SKIP_WINRE=0
LCU_WINRE=0
UPDT_BOOT_FILES=1
FORCE_DISM=0
REF_ESD=0
SKIP_EDGE=1
AUTO_EXIT=1
CFG

# Run the converter (args: compression, uup_directory, virtual_editions).
# It writes ISODIR and the generated ISO to the current directory, so keep
# those large build artifacts inside WORK_DIR.
rm -f "$WORK_DIR"/*.iso
(
    cd "$WORK_DIR"
    "$CONVERTER_DIR/convert.sh" wim "$UUP_FILES_DIR" 0
) 2>&1 | tee "$WORK_DIR/converter.log" || {
    echo "[ERROR] UUP converter failed"
    tail -30 "$WORK_DIR/converter.log"
    exit 1
}

# Find the generated ISO (converter creates it in WORK_DIR)
BASE_ISO=$(find "$WORK_DIR" -maxdepth 1 -iname "*.iso" -type f 2>/dev/null | head -1)
if [ -z "$BASE_ISO" ] || [ ! -f "$BASE_ISO" ]; then
    echo "[ERROR] No ISO generated by converter"
    find "$WORK_DIR" -maxdepth 2 -type f | sort | tail -50
    tail -30 "$WORK_DIR/converter.log"
    exit 1
fi
echo "[INFO] Base ISO: $BASE_ISO ($(du -h "$BASE_ISO" | cut -f1))"

# ============================================================================
# Step 6: Extract boot.wim from base ISO, inject peshell assets
# ============================================================================
echo "[6/8] Extracting and injecting boot.wim..."

# Mount the base ISO to extract boot.wim
ISO_MOUNT="$WORK_DIR/iso_mount"
mkdir -p "$ISO_MOUNT"
sudo mount -o loop,ro "$BASE_ISO" "$ISO_MOUNT" 2>/dev/null || {
    # Fallback: 7z can extract from ISO
    7z x "$BASE_ISO" -o"$ISO_MOUNT" sources/boot.wim -y 2>/dev/null || {
        echo "[ERROR] Cannot extract boot.wim from ISO"
        exit 1
    }
}

BOOT_WIM="$WORK_DIR/boot.wim"
if [ -f "$ISO_MOUNT/sources/boot.wim" ]; then
    cp "$ISO_MOUNT/sources/boot.wim" "$BOOT_WIM"
    chmod u+w "$BOOT_WIM"
else
    echo "[ERROR] boot.wim not found in ISO"
    ls -la "$ISO_MOUNT/sources/" 2>/dev/null || ls -la "$ISO_MOUNT/" 2>/dev/null
    exit 1
fi
sudo umount "$ISO_MOUNT" 2>/dev/null || true

echo "[INFO] boot.wim: $(du -h "$BOOT_WIM" | cut -f1)"

# Mount boot.wim and inject assets
MOUNT_DIR="$WORK_DIR/mount"
mkdir -p "$MOUNT_DIR"

# Determine WIM index (WinPE is usually index 1)
WIM_INDEX=1
wimlib-imagex mountrw "$BOOT_WIM" "$WIM_INDEX" "$MOUNT_DIR" 2>/dev/null || {
    WIM_INDEX=2
    wimlib-imagex mountrw "$BOOT_WIM" "$WIM_INDEX" "$MOUNT_DIR"
}

PE_SYSTEM32="$MOUNT_DIR/Windows/System32"
mkdir -p "$PE_SYSTEM32"

# winpeshl.ini: replace default shell with peshell
# When peshell exits, WinPE reboots → QEMU -no-reboot shuts down
cat > "$PE_SYSTEM32/winpeshl.ini" <<'INI'
[LaunchApps]
%SYSTEMROOT%\System32\peshell.exe, "run %SYSTEMROOT%\System32\winpe_test_profile.lua"
INI

# Copy peshell.exe and lua51.dll
for f in peshell.exe lua51.dll; do
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

# Create Lua module directories
LUA_DIR="$PE_SYSTEM32/lua"
mkdir -p "$LUA_DIR/ext" "$LUA_DIR/ffi" "$LUA_DIR/win-kit" "$LUA_DIR/win-utils" "$LUA_DIR/jit"

# Copy JIT stdlib
for jit_src in "$PESHELL_BUILD/jit" "$PESHELL_BUILD/share/lua/5.1/jit"; do
    if [ -d "$jit_src" ]; then
        cp "$jit_src"/*.lua "$LUA_DIR/jit/" 2>/dev/null || true
        break
    fi
done

# Copy lua-ext from win-utils vendor
if [ -d "$WINUTILS_DIR/vendor/lua-ext" ]; then
    cp "$WINUTILS_DIR"/vendor/lua-ext/*.lua "$LUA_DIR/ext/" 2>/dev/null || true
    echo "  [OK] lua-ext"
fi

# Copy lua-ffi-bindings from win-utils vendor
if [ -d "$WINUTILS_DIR/vendor/lua-ffi-bindings" ]; then
    cp -r "$WINUTILS_DIR"/vendor/lua-ffi-bindings/* "$LUA_DIR/ffi/" 2>/dev/null || true
    echo "  [OK] lua-ffi-bindings"
fi

# Copy win-kit
cp -r "$WINKIT_DIR"/* "$LUA_DIR/win-kit/" 2>/dev/null || true
echo "  [OK] win-kit"

# Copy win-utils (excluding vendor to avoid duplication)
mkdir -p "$LUA_DIR/win-utils"
for item in core disk fs net process reg sys tests init.lua; do
    if [ -e "$WINUTILS_DIR/$item" ]; then
        cp -r "$WINUTILS_DIR/$item" "$LUA_DIR/win-utils/" 2>/dev/null || true
    fi
done
echo "  [OK] win-utils"

# Copy the test profile
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$REPO_ROOT/scripts/winpe_test_profile.lua" ]; then
    cp "$REPO_ROOT/scripts/winpe_test_profile.lua" "$PE_SYSTEM32/"
    echo "  [OK] winpe_test_profile.lua"
fi

# Unmount and commit
echo "[INFO] Committing boot.wim changes..."
wimlib-imagex unmount "$MOUNT_DIR" --commit

# ============================================================================
# Step 7: Rebuild bootable ISO with modified boot.wim
# ============================================================================
echo "[7/8] Rebuilding bootable ISO..."

ISO_DIR="$WORK_DIR/iso_out"
mkdir -p "$ISO_DIR/sources" "$ISO_DIR/boot" "$ISO_DIR/efi/boot"

# Extract boot files from base ISO
7z x "$BASE_ISO" -o"$ISO_DIR" -y \
    bootmgr bootmgr.efi boot/etfsboot.com efi/boot/bootx64.efi 2>/dev/null || true

# Also extract any other needed files from base ISO
7z x "$BASE_ISO" -o"$ISO_DIR" -y -x!sources/boot.wim 2>/dev/null || true

# Replace boot.wim with our modified version
cp "$BOOT_WIM" "$ISO_DIR/sources/boot.wim"

# Build ISO with xorriso
ETFSBOOT="$ISO_DIR/boot/etfsboot.com"
EFIBOOT="$ISO_DIR/efi/boot/bootx64.efi"

if [ -f "$ETFSBOOT" ] && [ -f "$EFIBOOT" ]; then
    # Dual boot (BIOS + UEFI)
    xorriso -as mkisofs \
        -iso-level 3 -full-iso9660-filenames \
        -eltorito-boot boot/etfsboot.com \
        -no-emul-boot -boot-load-size 8 \
        -eltorito-platform efi -eltorito-boot efi/boot/bootx64.efi \
        -no-emul-boot -boot-load-size 8 \
        -o "$OUTPUT_ISO" \
        "$ISO_DIR"
elif [ -f "$ETFSBOOT" ]; then
    # BIOS only
    xorriso -as mkisofs \
        -iso-level 3 -full-iso9660-filenames \
        -eltorito-boot boot/etfsboot.com \
        -no-emul-boot -boot-load-size 8 \
        -o "$OUTPUT_ISO" \
        "$ISO_DIR"
elif [ -f "$EFIBOOT" ]; then
    # UEFI only
    xorriso -as mkisofs \
        -iso-level 3 -full-iso9660-filenames \
        -eltorito-platform efi -eltorito-boot efi/boot/bootx64.efi \
        -no-emul-boot -boot-load-size 8 \
        -o "$OUTPUT_ISO" \
        "$ISO_DIR"
else
    echo "[ERROR] No boot files found in base ISO"
    ls -la "$ISO_DIR/boot/" "$ISO_DIR/efi/boot/" 2>/dev/null
    exit 1
fi

echo "[INFO] ISO created: $(du -h "$OUTPUT_ISO" | cut -f1)"

# ============================================================================
# Step 8: Cleanup
# ============================================================================
echo "[8/8] Cleanup..."
rm -rf "$MOUNT_DIR" "$ISO_DIR" "$ISO_MOUNT" "$WORK_DIR/iso_mount"
echo "[DONE] Output: $OUTPUT_ISO"
echo "[DONE] UUP cache: $UUP_FILES_DIR (persist for next run)"
