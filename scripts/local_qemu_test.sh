#!/bin/bash
# local_qemu_test.sh - local KVM + iPXE + wimboot test launcher
# Usage: ./scripts/local_qemu_test.sh [timeout] [port] [normal|serial_bridge]

set -euo pipefail

TIMEOUT=${1:-180}
PORT=${2:-18080}
MODE=${3:-serial_bridge}

ROOT=/tmp/opencode/winpe_setup_http
IPXE_ISO=/tmp/opencode/ipxe.iso
WIMBOOT=/tmp/opencode/wimboot
SERIAL=/tmp/opencode/winpe_local_serial.log
RESULT_DIR=/tmp/opencode/winpe_result_drive
RESULT_LOG=$RESULT_DIR/pe_ci_result.log

rm -f "$SERIAL"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"
printf 'pecmd_compat WinPE CI result drive\n' > "$RESULT_DIR/PE_CI_RESULT_DRIVE.TAG"
case "$MODE" in
    normal)
        ;;
    serial_bridge)
        printf 'serial bridge\n' > "$RESULT_DIR/PE_CI_SERIAL_BRIDGE.TAG"
        ;;
    *)
        echo "[ERROR] Unknown mode: $MODE"
        echo "Usage: ./scripts/local_qemu_test.sh [timeout] [port] [normal|serial_bridge]"
        exit 1
        ;;
esac

if [ ! -f "$IPXE_ISO" ]; then
    echo "[ERROR] Missing cached iPXE ISO: $IPXE_ISO"
    exit 1
fi

if [ ! -f "$WIMBOOT" ] && [ ! -f "$ROOT/wimboot" ]; then
    echo "[ERROR] Missing cached wimboot: $WIMBOOT"
    exit 1
fi

if [ ! -f "$ROOT/wimboot" ]; then
    cp "$WIMBOOT" "$ROOT/wimboot"
    chmod +x "$ROOT/wimboot"
fi

for f in boot.wim bootmgr BCD boot.sdi; do
    if [ ! -f "$ROOT/$f" ]; then
        echo "[ERROR] Missing HTTP boot file: $ROOT/$f"
        exit 1
    fi
done

WIM_INDEX=1
if [ -f "$ROOT/wimboot.index" ]; then
    WIM_INDEX=$(tr -d '\r\n ' < "$ROOT/wimboot.index")
fi
if [ -z "$WIM_INDEX" ]; then
    WIM_INDEX=1
fi

# Always write boot.ipxe with the selected port. Reusing an older file can point
# iPXE at a stale HTTP server and boot the wrong WIM.
cat > "$ROOT/boot.ipxe" <<IPXE
#!ipxe
echo WINPE_CI_IPXE_START
dhcp || goto failed
set base http://10.0.2.2:$PORT
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

echo "[INFO] HTTP root: $ROOT"
echo "[INFO] Serial log: $SERIAL"
echo "[INFO] Timeout: ${TIMEOUT}s"
echo "[INFO] Mode: $MODE"
echo "[INFO] Starting QEMU..."

(cd "$ROOT" && python3 -m http.server "$PORT" --bind 0.0.0.0) > /dev/null 2>&1 &
HTTP_PID=$!
sleep 1

set +e
timeout "$TIMEOUT" qemu-system-x86_64 \
    -M pc -accel kvm -cpu host -m 2048 \
    -display gtk -vga std -no-reboot \
    -cdrom "$IPXE_ISO" -boot d \
    -netdev user,id=n0,tftp="$ROOT",bootfile=boot.ipxe \
    -device e1000,netdev=n0 \
    -drive file=fat:rw:"$RESULT_DIR",format=raw,if=ide,media=disk \
    -serial file:"$SERIAL" -monitor none \
    > /dev/null 2>&1
STATUS=$?
set -e

kill "$HTTP_PID" 2>/dev/null || true
wait "$HTTP_PID" 2>/dev/null || true

echo ""
echo "=== QEMU exit: $STATUS ==="
echo "=== Result log: ${RESULT_LOG} ==="
cat "$RESULT_LOG" 2>/dev/null || true
echo "=== Serial: $(wc -c < "$SERIAL" 2>/dev/null || echo 0) bytes ==="
cat "$SERIAL" 2>/dev/null || true
