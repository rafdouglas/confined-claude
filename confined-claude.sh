#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# confined-claude.sh — Run Claude Code in an isolated Docker container
#
# Launched from any project directory. Creates a local .confined-claude/
# folder for per-project persistent data (venvs, tools).
#
# Isolation model:
#   - Auth credentials are COPIED (not mounted) from ~/.claude/ on each launch
#   - The container has its OWN plugin/marketplace ecosystem
#   - Host ~/.claude/ is never mounted — never modified by the container
#   - pip and npm caches are shared across all container instances
# =============================================================================

INSTALL_DIR="${HOME}/.local/share/confined-claude"
IMAGE_NAME="confined-claude"
LOCAL_DIR=".confined-claude"
VERSION="0.2.0"

# Global shared paths
SHARED_DIR="$INSTALL_DIR/shared"
SHARED_PIP_CACHE="$SHARED_DIR/pip-cache"
SHARED_NPM_CACHE="$SHARED_DIR/npm-cache"
SHARED_CLAUDE_CONFIG="$SHARED_DIR/claude-config"   # container's OWN ~/.claude/

# Host Claude config — read from, never mounted
HOST_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ── Help ──────────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
confined-claude v${VERSION} — Run Claude Code in an isolated Docker container

USAGE
    confined-claude                  Launch Claude Code in the current directory
    confined-claude --yolo           Launch with --dangerously-skip-permissions
    confined-claude --shell          Drop into bash inside the container
    confined-claude --help           Show this help
    confined-claude --version        Show version number
    confined-claude --status         Running instances and disk usage
    confined-claude --clean          Remove this project's persistent data
    confined-claude --clean-global   Remove shared data (caches, container config)
    confined-claude --rebuild        Force-rebuild the Docker image

ENVIRONMENT VARIABLES
    CLAUDE_CONFIG_DIR   Host Claude config to copy auth from (default: ~/.claude)

ISOLATION MODEL
    Auth credentials are COPIED from your host ~/.claude/ on each launch.
    The container maintains its own separate plugin/marketplace ecosystem.
    Your host ~/.claude/ is never mounted and never modified.

WHAT GETS CREATED
    .confined-claude/                  In each project directory (per-project)
        venvs/                         Python virtual environments
        local-bin/                     Custom CLI tools

    ~/.local/share/confined-claude/    User-level installation
        shared/
            pip-cache/                 Shared pip download cache
            npm-cache/                 Shared npm cache (for plugin deps)
            claude-config/             Container's own Claude config, plugins,
                                       and marketplace data (shared across
                                       all container instances)

INSIDE THE CONTAINER
    mkvenv <n>       Create a persistent Python virtual environment
    lsvenvs             List venvs and their disk usage
    diskuse             Show all persistent volume sizes

EOF
}

# ── Status ────────────────────────────────────────────────────────────────────

