#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ ! -f "$ROOT/vendor/ComfyUI/main.py" ]]; then
  echo "Source cache missing. Run scripts/prepare-sources.sh or sync-sources.sh first." >&2
  exit 1
fi
"$ROOT/scripts/compose.sh" up -d --build
"$ROOT/scripts/healthcheck.sh"
echo "Canary passed. Existing ComfyUI services have not been stopped."
