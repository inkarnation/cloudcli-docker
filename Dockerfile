# syntax=docker/dockerfile:1.24

FROM node:22-bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    PATH=/home/claude/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gosu \
      jq \
      openssh-client \
      ripgrep \
      tini \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

# Claude Code self-updates at runtime (writes to ~/.claude/local, which is a
# volume in our compose setup), so its image-build version is just a bootstrap
# and not pinned. CloudCLI has no auto-update, so we pin it explicitly.
# renovate: datasource=npm depName=@cloudcli-ai/cloudcli
ARG CLOUDCLI_VERSION=1.32.0
# typescript is bundled globally so CloudCLI plugins whose `npm run build` calls
# `tsc` directly (without listing it as a dependency) still work.
RUN npm install -g \
      @anthropic-ai/claude-code \
      @cloudcli-ai/cloudcli@${CLOUDCLI_VERSION} \
      typescript \
    && npm cache clean --force

ARG PUID=1000
ARG PGID=1000
# Drop the default `node` user from the base image and create `claude` with the
# requested UID/GID. Lets bind-mounted ./data inherit the host user's ownership.
RUN userdel -r node 2>/dev/null || true \
    && groupadd -g ${PGID} claude \
    && useradd -m -u ${PUID} -g ${PGID} -s /bin/bash claude

# /home/claude is fully bind-mounted at runtime (see compose), so we only need
# the user account here — the entrypoint mkdir's the data subdirs after the mount.
RUN chown claude:claude /home/claude

COPY --chmod=0755 scripts/cc-workspace /usr/local/bin/cc-workspace
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# Entrypoint runs as root, applies PUID/PGID env (if set), chowns the data
# dirs under $HOME, then drops to the claude user via gosu.
WORKDIR /home/claude/workspaces

ENV HOME=/home/claude \
    TZ=UTC \
    CLOUDCLI_HOST=0.0.0.0 \
    CLOUDCLI_PORT=3001 \
    WORKSPACES_DIR=/home/claude/workspaces

EXPOSE 3001

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["cloudcli"]
