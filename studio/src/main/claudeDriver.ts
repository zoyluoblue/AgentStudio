import { spawn } from "node:child_process";
import { log } from "./log.js";
import { resolveBin } from "./which.js";

export interface ClaudeAsk {
  prompt: string;
  cwd: string;
  /** resume a prior session for multi-turn continuity */
  sessionId?: string;
  systemPrompt?: string;
  model?: string;
  /** inline JSON Schema -> forces structured output (returned in `structured`) */
  schema?: unknown;
  /** disable ALL tools so Claude answers directly in one turn (no agentic wandering) */
  disableTools?: boolean;
  signal?: AbortSignal;
  /** live status updates (e.g. "重连中") during retries */
  onStatus?: (s: string) => void;
}

export interface ClaudeResult {
  ok: boolean;
  text: string;
  structured?: unknown;
  sessionId?: string;
  error?: string;
}

// Disabling every tool makes `claude -p` answer in a single turn with clean output
// instead of going agentic (which can return an empty final result).
const ALL_TOOLS = [
  "Bash", "Edit", "Write", "MultiEdit", "NotebookEdit",
  "Read", "Glob", "Grep", "Task", "Agent",
  "WebFetch", "WebSearch", "TodoWrite",
];

// Network blips worth retrying (the "socket connection was closed unexpectedly" class).
const TRANSIENT =
  /socket|econnreset|closed unexpectedly|fetch failed|time.?d? ?out|\bnetwork\b|etimedout|enotfound|epipe|connection (?:closed|reset|error)|stream/i;

function delay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((res) => {
    const t = setTimeout(res, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(t);
      res();
    });
  });
}

// Dev stub (STUDIO_FAKE=1): canned plan / review so the chat UI works without a live API call.
function fakeClaude(ask: ClaudeAsk): Promise<ClaudeResult> {
  const isReview = ask.prompt.includes("审查") || ask.prompt.includes("git diff");
  const text = isReview
    ? "✅ 通过：改动实现了待办清单的添加、完成勾选与本地保存，没有发现明显问题。"
    : [
        "好的！我把它拆成 3 步：",
        "",
        "1. 页面框架 —— 顶部一个输入框，下面一个清单区，整体居中、留白干净。",
        "2. 增删改 —— 回车即添加；每条可勾选完成、也能删除。",
        "3. 本地保存 —— 用浏览器本地存储，刷新后内容不丢。",
        "",
        "下面交给 Codex 按这个计划实现。",
      ].join("\n");
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve({ ok: true, text, sessionId: "fake" }), Number(process.env.STUDIO_FAKE_DELAY ?? 900));
    ask.signal?.addEventListener("abort", () => {
      clearTimeout(t);
      resolve({ ok: false, text: "", error: "已停止" });
    });
  });
}

function parseEnvelope(out: string, code: number | null, err: string): ClaudeResult {
  const trimmed = out.trim();
  if (!trimmed) return { ok: false, text: "", error: err.trim() || `claude exited ${code}` };
  let o: Record<string, unknown>;
  try {
    o = JSON.parse(trimmed) as Record<string, unknown>;
  } catch {
    return code === 0 ? { ok: true, text: trimmed } : { ok: false, text: trimmed, error: `claude exited ${code}` };
  }
  const text = typeof o.result === "string" ? (o.result as string) : "";
  const sessionId = typeof o.session_id === "string" ? (o.session_id as string) : undefined;
  const structured = o.structured ?? undefined;
  if (o.is_error) return { ok: false, text, structured, sessionId, error: String(o.error ?? text ?? "claude error") };
  if (code !== 0) return { ok: false, text, structured, sessionId, error: `claude exited ${code}` };
  return { ok: true, text, structured, sessionId };
}

/**
 * Build a clean env for the spawned claude: drop a proxy base URL / injected API keys
 * and harness vars so it uses the default endpoint + the user's normal login. This fixes
 * "socket connection closed unexpectedly" when a proxy with a short timeout drops long requests.
 */
function spawnEnv(): NodeJS.ProcessEnv {
  const e: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (v === undefined) continue;
    if (k.startsWith("CLAUDE_CODE_")) continue;
    if (k === "ANTHROPIC_BASE_URL" || k === "ANTHROPIC_API_KEY" || k === "ANTHROPIC_AUTH_TOKEN" || k === "ANTHROPIC_MODEL") continue;
    e[k] = v;
  }
  return e;
}

function askClaudeOnce(ask: ClaudeAsk): Promise<ClaudeResult> {
  return new Promise((resolve) => {
    const bin = resolveBin("claude");
    if (!bin) return resolve({ ok: false, text: "", error: "claude 未找到（PATH）" });

    const argv = ["-p", ask.prompt, "--output-format", "json"];
    if (ask.systemPrompt) argv.push("--append-system-prompt", ask.systemPrompt);
    if (ask.schema !== undefined) argv.push("--json-schema", JSON.stringify(ask.schema));
    if (ask.model) argv.push("--model", ask.model);
    if (ask.sessionId) argv.push("--resume", ask.sessionId);
    argv.push("--add-dir", ask.cwd);
    if (ask.disableTools) argv.push("--disallowedTools", ...ALL_TOOLS); // variadic — keep LAST

    let out = "";
    let err = "";
    let settled = false;
    const finish = (r: ClaudeResult) => {
      if (settled) return;
      settled = true;
      resolve(r);
    };

    log("claude.exec", { model: ask.model || "default", resume: !!ask.sessionId, cwd: ask.cwd, baseUrl: process.env.ANTHROPIC_BASE_URL ? "stripped" : "default" });
    const child = spawn(bin, argv, { cwd: ask.cwd, stdio: ["ignore", "pipe", "pipe"], env: spawnEnv() });
    ask.signal?.addEventListener("abort", () => {
      try {
        child.kill("SIGKILL");
      } catch {
        /* ignore */
      }
      finish({ ok: false, text: "", error: "已停止" });
    });
    child.stdout.on("data", (d) => (out += d.toString()));
    child.stderr.on("data", (d) => (err += d.toString()));
    child.on("error", (e) => finish({ ok: false, text: "", error: e.message }));
    child.on("close", (code) => finish(parseEnvelope(out, code, err)));
  });
}

/** Run `claude -p`, retrying a couple times on transient network errors (socket closed, timeouts). */
export async function askClaude(ask: ClaudeAsk): Promise<ClaudeResult> {
  if (process.env.STUDIO_FAKE) return fakeClaude(ask);
  let last: ClaudeResult = { ok: false, text: "", error: "claude 未运行" };
  for (let attempt = 0; attempt < 3; attempt++) {
    if (ask.signal?.aborted) return { ok: false, text: "", error: "已停止" };
    last = await askClaudeOnce(ask);
    if (last.ok || !last.error || last.error === "已停止" || !TRANSIENT.test(last.error)) return last;
    console.error(`[claude] transient error (try ${attempt + 1}/3): ${last.error.slice(0, 120)} — retrying`);
    ask.onStatus?.(`重连中（第 ${attempt + 1} 次重试）`);
    await delay(700 * (attempt + 1), ask.signal);
  }
  return { ...last, error: `${last.error ?? "网络错误"}（已重试 3 次仍失败，请稍后再试）` };
}
