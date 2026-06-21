#!/bin/bash
# install.sh — Install headroom-pi integration
# https://github.com/chopratejas/headroom-pi
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

# --- Configuration ---
HEADROOM_PORT="${HEADROOM_PORT:-8787}"
HEADROOM_UPSTREAM="${HEADROOM_UPSTREAM:-https://openrouter.ai/api/v1}"
SCRIPTS_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_CONFIG="${HOME}/.pi/agent/models.json"

echo ""
echo "  headroom-pi installer"
echo "  ====================="
echo ""

# --- 1. Check prerequisites ---
log "Checking prerequisites..."

command -v python3 >/dev/null 2>&1 || err "python3 required but not found"
command -v curl    >/dev/null 2>&1 || err "curl required but not found"
command -v systemctl >/dev/null 2>&1 || warn "systemctl not found — systemd will not be available"

if command -v pi >/dev/null 2>&1 || [ -x "${HOME}/.npm-global/bin/pi" ]; then
    log "pi found"
else
    warn "pi not found on PATH. Install it: npm install -g @earendil-works/pi-coding-agent"
fi

# --- 2. Locate headroom ---
log "Locating headroom binary..."

HEADROOM_BIN=""
for candidate in \
    "$(command -v headroom 2>/dev/null || true)" \
    "${HOME}/.local/bin/headroom" \
    /usr/local/bin/headroom \
    /usr/bin/headroom; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        HEADROOM_BIN="$candidate"
        break
    fi
done

if [ -z "$HEADROOM_BIN" ]; then
    warn "headroom binary not found. Attempting pip install..."
    if command -v pip >/dev/null 2>&1; then
        pip install "headroom-ai[proxy]" || err "pip install failed. Install manually: pip install headroom-ai[proxy]"
        HEADROOM_BIN="$(command -v headroom)"
    elif command -v pipx >/dev/null 2>&1; then
        pipx install "headroom-ai[proxy]" || err "pipx install failed"
        HEADROOM_BIN="${HOME}/.local/bin/headroom"
    elif command -v uv >/dev/null 2>&1; then
        uv tool install "headroom-ai[proxy]" || err "uv tool install failed"
        HEADROOM_BIN="${HOME}/.local/bin/headroom"
    else
        err "No Python package manager found. Install headroom first: pip install headroom-ai[proxy]"
    fi
fi

log "Headroom binary: $HEADROOM_BIN"

# --- 3. Test headroom ---
log "Testing headroom..."
if "$HEADROOM_BIN" --version >/dev/null 2>&1; then
    HEADROOM_VERSION=$("$HEADROOM_BIN" --version)
    log "Headroom version: $HEADROOM_VERSION"
else
    err "headroom binary exists but is not executable"
fi

# --- 4. Install scripts ---
log "Installing scripts to $SCRIPTS_DIR..."
mkdir -p "$SCRIPTS_DIR"

cp "$REPO_DIR/scripts/headroom-pi" "$SCRIPTS_DIR/headroom-pi"
cp "$REPO_DIR/scripts/headroom-health-check" "$SCRIPTS_DIR/headroom-health-check"
chmod +x "$SCRIPTS_DIR/headroom-pi" "$SCRIPTS_DIR/headroom-health-check"

log "Scripts installed"

# --- 5. Install systemd units ---
log "Installing systemd user units..."
mkdir -p "$SYSTEMD_DIR"

# Substitute placeholders
for template in headroom-proxy.service headroom-health-check.service headroom-health-check.timer; do
    sed -e "s|{HEADROOM_BIN}|${HEADROOM_BIN}|g" \
        -e "s|{HEADROOM_PORT}|${HEADROOM_PORT}|g" \
        -e "s|{HEADROOM_UPSTREAM_URL}|${HEADROOM_UPSTREAM}|g" \
        -e "s|{SCRIPTS_DIR}|${SCRIPTS_DIR}|g" \
        "$REPO_DIR/systemd/$template" > "$SYSTEMD_DIR/$template"
    log "  Installed $template"
done

# --- 6. Enable linger for boot persistence ---
if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger 2>/dev/null || true
fi

# --- 7. Reload systemd and start ---
systemctl --user daemon-reload 2>/dev/null || warn "systemctl daemon-reload skipped (no systemd?)"

if systemctl --user is-active headroom-proxy.service >/dev/null 2>&1; then
    log "Stopping existing headroom-proxy..."
    systemctl --user stop headroom-proxy.service 2>/dev/null || true
fi

log "Starting headroom-proxy..."
systemctl --user start headroom-proxy.service 2>/dev/null || warn "Could not start headroom-proxy. Start manually."

log "Starting health-check timer..."
systemctl --user start headroom-health-check.timer 2>/dev/null || true
systemctl --user enable headroom-proxy.service headroom-health-check.timer 2>/dev/null || true

# --- 8. Configure pi models.json ---
log "Configuring pi..."

if [ -f "$PI_CONFIG" ]; then
    warn "$PI_CONFIG already exists. Add the following to the \"providers\" section:"
    echo ""
    echo "    \"{HEADROOM_UPSTREAM_PROVIDER}\": {"
    echo "      \"baseUrl\": \"http://localhost:${HEADROOM_PORT}/v1\""
    echo "    }"
    echo ""
    log "The provider key should match your upstream (e.g. \"openrouter\", \"anthropic\", \"openai\")"
else
    mkdir -p "$(dirname "$PI_CONFIG")"
    cat > "$PI_CONFIG" << 'PIEOF'
{
  "providers": {
    "openrouter": {
      "baseUrl": "http://localhost:PIHEADROOM_PORT/v1"
    }
  }
}
PIEOF
    sed -i "s|PIHEADROOM_PORT|${HEADROOM_PORT}|g" "$PI_CONFIG"
    log "Created $PI_CONFIG (defaults to OpenRouter — edit if you use a different upstream)"
fi

# --- 9. Shell alias ---
RC_FILE=""
for f in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.config/fish/config.fish"; do
    [ -f "$f" ] && RC_FILE="$f" && break
done

if [ -n "$RC_FILE" ]; then
    if grep -q "headroom-pi\|alias pi=" "$RC_FILE" 2>/dev/null; then
        log "Alias already present in $RC_FILE"
    else
        echo "" >> "$RC_FILE"
        echo "# headroom-pi: auto-start compression proxy before pi" >> "$RC_FILE"
        echo "alias pi=${SCRIPTS_DIR}/headroom-pi" >> "$RC_FILE"
        log "Added alias to $RC_FILE"
    fi
else
    warn "No shell config found. Add this alias manually:"
    echo "  alias pi=${SCRIPTS_DIR}/headroom-pi"
fi

# --- 10. Verify ---
echo ""
log "Installation complete!"
echo ""
echo "  ┌──────────────────────────────────────────┐"
echo "  │  Proxy:     systemctl --user status headroom-proxy  │"
echo "  │  Stats:     curl http://localhost:${HEADROOM_PORT}/stats   │"
echo "  │  Dashboard: http://localhost:${HEADROOM_PORT}/docs       │"
echo "  │  Wrapper:   ${SCRIPTS_DIR}/headroom-pi --help     │"
echo "  └──────────────────────────────────────────┘"
echo ""
echo "  Next steps:"
echo "  1. source $RC_FILE   (or open a new terminal)"
echo "  2. pi                 (launch pi through Headroom)"
echo "  3. /model             (select your provider's model)"
echo ""
echo "  To uninstall: ${REPO_DIR}/uninstall.sh"