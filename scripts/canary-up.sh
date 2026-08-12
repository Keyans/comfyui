#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/compose.sh" up -d --build
"$ROOT/scripts/healthcheck.sh"
echo "Canary passed. Existing ComfyUI services have not been stopped."
