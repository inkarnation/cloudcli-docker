#!/usr/bin/env bash
set -euo pipefail

WORKSPACES_DIR="${WORKSPACES_DIR:-/workspaces}"
CLAUDE_HOME="/home/claude"

# This entrypoint always starts as root so it can:
#   - remap the in-container `claude` user's UID/GID to match the host owner
#     of bind-mounted volumes (avoids EACCES on ./claude-home, ./workspaces)
#   - chown those dirs once
#   - drop privileges to `claude` via gosu and exec the command
#
# Runtime knobs (set in `environment:` of your compose):
#   PUID  desired UID for the claude user (default: image's build-time UID)
#   PGID  desired GID for the claude group (default: image's build-time GID)
if [ "$(id -u)" = "0" ]; then
  CURRENT_UID="$(id -u claude)"
  CURRENT_GID="$(id -g claude)"
  TARGET_UID="${PUID:-${CURRENT_UID}}"
  TARGET_GID="${PGID:-${CURRENT_GID}}"

  if [ "${TARGET_GID}" != "${CURRENT_GID}" ]; then
    groupmod -o -g "${TARGET_GID}" claude
  fi
  if [ "${TARGET_UID}" != "${CURRENT_UID}" ]; then
    usermod -o -u "${TARGET_UID}" claude
  fi

  mkdir -p "${WORKSPACES_DIR}" "${CLAUDE_HOME}/.claude" "${CLAUDE_HOME}/.config"

  # Only chown the top-level + immediate children to keep startup fast on
  # large workspace trees. The `claude` user owns its home recursively because
  # tools (plugins, sessions) need write access deep inside .claude.
  chown "${TARGET_UID}:${TARGET_GID}" "${WORKSPACES_DIR}"
  chown -R "${TARGET_UID}:${TARGET_GID}" "${CLAUDE_HOME}"

  exec gosu claude "$0" "$@"
fi

# Past this point we run as the (possibly remapped) claude user.
mkdir -p "${WORKSPACES_DIR}" "${HOME}/.claude" "${HOME}/.config"

if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -e "${HOME}/.claude/.credentials.json" ]; then
  echo "[entrypoint] No ANTHROPIC_API_KEY set and ~/.claude/.credentials.json missing."
  echo "[entrypoint] Run 'docker exec -it <container> claude login' or set ANTHROPIC_API_KEY."
fi

exec "$@"
