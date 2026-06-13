# cloudcli-docker

[![Build & publish image](https://github.com/inkarnation/cloudcli-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/inkarnation/cloudcli-docker/actions/workflows/docker-publish.yml)
[![GHCR image](https://img.shields.io/badge/ghcr.io-inkarnation%2Fcloudcli--docker-blue?logo=github)](https://github.com/inkarnation/cloudcli-docker/pkgs/container/cloudcli-docker)
[![Platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%7C%20linux%2Farm64-lightgrey)](https://github.com/inkarnation/cloudcli-docker/pkgs/container/cloudcli-docker)

Self-hostable Docker image for [**CloudCLI**](https://github.com/siteboon/claudecodeui) — the web UI for
[Claude Code](https://docs.anthropic.com/en/docs/claude-code). Run it on a VPS, point your browser at it,
and you have Claude Code with a usable UI, persistent sessions, and multiple project workspaces.

> **Unofficial / community-maintained.** This repository packages CloudCLI and Claude Code into a Docker
> image for convenience. It is **not affiliated with Siteboon AI B.V. or Anthropic.** See
> [License](#license) for important notes on the AGPL terms that apply to the built image.

The image bundles:

- `@cloudcli-ai/cloudcli` (pinned) — the web UI
- `@anthropic-ai/claude-code` — the agent, self-updates at runtime
- `typescript` (global) — for CloudCLI plugins whose build calls `tsc`
- [`mise`](https://mise.jdx.dev) — universal toolchain version manager (install Java, Python, Go… per workspace)
- `build-essential`, `pkg-config`, `unzip`, `xz-utils` — needed for native modules and toolchain builds
- `git`, `ripgrep`, `jq`, `openssh-client`, `tini`, `gosu`
- Node 22 on Debian bookworm-slim
- Multi-arch: `linux/amd64` and `linux/arm64`

## Quick start

```bash
mkdir -p ./data
docker run -d \
  --name cloudcli \
  -p 127.0.0.1:3001:3001 \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e PUID=$(id -u) -e PGID=$(id -g) \
  -v "$PWD/data:/home/claude" \
  --restart unless-stopped \
  ghcr.io/inkarnation/cloudcli-docker:latest
```

Then open <http://127.0.0.1:3001>.

No API key handy? Skip `-e ANTHROPIC_API_KEY` and log in interactively after start:

```bash
docker exec -it cloudcli claude login
```

### Or with docker compose

```bash
git clone https://github.com/inkarnation/cloudcli-docker.git
cd cloudcli-docker
cp .env.example .env      # set ANTHROPIC_API_KEY, PUID/PGID, TZ
docker compose up -d
```

The shipped `docker-compose.yml` builds locally. To pull the published image instead, replace the
`build:` block with `image: ghcr.io/inkarnation/cloudcli-docker:latest`.

## Configuration

| Variable            | Default       | Purpose                                                            |
| ------------------- | ------------- | ------------------------------------------------------------------ |
| `ANTHROPIC_API_KEY` | *(empty)*     | Claude API key. If unset, log in via `claude login`.               |
| `PUID` / `PGID`     | `1000`        | UID/GID of the in-container `claude` user. Match your host owner.  |
| `TZ`                | `UTC`         | Container timezone.                                                |
| `CLOUDCLI_BIND`     | `127.0.0.1`   | Host bind address for the published port.                          |
| `CLOUDCLI_PORT`     | `3001`        | Published port on the host.                                        |

A single volume at `/home/claude` captures everything the container persists:

```
data/
├── workspaces/   project trees
├── .claude/      Claude Code sessions, plugins, MCP, skills, credentials
├── .claude.json  global Claude config / MCP server registry
└── .cloudcli/    CloudCLI's SQLite DB (users, projects, UI prefs)
```

Back up `./data` and you've backed up everything.

## Workspaces

Workspaces are subdirectories under `/home/claude/workspaces`. The bundled `cc-workspace` helper
creates/lists/removes them. Run it inside the container, or from the host via `docker exec`.

```bash
# Create
docker exec -it cloudcli cc-workspace create project-a --git
docker exec -it cloudcli cc-workspace create project-b --template /home/claude/workspaces/_template

# List / remove
docker exec -it cloudcli cc-workspace list
docker exec -it cloudcli cc-workspace remove project-a

# Handy host alias
alias ccw='docker exec -it cloudcli cc-workspace'
```

In the UI: **Open Project** → pick `/home/claude/workspaces/<name>`.

### Isolation model

Workspaces are directories, not sandboxes. Claude Code honors its `cwd`, so tool calls (`Read`,
`Edit`, `Bash`) operate inside the project folder by default. Cross-project access is technically
possible (all workspaces share one container filesystem) but constrained by convention and per-project
`CLAUDE.md` rules. This matches CloudCLI's native single-`~/.claude` model.

## Toolchains per workspace

The base image deliberately ships **only Node 22**. For everything else — JDK, Maven, Python, Go,
Rust, Ruby, additional Node versions — use [mise](https://mise.jdx.dev) inside the workspace:

```bash
docker exec -it cloudcli bash
cd ~/workspaces/my-java-project
mise use java@21 maven@3.9
mvn --version
```

`mise use` writes a `.mise.toml` to the workspace, so the toolchain is pinned per project and
visible in the repo. Toolchains install into `~/.local/share/mise/`, which lives in the persistent
`./data` volume — once installed, they survive container restarts and `docker compose pull`.

The mise shim directory is on `PATH` by default, so `java`, `mvn`, `python` etc. work directly in
the integrated UI terminal and in Claude Code's `Bash` tool without further activation.

If a workspace already has a `.mise.toml`, `mise install` (no args) materializes everything in one
shot:

```bash
cd ~/workspaces/some-cloned-repo
mise install
```

The image also seeds a global `~/.claude/CLAUDE.md` on first start so Claude Code itself knows to
reach for `mise` (and not `apt-get`) when a project needs a JDK or other toolchain. The seed only
runs when the file is missing — your edits are preserved across image upgrades. To see the source
template before it gets copied, check `templates/global-CLAUDE.md` in this repo.

## Putting it on the internet

The container binds to `127.0.0.1` by default. **Don't** expose port 3001 publicly — CloudCLI has no
built-in multi-user auth. Terminate TLS and add auth in a reverse proxy:

```caddyfile
cloudcli.example.com {
    reverse_proxy 127.0.0.1:3001
    basic_auth {
        you $2a$14$replace_with_caddy_hash_password_output
    }
}
```

Equivalents in Traefik / nginx / Authelia / Tailscale work the same way — the only requirement is
that *something* upstream gates access.

## Build from source

```bash
docker build -t cloudcli-docker:dev .
# Pin a different CloudCLI version:
docker build --build-arg CLOUDCLI_VERSION=1.32.0 -t cloudcli-docker:dev .
```

The GitHub Actions workflow at `.github/workflows/docker-publish.yml` builds multi-arch images and
pushes to GHCR on tag pushes matching `v*.*.*`.

## Versioning

Image tags follow the repo's git tags (`vMAJOR.MINOR.PATCH`):

- `latest` — most recent release
- `1.2`, `1.2.3` — semver tags
- `sha-<short>` — per-release commit pin

CloudCLI itself is pinned via the `CLOUDCLI_VERSION` build arg (no upstream auto-update).
Claude Code self-updates inside the container — its CLI lives under `~/.claude/local` (volume-backed),
so updates persist across container restarts.

## Troubleshooting

**Permission errors on `./data`** — set `PUID`/`PGID` to `id -u`/`id -g` of the host owner. The
entrypoint re-maps the in-container `claude` user at startup.

**"No ANTHROPIC_API_KEY"** banner in logs — either set the env var or run `claude login` once
(credentials persist in `./data/.claude/.credentials.json`).

**UI shows no projects** — projects only appear after you click *Open Project* on a workspace at
least once. `cc-workspace create` just makes the directory.

## Credits

- **CloudCLI** (UI) — [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui)
- **Claude Code** — [Anthropic](https://docs.anthropic.com/en/docs/claude-code)

This repo only packages and configures the above; it is not affiliated with either project.

## License

This repository uses **two different licenses** depending on what you are looking at:

### The packaging in this repo — MIT

The Dockerfile, `docker-compose.yml`, `scripts/`, GitHub Actions workflows, and documentation are
released under the [MIT License](./LICENSE). Fork, adapt, redistribute freely.

### The built Docker image — AGPL-3.0-or-later

The image bundles **CloudCLI** ([`@cloudcli-ai/cloudcli`](https://github.com/siteboon/claudecodeui)),
which is licensed under the **GNU Affero General Public License v3.0 or later** with additional terms
under Section 7. If you:

- **Distribute the built image** (e.g. push your own fork to a registry), or
- **Run it as a publicly accessible network service** (e.g. host it for others)

…you must comply with the AGPL. The key obligation most people miss is **AGPL § 13**: anyone
interacting with the service over a network must be able to obtain the corresponding source code of
the version you are running, including any modifications. For an unmodified deployment of the
upstream code, linking to [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) and the
exact version (see `CLOUDCLI_VERSION` in the Dockerfile) is generally sufficient.

The Section 7 additional terms also reserve the **"Siteboon" and "CloudCLI" names** for the upstream
project — don't use them for promotional purposes for your fork without written permission from
Siteboon AI B.V.

**Claude Code** (`@anthropic-ai/claude-code`) is distributed under its own terms by Anthropic.

If you are just running the image privately for yourself (no public network exposure, no
redistribution), none of the AGPL distribution clauses apply to you — use it freely.

> This is a summary, not legal advice. Read the upstream
> [LICENSE](https://github.com/siteboon/claudecodeui/blob/main/LICENSE) and
> [NOTICE](https://github.com/siteboon/claudecodeui/blob/main/NOTICE) files for the authoritative text.
