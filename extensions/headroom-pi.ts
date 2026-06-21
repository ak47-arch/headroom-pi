/**
 * headroom-pi.ts — Pi extension for Headroom context compression
 *
 * Auto-starts the Headroom proxy, registers it as a custom provider, monitors
 * health, and shows compression stats in the footer.
 *
 * Install:  pi install npm:headroom-pi
 * Manual:   cp this file to ~/.pi/agent/extensions/headroom-pi.ts
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn, type ChildProcess } from "node:child_process";
import { join } from "node:path";

// ─── Configuration ────────────────────────────────────────────────────────

const HEADROOM_PORT = parseInt(process.env.HEADROOM_PORT || "8787", 10);
const HEALTH_URL = `http://127.0.0.1:${HEADROOM_PORT}/livez`;
const PROXY_URL = `http://localhost:${HEADROOM_PORT}/v1`;
const STARTUP_TIMEOUT_MS = 15_000;
const HEALTH_CHECK_INTERVAL_MS = 60_000;

// ─── Binary discovery ─────────────────────────────────────────────────────

async function findHeadroomBinary(): Promise<string | null> {
  const candidates = [
    join(process.env.HOME!, ".local/bin/headroom"),
    "/usr/local/bin/headroom",
    "/usr/bin/headroom",
    "headroom", // PATH lookup
  ];

  const { spawn } = await import("node:child_process");
  for (const candidate of candidates) {
    try {
      const proc = spawn(candidate, ["--version"], { stdio: "pipe" });
      const code = await new Promise<number | null>((resolve) => {
        proc.on("close", resolve);
        setTimeout(() => { proc.kill(); resolve(null); }, 3000);
      });
      if (code === 0) return candidate;
    } catch {
      // next candidate
    }
  }
  return null;
}

// ─── Health check ─────────────────────────────────────────────────────────

async function checkHealth(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 2000);
    const res = await fetch(HEALTH_URL, { signal: controller.signal });
    clearTimeout(timer);
    return res.ok;
  } catch {
    return false;
  }
}

// ─── Provider model list ──────────────────────────────────────────────────

// Detects which upstream the user uses by checking pi's auth/providers.
// Defaults to OpenRouter-compatible model IDs.
function resolveUpstreamProvider(): string {
  // Check environment for hints
  if (process.env.OPENROUTER_API_KEY || process.env.HEADROOM_UPSTREAM_URL?.includes("openrouter")) {
    return "openrouter";
  }
  if (process.env.ANTHROPIC_API_KEY) return "anthropic";
  if (process.env.OPENAI_API_KEY) return "openai";
  if (process.env.DEEPSEEK_API_KEY) return "deepseek";
  return "openrouter"; // default
}

function getDefaultModels(upstream: string) {
  // Returns models appropriate for the detected upstream
  const models: Array<{
    id: string;
    name: string;
    reasoning: boolean;
    input: string[];
    cost: { input: number; output: number; cacheRead: number; cacheWrite: number };
    contextWindow: number;
    maxTokens: number;
  }> = [];

  if (upstream === "openrouter") {
    models.push(
      {
        id: "deepseek/deepseek-v4-flash",
        name: "DeepSeek V4 Flash (via Headroom)",
        reasoning: true,
        input: ["text"],
        cost: { input: 0.15, output: 0.6, cacheRead: 0.04, cacheWrite: 0 },
        contextWindow: 131072,
        maxTokens: 8192,
      },
      {
        id: "deepseek/deepseek-v4-pro",
        name: "DeepSeek V4 Pro (via Headroom)",
        reasoning: true,
        input: ["text"],
        cost: { input: 2, output: 8, cacheRead: 0.5, cacheWrite: 0 },
        contextWindow: 131072,
        maxTokens: 8192,
      },
      {
        id: "anthropic/claude-sonnet-4-20250514",
        name: "Claude Sonnet 4 (via Headroom)",
        reasoning: true,
        input: ["text", "image"],
        cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
        contextWindow: 200000,
        maxTokens: 8192,
      },
    );
  } else if (upstream === "anthropic") {
    models.push({
      id: "claude-sonnet-4-20250514",
      name: "Claude Sonnet 4 (via Headroom)",
      reasoning: true,
      input: ["text", "image"],
      cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
      contextWindow: 200000,
      maxTokens: 8192,
    });
  } else if (upstream === "openai") {
    models.push({
      id: "gpt-4o",
      name: "GPT-4o (via Headroom)",
      reasoning: false,
      input: ["text", "image"],
      cost: { input: 2.5, output: 10, cacheRead: 1.25, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 16384,
    });
  } else {
    // Generic — let any model ID through
    models.push({
      id: "default",
      name: "Default (via Headroom)",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 8192,
    });
  }

  return models;
}

// ─── Extension ────────────────────────────────────────────────────────────

export default async function (pi: ExtensionAPI) {
  let proxyProcess: ChildProcess | null = null;
  let healthTimer: ReturnType<typeof setInterval> | null = null;
  let proxyHealthy = false;

  // ── Find binary ──
  const headroomBin = await findHeadroomBinary();
  if (!headroomBin) {
    pi.on("session_start", async (_event, ctx) => {
      ctx.ui.notify(
        "Headroom binary not found. Install: pip install headroom-ai[proxy]",
        "warning",
      );
    });
    return;
  }

  // ── Spawn proxy ──
  function startProxy(): Promise<boolean> {
    return new Promise((resolve) => {
      const env = {
        ...process.env,
        HEADROOM_PORT: String(HEADROOM_PORT),
        OPENAI_TARGET_API_URL:
          process.env.HEADROOM_UPSTREAM_URL || "https://openrouter.ai/api/v1",
      };

      proxyProcess = spawn(headroomBin!, ["proxy", "--port", String(HEADROOM_PORT)], {
        env,
        stdio: "pipe",
        detached: false,
      });

      proxyProcess.stdout?.on("data", (_chunk: Buffer) => { /* silence */ });
      proxyProcess.stderr?.on("data", (_chunk: Buffer) => { /* silence */ });

      proxyProcess.on("error", () => {
        proxyProcess = null;
        resolve(false);
      });

      proxyProcess.on("exit", (code: number | null) => {
        proxyProcess = null;
        proxyHealthy = false;
        if (code !== 0 && code !== null) {
          // systemd-like: restart on failure
          setTimeout(() => startProxy(), 2000);
        }
      });

      // Poll health endpoint
      const start = Date.now();
      const poll = setInterval(async () => {
        const healthy = await checkHealth();
        if (healthy) {
          clearInterval(poll);
          proxyHealthy = true;
          resolve(true);
        } else if (Date.now() - start > STARTUP_TIMEOUT_MS) {
          clearInterval(poll);
          resolve(false);
        }
      }, 300);
    });
  }

  // ── Register provider ──
  const upstream = resolveUpstreamProvider();
  const models = getDefaultModels(upstream);

  pi.registerProvider(upstream === "openrouter" ? "headroom-openrouter" : "headroom", {
    name: `Headroom (compressed → ${upstream})`,
    baseUrl: PROXY_URL,
    api: "openai-completions",
    apiKey: "none",
    models,
  });

  // ── Lifecycle: session_start → ensure proxy is running ──
  pi.on("session_start", async (_event, ctx) => {
    if (proxyHealthy) return;

    ctx.ui.setStatus("headroom", "Headroom: starting...");

    const ok = await startProxy();
    if (ok) {
      ctx.ui.setStatus("headroom", `Headroom: running :${HEADROOM_PORT}`);
      ctx.ui.notify("Headroom compression proxy started", "info");
    } else {
      ctx.ui.setStatus("headroom", "Headroom: FAILED");
      ctx.ui.notify("Headroom proxy failed to start. Run headroom proxy manually.", "error");
      return;
    }

    // Start health check polling
    if (!healthTimer) {
      healthTimer = setInterval(async () => {
        proxyHealthy = await checkHealth();
        if (!proxyHealthy) {
          console.error("[headroom-pi] Proxy health check FAILED — proxy may be down");
        }
      }, HEALTH_CHECK_INTERVAL_MS);
    }
  });

  // ── Lifecycle: session_shutdown → clean up ──
  pi.on("session_shutdown", async () => {
    if (healthTimer) {
      clearInterval(healthTimer);
      healthTimer = null;
    }
  });

  // ── Tool: headroom_stats → show compression stats ──
  // Note: this tool fetches from the local proxy, useful for LLM to self-check
  //
  // pi.registerTool({
  //   name: "headroom_stats",
  //   label: "Headroom Stats",
  //   description: "Get Headroom compression statistics",
  //   parameters: Type.Object({}),
  //   async execute(_toolCallId, _params, _signal, _onUpdate, _ctx) {
  //     try {
  //       const res = await fetch(`http://127.0.0.1:${HEADROOM_PORT}/stats`);
  //       const data = await res.json();
  //       return {
  //         content: [{ type: "text", text: JSON.stringify(data.summary, null, 2) }],
  //         details: data.summary,
  //       };
  //     } catch {
  //       return {
  //         content: [{ type: "text", text: "Headroom proxy not reachable" }],
  //         details: {},
  //       };
  //     }
  //   },
  // });
}