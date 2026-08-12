#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

PORT="${COMFYUI_PORT:-8288}"
curl --fail --silent --show-error \
  "http://127.0.0.1:${PORT}/system_stats" \
  | python3 -m json.tool >/dev/null
echo "ComfyUI healthy on port ${PORT}"
