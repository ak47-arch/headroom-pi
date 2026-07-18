---
type: Architecture
title: headroom-pi Architecture
description: Data flow and compression pipeline for headroom-pi. Documents how pi agent traffic is intercepted, compressed by Headroom's multi-strategy pipeline, and forwarded to upstream LLM providers.
tags: [headroom-pi, architecture, compression, proxy]
---

# Architecture Overview

## Data Flow

```
┌──────────┐     ┌─────────────────┐     ┌──────────────┐
│   pi     │ ──→ │  Headroom Proxy │ ──→ │  OpenRouter   │
│  agent   │     │  127.0.0.1:8787 │     │  Anthropic     │
└──────────┘     │                 │     │  OpenAI        │
                 │  Compression:   │     │  DeepSeek      │
                 │   • SmartCrusher│     └──────────────┘
                 │   • CodeCompress│
                 │   • Kompress-bas│
                 │   • CacheAligner│
                 │                 │
                 │  Features:      │
                 │   • CCR retriev│
                 │   • Cross-agent │
                 │     memory      │
                 │   • Output shapr│
                 └─────────────────┘
```

The flow is straightforward:

1. **pi agent** sends prompts, tool outputs, and file content to the Headroom proxy (localhost:8787) instead of directly to an LLM provider
2. **Headroom** inspects content type, selects the best compression strategy, and shrinks the payload
3. **Compressed content** is forwarded to the upstream LLM (OpenRouter, Anthropic, OpenAI, or DeepSeek)
4. **LLM response** passes back through Headroom to pi untouched
5. **CCR (Context-Compressed Retrieval)**: if the LLM needs original details, it calls `headroom_retrieve` to decompress

## Compression Pipeline

Headroom employs multiple compression strategies, chosen per-content-type:

| Strategy | Content Target | Mechanism |
|----------|---------------|-----------|
| **SmartCrusher** | JSON payloads | Structure-aware minification |
| **CodeCompressor** | Source code, ASTs | Language-aware AST compression |
| **Kompress-base** | Natural language text | ML-based text compression |
| **CacheAligner** | KV cache | Optimizes cache hit patterns |

## When Compression Activates

Compression is selective — it targets **verbose content**:

| Content Type | Compressed? | Typical Savings |
|-------------|-------------|-----------------|
| System prompts | No | 0% |
| Short user messages | No | 0% |
| File reads + model switch | Yes | ~12% |
| Code search results (100 results) | Yes | ~92% |
| Error logs / tool outputs | Yes | ~60-95% |
| RAG chunks | Yes | ~60-95% |
| SRE incident debugging sessions | Yes | ~92% |

The savings compound over long sessions as more tool output accumulates.

## Integration Surfaces

The [Pi Integration](/openwiki/integrations/pi-agent.md) page details the three ways pi connects to the proxy:

1. **Shell wrapper** — bash script that manages systemd service, then execs pi
2. **TypeScript extension** — lifecycle-aware extension that spawns the proxy process and registers a custom provider
3. **Pi skill** — teaches pi to use Headroom features like CCR and cross-agent memory

The [Operations](/openwiki/operations/operations.md) page covers how the systemd service maintains uptime.

## Provider Detection

The extension auto-detects which upstream provider to use by inspecting environment variables:

| Env var present | Provider | Default model |
|-----------------|----------|---------------|
| `OPENROUTER_API_KEY` (or `HEADROOM_UPSTREAM_URL` contains "openrouter") | OpenRouter | DeepSeek V4 Flash |
| `ANTHROPIC_API_KEY` | Anthropic | Claude Sonnet 4 |
| `OPENAI_API_KEY` | OpenAI | GPT-4o |
| `DEEPSEEK_API_KEY` | DeepSeek | DeepSeek V4 Flash |
| None of the above | OpenRouter (fallback) | DeepSeek V4 Flash |

## Key Source Files

| File | Role |
|------|------|
| `/extensions/headroom-pi.ts` | Pi extension — all proxy lifecycle, provider registration, model config |
| `/scripts/headroom-pi` | Bash wrapper — systemd management, proxy health polling |
| `/package.json` | Pi package manifest declaring extension and skill paths |