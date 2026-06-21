#!/bin/bash
# uninstall.sh — Remove headroom-pi integration
set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $1"; }

SCRIPTS_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
PI_CONFIG="${HOME}/.pi/agent/models.json"

log "Stopping services..."
systemctl --user stop headroom-proxy.service 2>/dev/null || true
systemctl --user stop headroom-health-check.timer 2>/dev/null || true
systemctl --user disable headroom-proxy.service headroom-health-check.timer 2>/dev/null || true

log "Removing systemd units..."
rm -f "$SYSTEMD_DIR/headroom-proxy.service"
rm -f "$SYSTEMD_DIR/headroom-health-check.service"
rm -f "$SYSTEMD_DIR/headroom-health-check.timer"
systemctl --user daemon-reload 2>/dev/null || true

log "Removing scripts..."
rm -f "$SCRIPTS_DIR/headroom-pi" "$SCRIPTS_DIR/headroom-health-check"

log "Cleaning shell alias..."
for f in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.config/fish/config.fish"; do
    [ -f "$f" ] && sed -i '/# headroom-pi:/d;/alias pi=.*headroom-pi/d' "$f"
done

log "Note: $PI_CONFIG was not modified. Review it if you no longer need the Headroom provider."
log "Note: Headroom binary was not removed. Uninstall separately: pip uninstall headroom-ai"

echo ""
log "Uninstall complete."