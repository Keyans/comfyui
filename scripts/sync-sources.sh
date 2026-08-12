#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 user@host:/absolute/path [user@host:/absolute/path ...]" >&2
  exit 1
fi

"$ROOT/scripts/prepare-sources.sh"

for target in "$@"; do
  rsync -a --delete --exclude='.git/' \
    "$ROOT/vendor/" "$target/vendor/"
done
