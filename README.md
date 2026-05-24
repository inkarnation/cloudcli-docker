# cloudcli-setup

Containerized [CloudCLI UI](https://github.com/siteboon/claudecodeui) (web UI for Claude Code)
for self-hosting on a VPS. The image bundles `@cloudcli-ai/cloudcli`,
`@anthropic-ai/claude-code`, Git, and the Docker CLI on Node 22 (Debian slim).
Workspaces live as subdirectories under `/workspaces` and are persisted to the host via a
bind mount.

What's in this repo:

- `Dockerfile` — image build
- `scripts/cc-workspace` — helper to create/list/remove workspaces
- `scripts/entrypoint.sh` — bootstrap hints (e.g. missing API key)
- `docker-compose.yml` — local run
- `.github/workflows/docker-publish.yml` — multi-arch publish to GHCR

## Quick start (local)

```bash
cp .env.example .env
# set ANTHROPIC_API_KEY (or log in interactively after start)
docker compose up -d
open http://127.0.0.1:3001
```

On first start:

```bash
# If no API key is set, log in interactively:
docker exec -it cloudcli claude login
```

## Managing workspaces

`cc-workspace` works both from the in-UI terminal and from the host.

```bash
# From the host
docker exec -it cloudcli cc-workspace create project-a --git
docker exec -it cloudcli cc-workspace list
docker exec -it cloudcli cc-workspace remove project-a

# Handy host alias
alias ccw='docker exec -it cloudcli cc-workspace'
ccw create project-b --template /workspaces/_template
```

Then in the UI hit "Open Project" → pick `/workspaces/<name>`. Claude Code creates its
session data under `~/.claude/projects/...` and CloudCLI picks the project up
automatically.

### Isolation model

Workspaces are directories. Claude Code honors its `cwd`, so tool
calls (`Read`, `Edit`, `Bash`) operate inside the project folder by default. Cross-project
access is technically possible (all workspaces share one container filesystem
namespace) but constrained by convention and per-project `CLAUDE.md` rules. This matches
CloudCLI's native single-`~/.claude` model.

## Deploying behind a reverse proxy (Caddy)

```caddyfile
cloudcli.example.com {
    reverse_proxy cloudcli:3001
    # Optional: front with basic-auth or mTLS — the UI itself has no multi-user auth layer.
    # basicauth { john $2a$14$... }
}
```


## Tests / verification

Locally:

```bash
# Build
docker compose build

# Start
docker compose up -d

# Create a workspace and inspect it
docker exec -it cloudcli cc-workspace create demo --git
docker exec -it cloudcli cc-workspace list   # → demo

# Logs
docker compose logs -f cloudcli
```

UI: http://127.0.0.1:3001 — "Open Project" → `/workspaces/demo`.

## License / sources

- CloudCLI UI: [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui)
- Claude Code: [Anthropic](https://docs.anthropic.com/en/docs/claude-code)
