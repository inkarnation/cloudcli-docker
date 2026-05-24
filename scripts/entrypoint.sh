#!/usr/bin/env bash
set -euo pipefail

CLAUDE_HOME="/home/claude"
WORKSPACES_DIR="${WORKSPACES_DIR:-${CLAUDE_HOME}/workspaces}"
CLAUDE_JSON="${CLAUDE_HOME}/.claude.json"

# This entrypoint always starts as root so it can:
#   - remap the in-container `claude` user's UID/GID to match the host owner
#     of bind-mounted volumes (avoids EACCES on bind mounts)
#   - chown the relevant data dirs once
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

  # Bind-mount gotcha: if the host side of `.claude.json` doesn't exist before
  # `docker compose up`, Docker creates a *directory* at that mount target.
  # Catch this early with a clear message instead of letting Claude Code fail
  # mysteriously later.
  if [ -d "${CLAUDE_JSON}" ]; then
    echo "[entrypoint] ERROR: ${CLAUDE_JSON} is a directory, not a file."
    echo "[entrypoint] This happens when Docker bind-mounts a non-existent host file."
    echo "[entrypoint] Fix on the host: 'touch <your-claude.json-host-path>' then restart."
    exit 1
  fi

  mkdir -p \
    "${WORKSPACES_DIR}" \
    "${CLAUDE_HOME}/.claude" \
    "${CLAUDE_HOME}/.cloudcli" \
    "${CLAUDE_HOME}/.config"
  [ -e "${CLAUDE_JSON}" ] || touch "${CLAUDE_JSON}"

  # Granular chown: top-level home + each data dir (recursive for the dot-dirs
  # which hold deep state, single-level for workspaces so large project trees
  # aren't re-chowned on every container start).
  chown    "${TARGET_UID}:${TARGET_GID}" "${CLAUDE_HOME}" "${WORKSPACES_DIR}" "${CLAUDE_JSON}"
  chown -R "${TARGET_UID}:${TARGET_GID}" "${CLAUDE_HOME}/.claude" "${CLAUDE_HOME}/.cloudcli" "${CLAUDE_HOME}/.config"

  exec gosu claude "$0" "$@"
fi

# Past this point we run as the (possibly remapped) claude user.
mkdir -p "${WORKSPACES_DIR}" "${HOME}/.claude" "${HOME}/.cloudcli" "${HOME}/.config"

if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -e "${HOME}/.claude/.credentials.json" ]; then
  echo "[entrypoint] No ANTHROPIC_API_KEY set and ~/.claude/.credentials.json missing."
  echo "[entrypoint] Run 'docker exec -it <container> claude login' or set ANTHROPIC_API_KEY."
fi

exec "$@"
