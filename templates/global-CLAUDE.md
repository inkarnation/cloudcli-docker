# Container conventions

This Claude Code instance runs inside the
[`cloudcli-docker`](https://github.com/inkarnation/cloudcli-docker) image. A few
things differ from a bare Linux dev box — keep them in mind when picking tools.

## Toolchains: use `mise`, not `apt`

The base image ships **only Node 22**. For everything else — JDK, Maven/Gradle,
Python, Go, Rust, Ruby, additional Node versions — install per workspace with
[mise](https://mise.jdx.dev):

```bash
cd <workspace>
mise use java@21 maven@3.9   # pin into .mise.toml (commit it)
mise install                  # materialize what .mise.toml declares
java --version                # available immediately, shim is on PATH
```

Installs land under `~/.local/share/mise/` (volume-backed) and persist across
container restarts and `docker compose pull`.

**Do not** try `apt-get install` for toolchains — the container runs as the
unprivileged `claude` user and the install wouldn't survive a `docker compose
pull` anyway. If something genuinely needs a system package, ask the user to add
it to the image upstream rather than patching the running container.

## Filesystem layout

- `/home/claude/workspaces/<name>/` — project trees. Operate inside the workspace
  you were opened in; cross-workspace access is technically possible but treat
  it as out-of-scope unless explicitly asked.
- `/home/claude/.claude/` — your own sessions, plugins, MCP servers, skills. Edit
  via the UI when possible.
- `/home/claude/.cloudcli/` — CloudCLI's database. Don't touch directly.

The entire `/home/claude` tree is on a persistent volume, so anything written
there outlives the container.

## Network and secrets

You have outbound internet from the container. Inbound access goes through the
CloudCLI UI (port 3001) and whatever reverse proxy the user has in front of it —
don't bind extra ports without asking.

For API keys, prefer reading from `process.env` / shell env vars (the user sets
them in their compose). Don't write credentials into project files.
