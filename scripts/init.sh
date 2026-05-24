#!/usr/bin/env bash
# One-time host-side bootstrap. Run before the first `docker compose up`.
#
# Creates the bind-mount targets so Docker doesn't auto-create them with the
# wrong type (in particular: a non-existent `.claude.json` would otherwise be
# created as a directory and break Claude Code).
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p workspaces claude-home cloudcli-data
[ -e claude.json ] || echo '{}' > claude.json

echo "[init] bind-mount targets ready:"
ls -la workspaces claude-home cloudcli-data claude.json
echo "[init] now run: docker compose up -d"
