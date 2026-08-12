#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-}"

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "Usage: $0 /absolute/path/to/instance.env" >&2
  exit 1
fi

cd "$ROOT"
"$ROOT/scripts/compose.sh" --env-file "$ENV_FILE" down
