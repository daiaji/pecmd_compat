#!/bin/bash
# Download the latest peshell_minimal Windows CI artifact for local WinPE tests.

set -euo pipefail

REPO=${PESHELL_REPO:-daiaji/peshell_minimal}
ARTIFACT=${PESHELL_ARTIFACT:-peshell-release}
DEST=${1:-/tmp/opencode/peshell_artifact}

rm -rf "$DEST"
mkdir -p "$DEST"

echo "[INFO] Downloading artifact '$ARTIFACT' from $REPO to $DEST"
gh run download --repo "$REPO" --name "$ARTIFACT" --dir "$DEST"

if [ ! -f "$DEST/bin/peshell.exe" ]; then
    echo "[ERROR] Artifact does not contain bin/peshell.exe: $DEST"
    exit 1
fi

if [ ! -f "$DEST/bin/cimgui.dll" ]; then
    echo "[WARN] Artifact does not contain bin/cimgui.dll; GUI native smoke will be skipped or fail."
fi

echo "[DONE] PEShell artifact ready: $DEST"
