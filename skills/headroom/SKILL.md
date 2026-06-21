# Headroom Integration

Use this skill when the user asks about:
- Token usage or token savings in the current session
- Compression performance
- Headroom proxy status or configuration
- Cost estimation for LLM prompts

## How it works

Headroom is a context compression proxy running at `http://127.0.0.1:8787`. It
compresses tool outputs, search results, logs, and other verbose content before
they reach the LLM, reducing token usage by 60–95%.

## Steps

1. Check proxy health:
   ```bash
   curl -sf http://127.0.0.1:8787/livez
   ```

2. Get compression stats:
   ```bash
   curl -s http://127.0.0.1:8787/stats | python3 -c "import sys,json; d=json.load(sys.stdin); s=d['summary']; print(f'Requests: {s[\"api_requests\"]}, Compressed: {s[\"compression\"][\"requests_compressed\"]}, Tokens saved: {s[\"compression\"][\"total_tokens_saved\"]}, Cost saved: \${s[\"cost\"][\"total_saved_usd\"]:.4f}')"
   ```

3. If the proxy is down, restart it:
   ```bash
   systemctl --user restart headroom-proxy.service
   ```

4. Check logs:
   ```bash
   journalctl --user -u headroom-proxy --since "5 minutes ago" --no-pager
   ```

## Configuration

- Port: `HEADROOM_PORT` (default: 8787)
- Upstream: `HEADROOM_UPSTREAM` — OpenRouter, Anthropic, OpenAI endpoint URL
- Slack alerts: `HEADROOM_SLACK_WEBHOOK`