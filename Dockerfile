FROM debian:bookworm-slim

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl wget ca-certificates gnupg \
        python3 python3-pip python3-venv \
        jq ripgrep vim-tiny build-essential sudo \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 via nodesource ────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Claude Code ──────────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ── Helper scripts (installed globally so they work regardless of UID) ───────

RUN cat > /usr/local/bin/mkvenv <<'SCRIPT' && chmod +x /usr/local/bin/mkvenv
#!/usr/bin/env bash
set -euo pipefail
NAME="${1:?Usage: mkvenv <name>}"
VENV_PATH="$HOME/venvs/$NAME"
if [ -d "$VENV_PATH" ]; then
    echo "Venv '$NAME' already exists."
else
    echo "Creating venv '$NAME' ..."
    python3 -m venv "$VENV_PATH"
    echo "Created."
fi
echo "Activate with:  source ~/venvs/$NAME/bin/activate"
SCRIPT

RUN cat > /usr/local/bin/lsvenvs <<'SCRIPT' && chmod +x /usr/local/bin/lsvenvs
#!/usr/bin/env bash
echo "Python virtual environments (this project):"
echo ""
if [ -z "$(ls -A "$HOME/venvs" 2>/dev/null)" ]; then
    echo "  (none — create one with: mkvenv <name>)"
else
    du -sh "$HOME/venvs"/*/ 2>/dev/null
fi
SCRIPT

RUN cat > /usr/local/bin/diskuse <<'SCRIPT' && chmod +x /usr/local/bin/diskuse
#!/usr/bin/env bash
echo "Persistent volume usage:"
echo ""
echo "  Venvs:     $(du -sh "$HOME/venvs" 2>/dev/null | cut -f1)"
echo "  Pip cache: $(du -sh "$HOME/.cache/pip" 2>/dev/null | cut -f1)"
echo "  Local bin: $(du -sh "$HOME/.local/bin" 2>/dev/null | cut -f1)"
SCRIPT

WORKDIR /home/claude/workspace

CMD ["claude"]
