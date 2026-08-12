#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${CUSTOM_NODES_DIR:-${COMFYUI_DATA_DIR:-/srv/comfyui}/custom_nodes}"
LOCK="${CUSTOM_NODES_LOCK:-$ROOT/config/custom-nodes.lock}"
mkdir -p "$TARGET"

while IFS='|' read -r name url ref; do
  [[ -z "${name}" || "${name:0:1}" == "#" ]] && continue
  dest="$TARGET/$name"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" checkout --detach -q FETCH_HEAD
  else
    git init -q "$dest"
    git -C "$dest" remote add origin "$url"
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" checkout --detach -q FETCH_HEAD
  fi
done < "$LOCK"
