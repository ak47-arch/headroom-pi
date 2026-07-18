---
type: Reference
title: headroom-pi Quickstart
description: Entrypoint for the headroom-pi wiki. Covers project overview, installation, verification, key commands, and links to architecture, operations, and pi integration details.
tags: [headroom-pi, quickstart, setup]
---

# headroom-pi Quickstart

## Overview

[headroom-pi](https://github.com/ak47-arch/headroom-pi) is an integration layer that routes all [pi coding agent](https://github.com/earendil-works/pi-coding-agent) traffic through the [Headroom](https://github.com/chopratejas/headroom) context compression proxy. It delivers **60–95% fewer tokens** with zero code changes to your pi setup.

```
pi → headroom-pi → Headroom proxy (:8787) → OpenRouter / Anthropic / OpenAI
```

The project provides three distinct integration surfaces, each documented in its own section:

- **Shell wrapper** (`headroom-pi`) — a bash script that manages the systemd service lifecycle and transparently launches pi through the proxy
- **Pi extension** (`extensions/headroom-pi.ts`) — a TypeScript extension for macOS users or anyone avoiding systemd
- **Pi skill** (`skills/headroom/SKILL.md`) — a skill file that teaches the pi agent how to use Headroom's features

See [Architecture](/openwiki/architecture/overview.md) for the full data flow and compression pipeline.

See [Pi Integration](/openwiki/integrations/pi-agent.md) for extension and skill details.

See [Operations](/openwiki/operations/operations.md) for systemd management, health checks, and configuration.

## Quick Install

```bash
git clone https://github.com/ak47-arch/headroom-pi.git
cd headroom-pi
./install.sh
```

The installer:

| Action | Purpose |
|--------|---------|
| Finds or installs `headroom` binary via pip/pipx/uv | One less dependency to manage |
| Installs systemd user service (`headroom-proxy.service`) | Always-on proxy with auto-restart |
| Installs health-check timer (`headroom-health-check.timer`) | Every-60s health probe with Slack alerting |
| Installs `headroom-pi` shell wrapper to `~/.local/bin` | `pi` launches proxy transparently |
| Adds shell alias `pi=headroom-pi` to `.bashrc`/`.zshrc` | Transparent replacement — just type `pi` |
| Configures `~/.pi/agent/models.json` | pi sees models routed through Headroom |

### Alternative: Pi Extension (no systemd)

For macOS or anywhere systemd is unavailable:

```bash
pi install git:github.com/ak47-arch/headroom-pi
```

The extension auto-starts Headroom on session launch, registers it as a custom provider, and shows compression status in the footer.

## Verify It Works

```bash
# Check proxy is running
headroom-pi --status
# Expected: "Proxy: running (port 8787)" with version and uptime

# Launch pi (compression is on automatically)
pi
# In pi: /model → select openrouter/deepseek/deepseek-v4-flash
# Send any prompt, then in another terminal:
curl http://127.0.0.1:8787/stats | python3 -m json.tool
```

Look for `tokens_saved > 0` and `savings_percent > 0`. Compression activates on verbose content like file reads, code searches, and tool outputs. System prompts and short messages pass through unchanged.

## Commands

| Command | Purpose |
|---------|---------|
| `headroom-pi --status` | Show proxy version, uptime, port |
| `headroom-pi --restart` | Bounce the proxy, then launch pi |
| `headroom-pi --stop` | Stop the proxy service |
| `headroom-pi --no-proxy [args]` | Launch pi without compression (escape hatch) |
| `headroom-pi --help` | Show all options |

## Uninstall

```bash
cd headroom-pi
./uninstall.sh
```

## Source Repository

- [GitHub: ak47-arch/headroom-pi](https://github.com/ak47-arch/headroom-pi)
- **License:** Apache 2.0

## Next Steps

| Page | What you'll find |
|------|------------------|
| [Architecture Overview](/openwiki/architecture/overview.md) | Data flow, compression pipeline, token savings benchmarks |
| [Pi Integration](/openwiki/integrations/pi-agent.md) | Shell wrapper, TypeScript extension, pi skill |
| [Operations](/openwiki/operations/operations.md) | Systemd units, health checks, Slack alerting, configuration reference |

## Backlog

| Area | Source Anchor | Reason Deferred |
|------|--------------|-----------------|
| Compression algorithm internals | Headroom upstream repo | Headroom-specific details belong in the Headroom repository, not here |
| GitHub Actions CI/CD | No CI/CD files exist in repo | Not yet implemented; add when workflows are added |
| Headroom binary compilation / system requirements | Headroom upstream repo | Covered by `pip install headroom-ai[proxy]`; upstream docs are authoritative |