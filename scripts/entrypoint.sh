#!/usr/bin/env bash
set -euo pipefail

WORKSPACES_DIR="${WORKSPACES_DIR:-/workspaces}"

# Ensure expected dirs exist (they may be empty bind mounts on first start).
mkdir -p "${WORKSPACES_DIR}" "${HOME}/.claude" "${HOME}/.config"

# Bootstrap: if no API key is set and ~/.claude is empty, point this out once.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -e "${HOME}/.claude/.credentials.json" ]; then
  echo "[entrypoint] No ANTHROPIC_API_KEY set and ~/.claude/.credentials.json missing."
  echo "[entrypoint] Run 'docker exec -it <container> claude login' or set ANTHROPIC_API_KEY."
fi

exec "$@"
