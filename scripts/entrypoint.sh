#!/usr/bin/env bash
set -euo pipefail

CLAUDE_HOME="/home/claude"
WORKSPACES_DIR="${WORKSPACES_DIR:-${CLAUDE_HOME}/workspaces}"

# This entrypoint always starts as root so it can:
#   - remap the in-container `claude` user's UID/GID to match the host owner
#     of the bind-mounted /home/claude volume (avoids EACCES)
#   - create + chown the data dirs on first start
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

  mkdir -p \
    "${WORKSPACES_DIR}" \
    "${CLAUDE_HOME}/.claude" \
    "${CLAUDE_HOME}/.cloudcli" \
    "${CLAUDE_HOME}/.config"
  # Claude Code parses ~/.claude.json as JSON; a 0-byte file would error.
  # Seed with empty object if missing or empty.
  if [ ! -s "${CLAUDE_HOME}/.claude.json" ]; then
    echo '{}' > "${CLAUDE_HOME}/.claude.json"
  fi
  # Seed the global CLAUDE.md so Claude Code knows about mise + container
  # conventions. Only on first start — user edits afterwards are preserved.
  if [ ! -e "${CLAUDE_HOME}/.claude/CLAUDE.md" ] && [ -f /etc/cloudcli/global-CLAUDE.md ]; then
    cp /etc/cloudcli/global-CLAUDE.md "${CLAUDE_HOME}/.claude/CLAUDE.md"
  fi

  # Granular chown: recursive for dot-dirs that hold deep state, single-level
  # for workspaces so large project trees aren't re-chowned on every restart.
  chown    "${TARGET_UID}:${TARGET_GID}" "${CLAUDE_HOME}" "${WORKSPACES_DIR}" "${CLAUDE_HOME}/.claude.json"
  chown -R "${TARGET_UID}:${TARGET_GID}" "${CLAUDE_HOME}/.claude" "${CLAUDE_HOME}/.cloudcli" "${CLAUDE_HOME}/.config"

  exec gosu claude "$0" "$@"
fi

# Past this point we run as the (possibly remapped) claude user.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -e "${HOME}/.claude/.credentials.json" ]; then
  echo "[entrypoint] No ANTHROPIC_API_KEY set and ~/.claude/.credentials.json missing."
  echo "[entrypoint] Run 'docker exec -it <container> claude login' or set ANTHROPIC_API_KEY."
fi

exec "$@"
