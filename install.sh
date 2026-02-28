#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# install.sh — Confined Claude installer (no sudo required)
#
# Installs to ~/.local/share/confined-claude, builds the Docker image,
# and creates a bash/zsh alias so you can run `confined-claude` from anywhere.
#
# Prerequisites:
#   - Docker installed and running
#   - Your user in the `docker` group (or rootless Docker configured)
#
# Usage:
#   ./install.sh
# =============================================================================

INSTALL_DIR="${HOME}/.local/share/confined-claude"
IMAGE_NAME="confined-claude"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  Confined Claude v0.1.0 — Installer"
echo ""
echo "  Install to:  $INSTALL_DIR"
echo "  User:        $(whoami) (uid=$(id -u))"
echo "  Image:       $IMAGE_NAME"
echo ""

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
    echo "Error: Docker is not installed. Install it first:"
    echo "  https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo "Error: Cannot connect to Docker. Possible causes:"
    echo "  - Docker daemon is not running"
    echo "  - Your user is not in the 'docker' group"
    echo ""
    echo "  To fix the group issue (then log out and back in):"
    echo "    sudo usermod -aG docker \$(whoami)"
    exit 1
fi

# ── Install files ─────────────────────────────────────────────────────────────

echo "Installing to $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/shared/pip-cache"

cp "$REPO_DIR/confined-claude.sh"  "$INSTALL_DIR/confined-claude.sh"
cp "$REPO_DIR/Dockerfile"          "$INSTALL_DIR/Dockerfile"

chmod +x "$INSTALL_DIR/confined-claude.sh"

echo "  Files installed."
echo ""

# ── Build Docker image ────────────────────────────────────────────────────────

echo "Building Docker image '$IMAGE_NAME' ..."
docker build -t "$IMAGE_NAME" -f "$INSTALL_DIR/Dockerfile" "$INSTALL_DIR" --quiet
echo "  Image ready."
echo ""

# ── Set up shell alias ────────────────────────────────────────────────────────

ALIAS_LINE="alias confined-claude='$INSTALL_DIR/confined-claude.sh'"
ALIAS_MARKER="# confined-claude"

setup_alias() {
    local rc_file="$1"

    if [ ! -f "$rc_file" ]; then
        return 1
    fi

    if grep -qF "$ALIAS_MARKER" "$rc_file" 2>/dev/null; then
        sed -i "/$ALIAS_MARKER/c\\$ALIAS_LINE  $ALIAS_MARKER" "$rc_file"
        echo "  Updated alias in $rc_file"
    else
        echo "" >> "$rc_file"
        echo "$ALIAS_LINE  $ALIAS_MARKER" >> "$rc_file"
        echo "  Added alias to $rc_file"
    fi
    return 0
}

ALIAS_ADDED=0

for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if setup_alias "$rc" 2>/dev/null; then
        ALIAS_ADDED=1
        break
    fi
done

if setup_alias "$HOME/.zshrc" 2>/dev/null; then
    ALIAS_ADDED=1
fi

if [ "$ALIAS_ADDED" -eq 0 ]; then
    echo "  Could not find .bashrc, .bash_profile, or .zshrc."
    echo "  Add this alias manually:"
    echo "    $ALIAS_LINE"
fi

echo ""
echo "  Installation complete!"
echo ""
echo "  Reload your shell, then:"
echo "    cd ~/my-project"
echo "    confined-claude"
echo ""
echo "  Or start a new shell:  exec bash"
echo ""
echo "  To uninstall:"
echo "    rm -rf ~/.local/share/confined-claude"
echo "    docker rmi confined-claude"
echo "    Remove the alias from your shell rc file"
echo ""
