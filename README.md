# Confined Claude

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) inside isolated Docker containers — one image, as many parallel projects as you need. No sudo required.

Each project gets its own sandboxed environment with persistent Python virtual environments and tools. Auth credentials are copied from your host on each launch, but the container maintains its **own** plugin and marketplace ecosystem — your host `~/.claude/` is never mounted and never modified.

![cover image](./confined_claude.png)

## Why

Claude Code is powerful but runs directly on your machine. **Confined Claude** wraps it in a Docker container so that:

- **Nothing touches your host** — packages, tools, and file changes stay inside the container
- **Projects are isolated** — each directory gets its own venvs and tools
- **Config is isolated** — the container has its own plugins and marketplaces
- **Credentials carry over** — auth is copied (not mounted) so you don't re-login
- **File permissions just work** — container runs as your host UID/GID
- **Parallel instances work** — run Claude on multiple projects simultaneously
- **No root needed** — installs entirely in your home directory

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Your user in the `docker` group:
  ```bash
  sudo usermod -aG docker $(whoami)
  # then log out and back in
  ```

## Quick Start

```bash
git clone https://github.com/rafdouglas/confined-claude.git
cd confined-claude
./install.sh
exec bash

cd ~/my-project
confined-claude
```

## How It Works

### Isolation model

```
Host                                Container
~/.claude/                          /home/claude/.claude/
  settings.json  ──── copied ────>    settings.json (first run only)
  credentials.json ── copied ────>    credentials.json (every launch)
  plugins/       NOT mounted          plugins/        (container's own)
  marketplaces/  NOT mounted          marketplaces/   (container's own)
```

- **Auth credentials** are copied from host `~/.claude/` on each launch
- **Settings** are copied only on first run (so container-specific tweaks persist)
- **Plugins and marketplaces** are the container's own — install them separately inside the container with `/plugin`
- **Host `~/.claude/`** is never mounted and never modified by the container

### Directory layout

```
~/.local/share/confined-claude/       installed by install.sh
  confined-claude.sh                  the runner (aliased)
  Dockerfile                          single image definition
  shared/
    pip-cache/                        reused across all container instances
    claude-config/                    container's own ~/.claude/
                                      (plugins, marketplaces, settings)

~/any/project/
  your-code/
  .confined-claude/                   created per-project (auto-gitignored)
    venvs/                            Python virtual environments
    local-bin/                        project-specific CLI tools
```

### Volume mapping

| Host | Container | Scope |
|---|---|---|
| `./` (project dir) | `/home/claude/workspace` | per-project |
| `.confined-claude/venvs/` | `/home/claude/venvs` | per-project |
| `.confined-claude/local-bin/` | `/home/claude/.local/bin` | per-project |
| `shared/claude-config/` | `/home/claude/.claude` | shared (container's own config) |
| `shared/pip-cache/` | `/home/claude/.cache/pip` | shared |
| `~/.gitconfig` | `/home/claude/.gitconfig` (read-only) | shared (for marketplace git access) |

### UID mapping

The container runs as your host user (`--user $(id -u):$(id -g)`), so all files created inside the container are owned by you on the host. No permission issues.

## Usage

### Basic

```bash
cd ~/projects/my-api
confined-claude
```

On first run in a project directory, the runner creates `.confined-claude/` for per-project data and adds it to `.gitignore` automatically.

### Installing plugins inside the container

Plugins are managed separately from your host. Inside the container:

```bash
/plugin marketplace add anthropics/claude-plugins-official
/plugin install <plugin-name>
```

These persist across sessions in the shared container config. Plugin npm dependencies are **auto-installed** on each launch if missing — you don't need to run `npm install` manually.

To debug plugin issues, use `confined-claude --shell` or exec into a running container:

```bash
docker exec -it confined-claude-<project> bash
```

### Parallel instances

```bash
# Terminal 1
cd ~/projects/backend && confined-claude

# Terminal 2
cd ~/projects/frontend && confined-claude

# Terminal 3
cd ~/projects/ml-pipeline && confined-claude
```

### Management commands

```bash
confined-claude --help           # full usage info
confined-claude --version        # show version number
confined-claude --yolo           # launch with --dangerously-skip-permissions
confined-claude --shell          # drop into bash inside the container
confined-claude --status         # running containers + disk usage
confined-claude --clean          # delete current project's .confined-claude/
confined-claude --clean-global   # wipe shared data (pip, container config, plugins)
confined-claude --rebuild        # force-rebuild the Docker image
```

### Inside the container

```bash
mkvenv myenv                     # create a persistent Python venv
source ~/venvs/myenv/bin/activate
pip install pandas               # cached globally, venv is per-project

lsvenvs                          # list venvs + disk usage
diskuse                          # show all volume sizes
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Host Claude config to copy auth from |

```bash
CLAUDE_CONFIG_DIR=~/alt-claude-config confined-claude
```

## Checking Disk Usage

From the host:

```bash
# Per-project
du -sh ~/projects/my-api/.confined-claude/*

# Shared (pip cache + container config/plugins)
du -sh ~/.local/share/confined-claude/shared/*

# Quick overview
confined-claude --status
```

From inside the container:

```bash
diskuse
```

## What's in the Container

Based on `debian:bookworm-slim` with Node.js 22 (nodesource):

- **Claude Code** (via npm)
- **Python 3** with `pip` and `venv`
- **Git**, **curl**, **wget**, **jq**, **ripgrep**
- **build-essential** (gcc, make, etc.)
- **sudo** available for installing additional packages at runtime

## Uninstall

```bash
# Remove the installation
rm -rf ~/.local/share/confined-claude

# Remove per-project data
find ~ -maxdepth 4 -type d -name .confined-claude -exec rm -rf {} +

# Remove the Docker image
docker rmi confined-claude

# Remove the alias line from ~/.bashrc or ~/.zshrc
# (look for the line marked: # confined-claude)
```

## License

MIT — see [LICENSE](LICENSE)

## Author

**RafDouglas C. Tommasi**
[LinkedIn](https://www.linkedin.com/in/rafdouglas/) · [rafdouglas@gmail.com](mailto:rafdouglas@gmail.com)
