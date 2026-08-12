#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  /data/input \
  /data/output \
  /data/temp \
  /data/user/default

args=(
  --listen "${COMFYUI_HOST:-0.0.0.0}"
  --port "${CONTAINER_PORT:-8188}"
  --input-directory /data/input
  --output-directory /data/output
  --temp-directory /data/temp
  --user-directory /data/user
  --database-url sqlite:////data/user/comfyui.db
  --extra-model-paths-config /opt/config/extra_model_paths.yaml
)

if [[ "${ENABLE_MANAGER:-1}" == "1" ]]; then
  args+=(--enable-manager)
fi

exec python3 /opt/ComfyUI/main.py "${args[@]}"