show_status() {
    echo "confined-claude v${VERSION}"
    echo ""
    echo "Running containers:"
    echo ""
    RUNNING="$(docker ps --filter "name=confined-claude-" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null)"
    if [ -z "$RUNNING" ] || [ "$(echo "$RUNNING" | wc -l)" -le 1 ]; then
        echo "   (none)"
    else
        echo "$RUNNING" | sed 's/^/   /'
    fi
    echo ""

    echo "Shared data:"
    if [ -d "$SHARED_DIR" ]; then
        du -sh "$SHARED_DIR"/*/ 2>/dev/null \
            | sed "s|$SHARED_DIR/||;s|/$||" \
            | awk '{printf "   %-25s %s\n", $2, $1}' \
            || echo "   (empty)"
    fi
    echo ""

    echo "Projects with $LOCAL_DIR/ (searching ~, max depth 4):"
    echo ""
    find "$HOME" -maxdepth 4 -type d -name "$LOCAL_DIR" 2>/dev/null | while read -r d; do
        project_dir="$(dirname "$d")"
        size="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
        printf "   %-50s %s\n" "$project_dir" "$size"
    done || echo "   (none found)"
}

# ── Clean ─────────────────────────────────────────────────────────────────────

clean_project() {
    local target="$PWD/$LOCAL_DIR"
    if [ ! -d "$target" ]; then
        echo "No $LOCAL_DIR/ found in the current directory. Nothing to clean."
        exit 0
    fi
    SIZE="$(du -sh "$target" | awk '{print $1}')"
    echo "About to delete: $target ($SIZE)"
    read -rp "Continue? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$target"
        echo "Deleted."
    else
        echo "Cancelled."
    fi
}

clean_global() {
    if [ ! -d "$SHARED_DIR" ]; then
        echo "No shared data found. Nothing to clean."
        exit 0
    fi
    SIZE="$(du -sh "$SHARED_DIR" | awk '{print $1}')"
    echo "About to delete all shared container data ($SIZE):"
    echo "   $SHARED_DIR"
    echo "   This includes: pip/npm cache, container's Claude config and plugins."
    echo "   (Your host ~/.claude/ is NOT affected.)"
    read -rp "Continue? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$SHARED_DIR"
        mkdir -p "$SHARED_PIP_CACHE" "$SHARED_NPM_CACHE" "$SHARED_CLAUDE_CONFIG"
        echo "Cleared. You'll need to re-install plugins inside the container."
    else
        echo "Cancelled."
    fi
}

# ── Rebuild ───────────────────────────────────────────────────────────────────

rebuild_image() {
    echo "Force-rebuilding image '$IMAGE_NAME' ..."
    docker build --no-cache -t "$IMAGE_NAME" -f "$INSTALL_DIR/Dockerfile" "$INSTALL_DIR"
    echo "Image rebuilt."
}

# ── Handle flags ──────────────────────────────────────────────────────────────

LAUNCH_CMD="claude"

case "${1:-}" in
    --help|-h)       show_help;    exit 0 ;;
    --version|-v)    echo "confined-claude v${VERSION}"; exit 0 ;;
    --status|-s)     show_status;  exit 0 ;;
    --clean)         clean_project; exit 0 ;;
    --clean-global)  clean_global; exit 0 ;;
    --rebuild)       rebuild_image; exit 0 ;;
    --shell)         LAUNCH_CMD="bash" ;;
    --yolo)          LAUNCH_CMD="claude --dangerously-skip-permissions" ;;
esac

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
    echo "Error: Docker is not installed or not in PATH."
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo "Error: Cannot connect to Docker."
    echo "Is the daemon running? Is your user in the 'docker' group?"
    exit 1
fi

# Ensure the image exists; build if not
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Image '$IMAGE_NAME' not found. Building ..."
    docker build -t "$IMAGE_NAME" -f "$INSTALL_DIR/Dockerfile" "$INSTALL_DIR" --quiet
    echo "Built."
    echo ""
fi

# ── Set up per-project directories ────────────────────────────────────────────

PROJECT_DIR="$PWD"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
PROJECT_SLUG="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"

PROJECT_DATA="$PROJECT_DIR/$LOCAL_DIR"
PROJECT_VENVS="$PROJECT_DATA/venvs"
PROJECT_LOCAL_BIN="$PROJECT_DATA/local-bin"

mkdir -p "$PROJECT_VENVS" "$PROJECT_LOCAL_BIN"
mkdir -p "$SHARED_PIP_CACHE" "$SHARED_NPM_CACHE" "$SHARED_CLAUDE_CONFIG"

# ── Sync credentials from host → container config ────────────────────────────
# We COPY auth files so the container can log in, but the container maintains
# its own plugins, marketplaces, and settings independently.

sync_credentials() {
    if [ ! -d "$HOST_CLAUDE_DIR" ]; then
        echo "  Note: No host Claude config found at $HOST_CLAUDE_DIR"
        echo "  You'll need to authenticate inside the container."
        return
    fi

    local synced=0
    for f in credentials.json .credentials.json auth.json; do
        if [ -f "$HOST_CLAUDE_DIR/$f" ]; then
            cp "$HOST_CLAUDE_DIR/$f" "$SHARED_CLAUDE_CONFIG/$f"
            synced=1
        fi
    done

    # Copy settings.json only if container doesn't have one yet
    if [ -f "$HOST_CLAUDE_DIR/settings.json" ] && \
       [ ! -f "$SHARED_CLAUDE_CONFIG/settings.json" ]; then
        cp "$HOST_CLAUDE_DIR/settings.json" "$SHARED_CLAUDE_CONFIG/settings.json"
        synced=1
    fi

    if [ "$synced" -eq 1 ]; then
        echo "  Synced credentials from host ~/.claude/"
    fi
}

sync_credentials

# ── Ensure .confined-claude/ is in .gitignore ─────────────────────────────────

ensure_gitignore() {
    local gitignore="$PROJECT_DIR/.gitignore"

    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        return
    fi

    if git -C "$PROJECT_DIR" check-ignore -q "$LOCAL_DIR" 2>/dev/null; then
        return
    fi

    if [ -f "$gitignore" ]; then
        echo "" >> "$gitignore"
        echo "# Confined Claude — per-project container data" >> "$gitignore"
        echo "$LOCAL_DIR/" >> "$gitignore"
        echo "  Added '$LOCAL_DIR/' to .gitignore"
    else
        echo "# Confined Claude — per-project container data" > "$gitignore"
        echo "$LOCAL_DIR/" >> "$gitignore"
        echo "  Created .gitignore with '$LOCAL_DIR/'"
    fi
}

ensure_gitignore

# ── Print summary ────────────────────────────────────────────────────────────

echo ""
echo "  Confined Claude v${VERSION}"
echo "  Project:    $PROJECT_NAME"
echo "  Directory:  $PROJECT_DIR"
echo "  Running as: $(id -u):$(id -g)"
echo ""
echo "  Per-project (in $LOCAL_DIR/):"
echo "    venvs/       $PROJECT_VENVS"
echo "    local-bin/   $PROJECT_LOCAL_BIN"
echo ""
echo "  Shared (across all containers):"
echo "    config       $SHARED_CLAUDE_CONFIG"
echo "    pip-cache    $SHARED_PIP_CACHE"
echo "    npm-cache    $SHARED_NPM_CACHE"
echo ""

# ── Assemble volumes ─────────────────────────────────────────────────────────

VOLUMES=(
    -v "$PROJECT_DIR:/home/claude/workspace"
    -v "$SHARED_CLAUDE_CONFIG:/home/claude/.claude"
    -v "$SHARED_PIP_CACHE:/home/claude/.cache/pip"
    -v "$SHARED_NPM_CACHE:/home/claude/.cache/npm"
    -v "$PROJECT_VENVS:/home/claude/venvs"
    -v "$PROJECT_LOCAL_BIN:/home/claude/.local/bin"
)

# Mount git config for marketplace clone access
if [ -f "$HOME/.gitconfig" ]; then
    VOLUMES+=( -v "$HOME/.gitconfig:/home/claude/.gitconfig:ro" )
fi

# ── Container name ────────────────────────────────────────────────────────────

CONTAINER_NAME="confined-claude-$PROJECT_SLUG"
docker rm -f "$CONTAINER_NAME" &>/dev/null || true

# ── Launch ────────────────────────────────────────────────────────────────────

echo "  Starting container '$CONTAINER_NAME' ..."
echo "  Helpers:  mkvenv <n> | lsvenvs | diskuse"
[ "$LAUNCH_CMD" = "bash" ] && echo "  Mode: shell (type 'claude' to start Claude Code)"
[[ "$LAUNCH_CMD" == *"dangerously"* ]] && echo "  Mode: --dangerously-skip-permissions (you're in a container, YOLO)"
echo ""

exec docker run --rm -it --init \
    --name "$CONTAINER_NAME" \
    --user "$(id -u):$(id -g)" \
    "${VOLUMES[@]}" \
    -e "HOME=/home/claude" \
    -e "CLAUDE_CONFIG_DIR=/home/claude/.claude" \
    -e "PIP_CACHE_DIR=/home/claude/.cache/pip" \
    -e "npm_config_cache=/home/claude/.cache/npm" \
    -e "CONFINED_CLAUDE_PROJECT=$PROJECT_NAME" \
    -e "TERM=${TERM:-xterm-256color}" \
    -w "/home/claude/workspace" \
    "$IMAGE_NAME" \
    $LAUNCH_CMD
