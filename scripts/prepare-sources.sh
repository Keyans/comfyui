#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
COMFYUI_LOCK="$ROOT/config/comfyui.lock"
CUSTOM_NODES_LOCK="$ROOT/config/custom-nodes.lock"

fetch_commit() {
  local url="$1"
  local commit="$2"
  local dest="$3"
  local attempt

  if [[ ! -d "$dest/.git" ]]; then
    mkdir -p "$(dirname "$dest")"
    git init -q "$dest"
    git -C "$dest" remote add origin "$url"
  fi

  for attempt in 1 2 3; do
    if git -c http.version=HTTP/1.1 -C "$dest" \
      fetch --depth 1 origin "$commit"; then
      break
    fi
    if [[ "$attempt" -eq 3 ]]; then
      echo "Unable to fetch $url at $commit after $attempt attempts." >&2
      exit 1
    fi
    sleep $((attempt * 3))
  done

  git -C "$dest" checkout --detach -q FETCH_HEAD

  local actual
  actual="$(git -C "$dest" rev-parse HEAD)"
  if [[ "$actual" != "$commit" ]]; then
    echo "Source verification failed for $dest: expected $commit, got $actual" >&2
    exit 1
  fi
}

IFS='|' read -r comfyui_url comfyui_commit < <(
  grep -v '^[[:space:]]*#' "$COMFYUI_LOCK" | grep -v '^[[:space:]]*$'
)
fetch_commit "$comfyui_url" "$comfyui_commit" "$VENDOR/ComfyUI"

while IFS='|' read -r name url commit; do
  [[ -z "${name}" || "${name:0:1}" == "#" ]] && continue
  fetch_commit "$url" "$commit" "$VENDOR/custom_nodes/$name"
done < "$CUSTOM_NODES_LOCK"

echo "Verified source cache prepared in $VENDOR"
