#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-}"

if [[ -z "$ENV_FILE" ]]; then
  echo "Usage: $0 /absolute/path/to/instance.env" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

cd "$ROOT"
"$ROOT/scripts/compose.sh" --env-file "$ENV_FILE" up -d

set -a
source "$ENV_FILE"
set +a

PORT="${COMFYUI_PORT:?COMFYUI_PORT is required}"
for attempt in $(seq 1 36); do
  if curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${PORT}/system_stats" >/dev/null 2>&1; then
    echo "ComfyUI instance is healthy on port ${PORT}"
    exit 0
  fi
  sleep 5
done

echo "ComfyUI did not become healthy on port ${PORT} within 180 seconds." >&2
exit 1
