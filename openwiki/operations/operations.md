---
type: Operations
title: headroom-pi Operations
description: Systemd service management, health checks, Slack alerting, configuration environment variables, and install/uninstall lifecycle for headroom-pi.
tags: [headroom-pi, operations, systemd, health-check, configuration]
---

# Operations

## Systemd Service Architecture

The headroom-pi installer creates three systemd user units:

| Unit | Type | Purpose |
|------|------|---------|
| `headroom-proxy.service` | `simple` | Runs the Headroom proxy binary with `--port` and upstream URL. Restarts on failure with a 2s delay. |
| `headroom-health-check.service` | `oneshot` | Runs the `headroom-health-check` script, bound to the proxy service. |
| `headroom-health-check.timer` | `timer` | Triggers the health check every minute (`OnCalendar=minutely`). Persistent across reboots. |

The `install.sh` script also enables `loginctl enable-linger`, ensuring user services start on boot without requiring an active login session.

## Service Management

```bash
# Status
systemctl --user status headroom-proxy.service

# Restart after config change
systemctl --user restart headroom-proxy.service

# Live logs
journalctl --user -u headroom-proxy -f

# List active timers
systemctl --user list-timers
```

## Health Check

The `headroom-health-check` script probes `http://127.0.0.1:8787/livez`:

- **exit 0** — proxy is healthy
- **exit 1** — proxy is unreachable; actions taken:
  - Logs an error via `logger` (syslog)
  - Sends a desktop notification via `notify-send` (if available)
  - Posts a Slack alert (if `HEADROOM_SLACK_WEBHOOK` is configured)

## Slack Alerting

For team notification when the proxy goes down, set:

```bash
echo 'HEADROOM_SLACK_WEBHOOK=https://hooks.slack.com/services/...' > ~/.headroom/proxy.env
```

The health-check timer checks every 60 seconds and posts to Slack on failure.

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HEADROOM_PORT` | `8787` | Port the proxy listens on |
| `HEADROOM_UPSTREAM` | `https://openrouter.ai/api/v1` | Upstream LLM provider base URL |
| `HEADROOM_SLACK_WEBHOOK` | (none) | Slack webhook URL for health alerts |

### pi Configuration

The installer creates or updates `~/.pi/agent/models.json`:

```json
{
  "providers": {
    "openrouter": {
      "baseUrl": "http://localhost:8787/v1"
    }
  }
}
```

Replace the provider key (`openrouter`) with `anthropic`, `openai`, or `deepseek` depending on your upstream.

### Changing the Port

```bash
export HEADROOM_PORT=8888
./install.sh   # re-run to regenerate systemd units
```

## Install Lifecycle

The `install.sh` script (`/install.sh`) performs:

1. Checks prerequisites: python3, curl, systemctl, pi
2. Locates or installs the `headroom` binary (checks PATH, `~/.local/bin`, `/usr/local/bin`, `/usr/bin`; falls back to pip/pipx/uv)
3. Verifies headroom works (`headroom --version`)
4. Copies `scripts/headroom-pi` and `scripts/headroom-health-check` to `~/.local/bin`
5. Substitutes template variables and installs systemd units to `~/.config/systemd/user/`
6. Enables linger, reloads systemd, starts services
7. Creates or annotates `~/.pi/agent/models.json`
8. Adds `alias pi=<wrapper-path>` to shell RC file

## Uninstall Lifecycle

The `uninstall.sh` script (`/uninstall.sh`) performs:

1. Stops and disables systemd units
2. Removes systemd unit files
3. Removes shell scripts from `~/.local/bin`
4. Cleans shell aliases from RC files
5. Leaves `~/.pi/agent/models.json` untouched (manual review advised)
6. Leaves the `headroom` binary in place (uninstall separately via pip)

## Key Source Files

| File | Role |
|------|------|
| `/install.sh` | Full installation orchestration |
| `/uninstall.sh` | Clean removal |
| `/systemd/headroom-proxy.service` | Proxy service unit |
| `/systemd/headroom-health-check.service` | Health check oneshot |
| `/systemd/headroom-health-check.timer` | 60-second health check timer |
| `/scripts/headroom-health-check` | Health probe logic |