# syntax=docker/dockerfile:1.7

FROM node:22-bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    PATH=/home/claude/.local/bin:/usr/local/bin:/usr/bin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      ripgrep \
      tini \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
ARG CLOUDCLI_VERSION=latest
RUN npm install -g \
      @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
      @cloudcli-ai/cloudcli@${CLOUDCLI_VERSION} \
    && npm cache clean --force

ARG USER_UID=1000
ARG USER_GID=1000
# Drop the default `node` user from the base image and create `claude` with the
# requested UID/GID. Lets bind-mounted ./data inherit the host user's ownership.
RUN userdel -r node 2>/dev/null || true \
    && groupadd -g ${USER_GID} claude \
    && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash claude

RUN mkdir -p /workspaces /home/claude/.claude /home/claude/.config \
    && chown -R claude:claude /workspaces /home/claude

COPY --chmod=0755 scripts/cc-workspace /usr/local/bin/cc-workspace
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

USER claude
WORKDIR /workspaces

ENV HOME=/home/claude \
    TZ=UTC \
    CLOUDCLI_HOST=0.0.0.0 \
    CLOUDCLI_PORT=3001 \
    WORKSPACES_DIR=/workspaces

EXPOSE 3001

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["cloudcli"]
