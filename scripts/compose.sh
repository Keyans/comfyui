#!/usr/bin/env bash
set -euo pipefail

if docker info >/dev/null 2>&1; then
  exec docker compose "$@"
fi

if sudo -n docker info >/dev/null 2>&1; then
  exec sudo docker compose "$@"
fi

echo "Docker is unavailable. Grant this user Docker access or passwordless sudo for Docker." >&2
exit 1
