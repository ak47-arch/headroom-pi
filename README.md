# headroom-pi

Route all pi coding agent traffic through [Headroom](https://github.com/chopratejas/headroom)'s
context compression proxy — **60–95% fewer tokens, zero code changes.**

```
pi → headroom-pi → Headroom proxy (:8787) → OpenRouter / Anthropic / OpenAI
                        │
                        ├─ SmartCrusher (JSON)
                        ├─ CodeCompressor (AST)
                        ├─ Kompress-base (ML text)
                        ├─ CacheAligner (KV cache hits)
                        └─ CCR (reversible — LLM retrieves originals)
```

---

## Installation

```bash
git clone https://github.com/ak47-arch/headroom-pi.git
cd headroom-pi
./install.sh
```

That's it. The installer:

| Does | Why |
|---|---|
| Finds or installs `headroom` binary | One less thing to think about |
| Installs systemd user service | Proxy always-on, auto-restart on crash |
| Adds health-check timer (every 60s) | Catches hangs, alerts your team |
| Installs `headroom-pi` shell wrapper | `pi` auto-starts proxy if it's down |
| Adds shell alias `pi=headroom-pi` | Transparent — you just type `pi` |
| Configures `~/.pi/agent/models.json` | pi sees models routed through Headroom |

### Pi extension (alternative, no systemd)

If you're on macOS or don't want systemd, use the pi extension instead:

```bash
pi install git:github.com/ak47-arch/headroom-pi
```

The extension auto-starts Headroom when pi launches, registers it as a custom
provider, and shows compression status in the footer.

---

## Verify it works

```bash
# 1. Check proxy is running
headroom-pi --status

# Output:
# Proxy: running (port 8787)
#   Version: 0.26.0
#   Uptime: 1546.2s

# 2. Launch pi (compression is on automatically)
pi

# In pi:
# /model  →  select  openrouter/deepseek/deepseek-v4-flash
# Send any prompt, then check stats in another terminal:

curl http://127.0.0.1:8787/stats | python3 -m json.tool
```

Look for `tokens_saved > 0` and `savings_percent > 0`. Compression kicks in when
pi reads files, searches code, or processes tool outputs.

---

## Commands

| Command | What it does |
|---|---|
| `headroom-pi --status` | Show proxy version, uptime, port |
| `headroom-pi --restart` | Bounce the proxy, then launch pi |
| `headroom-pi --stop` | Stop the proxy service |
| `headroom-pi --no-proxy` | Launch pi without compression (escape hatch) |
| `headroom-pi --help` | Show all options |

### Systemd management

```bash
systemctl --user status headroom-proxy.service   # proxy health
systemctl --user restart headroom-proxy.service  # restart after config change
journalctl --user -u headroom-proxy -f           # live logs
systemctl --user list-timers                     # health-check timer
```

### Health check

```bash
headroom-health-check              # exit 0 = healthy, exit 1 = down
curl http://127.0.0.1:8787/livez   # raw endpoint
```

---

## Configuration

### Upstream provider

By default, Headroom routes to **OpenRouter** (`https://openrouter.ai/api/v1`).
To change:

```bash
export HEADROOM_UPSTREAM=https://api.anthropic.com/v1
```

Or set in pi's `~/.pi/agent/models.json`:

```json
{
  "providers": {
    "openrouter": {
      "baseUrl": "http://localhost:8787/v1"
    }
  }
}
```

Replace `openrouter` with `anthropic`, `openai`, or `deepseek` depending on your
provider.

### Port

```bash
export HEADROOM_PORT=8888
./install.sh   # re-run to update
```

### Team alerting

Set `HEADROOM_SLACK_WEBHOOK` to get notified within 60 seconds when the proxy
goes down:

```bash
echo 'HEADROOM_SLACK_WEBHOOK=https://hooks.slack.com/services/...' > ~/.headroom/proxy.env
```

The health-check timer posts to Slack on failure.

---

## How it works

```
┌──────────┐     ┌───────────────────┐     ┌──────────────┐
│   pi     │ ──→ │  Headroom Proxy   │ ──→ │  OpenRouter   │
│          │     │  127.0.0.1:8787   │     │  Anthropic     │
└──────────┘     │                   │     │  OpenAI        │
                 │  Compression:     │     │  DeepSeek      │
                 │   • SmartCrusher  │     └──────────────┘
                 │   • CodeCompressor│
                 │   • Kompress-base │
                 │   • CacheAligner  │
                 │                   │
                 │  Features:        │
                 │   • CCR retrieval │
                 │   • Cross-agent   │
                 │     memory        │
                 │   • Output shaper │
                 └───────────────────┘
```

1. **pi** sends prompts, tool outputs, file contents → Headroom proxy
2. **Headroom** detects content type, picks the right compressor, shrinks it
3. **Compressed content** goes to upstream LLM (lower cost, same accuracy)
4. **LLM** responds; Headroom passes response back to pi untouched
5. **CCR**: if the LLM needs original details, it calls `headroom_retrieve`

### compression only activates on verbose content

The 60–95% headline applies to large tool outputs (code search results, error
logs, RAG chunks). System prompts and short user messages are left alone. You'll
see the savings compound as sessions generate more tool output.

---

## Real-world savings (from our testing)

| Session | Before | After | Saved |
|---|---|---|---|
| pi startup system prompt | 30,097 | 30,097 | 0% (correct — nothing to compress) |
| File reads + model switch | 124,947 | 109,664 | **12.2%** |
| 100 code search results | ~17,765 | ~1,408 | **~92%** (Headroom benchmark) |
| SRE incident debugging | ~65,694 | ~5,118 | **~92%** (Headroom benchmark) |

---

## Uninstall

```bash
cd headroom-pi
./uninstall.sh
```

Removes systemd units, scripts, and shell alias. Does **not** remove the
headroom binary or your pi models.json (review those manually).

---

## Requirements

- **Headroom**: `pip install headroom-ai[proxy]` (installer does this automatically)
- **pi**: `npm install -g @earendil-works/pi-coding-agent`
- **systemd**: for the service/timer approach (Linux). Use the pi extension on macOS
- Python 3.10+

---

## Files

```
headroom-pi/
├── README.md
├── LICENSE                 # Apache 2.0
├── install.sh              # One-command installer
├── uninstall.sh            # Clean removal
├── systemd/                # Systemd units
│   ├── headroom-proxy.service
│   ├── headroom-health-check.service
│   └── headroom-health-check.timer
├── scripts/                # Shell tools
│   ├── headroom-pi         # Wrapper (auto-start, status, restart)
│   └── headroom-health-check
├── extensions/             # Pi extension (TypeScript)
│   └── headroom-pi.ts
└── skills/                 # Pi skill
    └── headroom/SKILL.md
```

## Troubleshooting

**`headroom: command not found`**

The installer should catch this. If not:
```bash
pip install headroom-ai[proxy]
```

**401 / authentication error**

Make sure you've authenticated in pi (`/login openrouter` or set your API key).
The proxy forwards credentials from pi to the upstream.

**Proxy starts but no compression**

Check compression is working:
```bash
curl http://127.0.0.1:8787/stats | grep tokens_saved
```
If zero, you might be sending small requests. Send a prompt that reads a large
file — that's where compression kicks in.

**Port 8787 already in use**

```bash
export HEADROOM_PORT=8888
./install.sh
```

**Proxy crashes**

systemd auto-restarts it in ~2 seconds. Check:
```bash
journalctl --user -u headroom-proxy --since "5 min ago"
```

## License

Apache 2.0 — same as [Headroom](https://github.com/chopratejas/headroom). See [LICENSE](LICENSE).