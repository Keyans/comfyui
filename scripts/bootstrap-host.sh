#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
fi

set -a
source "$ROOT/.env"
set +a

DATA="${COMFYUI_DATA_DIR:-/srv/comfyui}"
mkdir -p "$DATA"/{models,input,output,temp,user}
"$ROOT/scripts/compose.sh" -f "$ROOT/docker-compose.yml" config >/dev/null
echo "Bootstrap complete. Review $ROOT/.env before starting the canary service."
