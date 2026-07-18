---
type: Integration
title: Pi Agent Integration
description: Three integration surfaces for routing pi coding agent traffic through the Headroom compression proxy — bash shell wrapper, TypeScript extension, and pi skill.
tags: [headroom-pi, pi, integration, extension, shell-wrapper, skill]
---

# Pi Agent Integration

The headroom-pi project connects the [pi coding agent](https://github.com/earendil-works/pi-coding-agent) to the [Headroom](https://github.com/chopratejas/headroom) context compression proxy through three distinct surfaces:

## 1. Shell Wrapper

**File:** `/scripts/headroom-pi`

A bash script that acts as an alias for `pi`. When invoked, it:

1. Checks the systemd status of `headroom-proxy.service`
2. If inactive or failed, starts the service and polls `/livez` (up to 10 seconds)
3. Once healthy (or timeout), runs `pi` via `exec`, passing all arguments through

### Subcommands

| Subcommand | Behavior |
|------------|----------|
| `--status` | Check proxy version, uptime, and port via systemd + `/livez` |
| `--restart` | `systemctl --user restart` the proxy, wait for health, then launch pi |
| `--no-proxy [args]` | Skip proxy check entirely, launch pi directly (escape hatch) |
| `--stop` | Stop the proxy service, exit |
| `--help` | Print usage from script header |

The wrapper resolves the pi binary by checking `~/.npm-global/bin/pi`, `/usr/bin/pi`, `/usr/local/bin/pi`, then falling back to `command -v pi`.

## 2. TypeScript Extension

**File:** `/extensions/headroom-pi.ts`

A pi extension implementing the `ExtensionAPI` interface. Registered in `package.json` under `pi.extensions`. Designed for macOS users or any environment without systemd.

### Lifecycle

| Event | Extension Behavior |
|-------|-------------------|
| `session_start` | Finds the `headroom` binary (searches 4 paths + PATH). If not found, warns user. Spawns `headroom proxy --port` as a child process. Polls `/livez` every 300ms for up to 15s. On success, shows "Headroom: running" in pi status bar. |
| `session_shutdown` | Clears the health-check interval timer. |

### Provider Registration

The extension registers a custom pi provider (e.g., `headroom-openrouter` or `headroom`) with:

- `baseUrl`: `http://localhost:8787/v1`
- `api`: `"openai-completions"` (OpenAI-compatible API format)
- Model list appropriate to the detected [upstream provider](/openwiki/architecture/overview.md#provider-detection)

### Provider-Dependent Model Lists

| Upstream | Models Registered |
|----------|------------------|
| OpenRouter | DeepSeek V4 Flash, DeepSeek V4 Pro, Claude Sonnet 4 |
| Anthropic | Claude Sonnet 4 |
| OpenAI | GPT-4o |
| DeepSeek | (generic fallback) |
| Unknown/other | Single "Default" model |

### Health Monitoring

A 60-second interval timer checks `/livez`. On failure, it logs to console but does not attempt auto-restart (relies on systemd-like restart logic from the child process `exit` handler, which schedules a 2s restart).

### Stats Tool (Commented Out)

The extension includes a commented `headroom_stats` tool registration that fetches compression statistics from `http://127.0.0.1:<port>/stats`. It is disabled but serves as a reference for future implementation.

## 3. Pi Skill

**File:** `/skills/headroom/SKILL.md`

A skill file that teaches the pi agent how to interact with Headroom during a session. The skill provides step-by-step instructions for:

- **Checking proxy health** — probes `http://127.0.0.1:8787/livez`
- **Getting compression statistics** — fetches `http://127.0.0.1:8787/stats` and parses the summary (requests compressed, tokens saved, cost saved)
- **Restarting the proxy** — triggers `systemctl --user restart headroom-proxy.service`
- **Inspecting logs** — runs `journalctl --user -u headroom-proxy`

The skill path is declared in `package.json` under `pi.skills`.

## Package Manifest

**File:** `/package.json`

| Field | Value |
|-------|-------|
| `name` | `headroom-pi` |
| `version` | `0.1.0` |
| `description` | "Headroom context compression for pi — 60-95% fewer tokens, transparent proxy integration" |
| `pi.extensions` | `["./extensions"]` |
| `pi.skills` | `["./skills"]` |
| `license` | Apache-2.0 |
| `repository` | `github:chopratejas/headroom-pi` |

## Architecture Context

See [Architecture Overview](/openwiki/architecture/overview.md) for the full data flow and compression pipeline details.

See [Operations](/openwiki/operations/operations.md) for systemd-based lifecycle management that complements the extension's process-based approach.