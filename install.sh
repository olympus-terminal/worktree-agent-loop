#!/bin/bash
# Install p-ralph by symlinking bin/p-ralph into ~/.local/bin.
# Run from the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${HOME}/.local/bin"
mkdir -p "$BIN"

chmod +x "${ROOT}/bin/p-ralph"
chmod +x "${ROOT}/lib/install_merge_drivers.sh"
chmod +x "${ROOT}/lib/resolve_with_claude.sh"
chmod +x "${ROOT}/lib/merge_drivers/plan.py"
chmod +x "${ROOT}/lib/merge_drivers/activity.py"

ln -sf "${ROOT}/bin/p-ralph" "${BIN}/p-ralph"

echo "installed: ${BIN}/p-ralph -> ${ROOT}/bin/p-ralph"
case ":$PATH:" in
    *":${BIN}:"*) ;;
    *) echo "note: ${BIN} is not on PATH. Add:  export PATH=\"${BIN}:\$PATH\"" ;;
esac
