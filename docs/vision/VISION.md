# Headroom-Pi Vision

## Why This Exists

Pi coding agent sessions consume large context windows, and every conversation — tool call outputs, file contents, thinking blocks — is sent to the LLM provider as-is. Token costs add up, and context limits are hit faster than necessary. Without compression, every session is more expensive, slower, and more likely to hit provider rate limits.

Headroom is a compression proxy that sits between pi and the LLM provider, transparently compressing traffic by 60–95% with zero code changes. Headroom-pi packages this as a seamless integration: install once, transparent compression forever.

## Core Intent

A zero-friction proxy layer that compresses all pi coding agent traffic through Headroom's context compression algorithms, reducing token consumption by 60–95% while preserving the agent's ability to reason over the full context.

The proxy is invisible to the user and to pi. After installation, `pi` routes through the proxy automatically. Compression happens transparently, and reversible compression (CCR) allows the LLM to reconstruct original content when needed.

## Architecture Overview

```
User runs: pi (aliased to headroom-pi wrapper)
                │
                ▼
headroom-pi (shell wrapper)
  ├─ Ensures Headroom proxy is running (auto-start via systemd)
  └─ Execs pi with overridden provider baseUrl
                │
                ▼
Headroom Proxy (:8787)
  ├─ SmartCrusher (JSON compression)
  ├─ CodeCompressor (AST-aware code compression)
  ├─ Kompress-base (ML text compression)
  ├─ CacheAligner (KV cache hit rate stabilization)
  └─ CCR (reversible compression — LLM retrieves originals)
                │
                ▼
OpenRouter / Anthropic / OpenAI (or any provider)
```

## Scope Boundaries

### This project is:
- A Headroom proxy wrapper for pi
- Systemd service + health monitoring for the proxy
- A pi extension for non-systemd environments (macOS)
- Transparent provider override (pi sees Headroom as an OpenRouter-compatible endpoint)
- Health checks with desktop notifications

### This project is not:
- A general-purpose compression tool (Headroom itself is the compression engine)
- A caching layer (Headroom's CacheAligner is about KV cache stability, not response caching)
- A model provider or router
- A monitoring or observability platform

## Guiding Principles

1. **Zero code changes** — The project exists so pi users don't need to modify pi or their workflow. Install once, forget it.
2. **Transparent operation** — The user should never need to think about the proxy. It starts on demand, health-checks itself, and recovers from crashes.
3. **Reversible compression** — Compression must not lose information that the LLM needs. CCR ensures originals are retrievable.
4. **Fail-open safety** — If the proxy is down, pi should still work (bypass to direct provider).
5. **Portable** — Works on Linux (systemd) and macOS (pi extension), with the same zero-friction experience.

## Active Tasks

- (none — project is deployed and stable; see `docs/tasks.txt` for eval task)

## Future Direction

1. Compression ratio benchmarks across different session types (coding, research, planning)
2. Configurable compression levels (more aggressive = more savings, less reversible)
3. Per-provider compression profiles
4. Prometheus metrics export for the proxy
5. Gradual rollout of compression for different message types

## A Living Vision

This document defines intent and direction, not frozen implementation details. It should evolve as Headroom's compression algorithms improve and as pi's traffic patterns change.