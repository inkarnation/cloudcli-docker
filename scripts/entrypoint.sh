#!/usr/bin/env bash
set -euo pipefail

WORKSPACES_DIR="${WORKSPACES_DIR:-/workspaces}"

# Ensure expected dirs exist (they may be empty bind mounts on first start).
mkdir -p "${WORKSPACES_DIR}" "${HOME}/.claude" "${HOME}/.config"

# If a host docker socket is mounted, align the in-container 'docker' group
# with the socket's gid so the claude user can talk to it. Requires sudo
# (NOPASSWD configured in the image) and is a no-op when no socket is mounted.
SOCKET=/var/run/docker.sock
if [ -S "${SOCKET}" ]; then
  SOCKET_GID="$(stat -c '%g' "${SOCKET}")"
  if ! getent group docker >/dev/null; then
    sudo groupadd -g "${SOCKET_GID}" docker || true
  fi
  CURRENT_GID="$(getent group docker | cut -d: -f3 || echo '')"
  if [ "${CURRENT_GID}" != "${SOCKET_GID}" ]; then
    sudo groupmod -g "${SOCKET_GID}" docker || true
  fi
  if ! id -nG claude | grep -qw docker; then
    sudo usermod -aG docker claude
  fi
  # Re-exec under the updated group membership so 'docker' commands work
  # without requiring the user to log out and back in.
  if ! id -nG | grep -qw docker; then
    exec sudo -E -u claude -g docker -- "$0" "$@"
  fi
fi

# Bootstrap: if no API key is set and ~/.claude is empty, point this out once.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -e "${HOME}/.claude/.credentials.json" ]; then
  echo "[entrypoint] No ANTHROPIC_API_KEY set and ~/.claude/.credentials.json missing."
  echo "[entrypoint] You can log in via 'docker exec -it <container> claude login' or set ANTHROPIC_API_KEY."
fi

exec "$@"
