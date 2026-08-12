#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

PORT="${COMFYUI_PORT:-8288}"
for attempt in $(seq 1 36); do
  if response="$(curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${PORT}/system_stats" 2>/dev/null)" \
    && python3 -m json.tool >/dev/null <<<"$response"; then
    echo "ComfyUI healthy on port ${PORT}"
    exit 0
  fi
  sleep 5
done

echo "ComfyUI did not become healthy on port ${PORT} within 180 seconds." >&2
exit 1
