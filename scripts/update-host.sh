#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
git pull --ff-only origin main
"$ROOT/scripts/compose.sh" build --pull
"$ROOT/scripts/compose.sh" up -d
"$ROOT/scripts/compose.sh" ps
