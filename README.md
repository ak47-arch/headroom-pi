# headroom-pi

**60–95% fewer tokens for pi coding agent sessions — zero code changes.**

Routes all pi traffic through [Headroom](https://github.com/chopratejas/headroom)'s
context compression proxy, slashing API costs while preserving accuracy.

```
pi → headroom-pi wrapper → Headroom proxy (compresses) → OpenRouter/Anthropic/OpenAI
```

## Two ways to install

### Option A: Systemd service (Linux, most reliable)

```bash
git clone https://github.com/chopratejas/headroom-pi.git
cd headroom-pi
./install.sh
```

What it does:
- Installs Headroom as a systemd user service with `Restart=on-failure`
- Adds a health-check timer (every 60s, alerts on failure)
- Installs the `headroom-pi` shell wrapper → `alias pi=headroom-pi`
- Configures pi's `models.json` to route through the proxy

### Option B: Pi extension (cross-platform, pi-native)

```bash
pi install npm:headroom-pi
```

Or manually:

```bash
cp extensions/headroom-pi.ts ~/.pi/agent/extensions/
```

What it does:
- Auto-starts Headroom proxy when pi starts
- Registers Headroom as a custom provider
- Shows compression status in pi's footer
- Cleans up on exit

## Quick test

```bash
# 1. Check proxy is running
headroom-pi --status

# 2. See compression stats
curl http://127.0.0.1:8787/stats | python3 -m json.tool

# 3. Launch pi with compression
pi

# In pi:
# /model  →  select  openrouter/deepseek/deepseek-v4-flash
# Send any prompt — then check stats again
```

## Requirements

- **Headroom** installed: `pip install headroom-ai[proxy]`
- **pi** installed: `npm install -g @earendil-works/pi-coding-agent`
- Python 3.10+, systemd (for Option A), Linux/macOS

## Upstream configuration

| If you use... | Set `HEADROOM_UPSTREAM` to... |
|---|---|
| OpenRouter (default) | `https://openrouter.ai/api/v1` |
| Anthropic direct | *(uses Anthropic API auto-detection)* |
| OpenAI direct | `https://api.openai.com/v1` |
| DeepSeek direct | `https://api.deepseek.com/v1` |

Set via environment or in `models.json`:
```json
{
  "providers": {
    "openrouter": {
      "baseUrl": "http://localhost:8787/v1"
    }
  }
}
```

## Monitoring

```bash
systemctl --user status headroom-proxy    # proxy status
journalctl --user -u headroom-proxy -f   # live logs
headroom-pi --restart                    # bounce the proxy
headroom-pi --stop                       # stop the proxy
headroom-pi --no-proxy                   # run pi without compression
```

For team alerting, set `HEADROOM_SLACK_WEBHOOK` to get notified when the proxy
goes down (within ~60 seconds).

## How it works

```
┌─────────┐     ┌──────────────────┐     ┌────────────┐
│   pi    │ ──→ │  Headroom Proxy  │ ──→ │  Upstream  │
│         │     │  :8787/v1        │     │  LLM API   │
└─────────┘     │                  │     └────────────┘
                │  • SmartCrusher  │
                │  • CodeCompressor│
                │  • Kompress-base │
                │  • CacheAligner  │
                │  • CCR           │
                └──────────────────┘
```

1. pi sends prompt + tool outputs → Headroom proxy
2. Headroom compresses (JSON, AST, ML text compression) → sends to upstream
3. Upstream LLM responds → Headroom passes response back to pi
4. LLM can retrieve originals via `headroom_retrieve` MCP tool

## Files

```
headroom-pi/
├── install.sh              # Option A: one-command installer
├── uninstall.sh            # Clean removal
├── systemd/                # Systemd service + timer units
├── scripts/                # headroom-pi wrapper + health-check
├── extensions/             # Option B: pi TypeScript extension
│   └── headroom-pi.ts
├── skills/                 # Pi skill for /skill:headroom
│   └── headroom/SKILL.md
├── package.json            # npm pi-package manifest
└── README.md
```

## License

Apache 2.0 — same as Headroom.