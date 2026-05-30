import { spawn } from "node:child_process";
import { log } from "../util/log.js";

export interface ClaudeRunOptions {
  prompt: string;
  cwd: string;
  /** JSON Schema object -> passed inline to `--json-schema` for structured output. */
  schema?: unknown;
  /** Appended to the system prompt (e.g. to force JSON-only output). */
  systemPrompt?: string;
  model?: string;
  /** Disallow edit tools (default true) so plan/review can't mutate the repo. */
  readOnly?: boolean;
  timeoutMs?: number;
  bin?: string;
  signal?: AbortSignal;
}

export interface ClaudeRunResult {
  ok: boolean;
  text: string; // the envelope's `result` text
  structured?: unknown; // parsed structured output (when a schema was used)
  sessionId?: string;
  costUsd?: number;
  raw: string;
  error?: string;
}

function tryParse(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return undefined;
  }
}

/** Pull a JSON value from a string that may be wrapped in markdown fences or prose. */
function extractJson(s: string): unknown {
  const direct = tryParse(s.trim());
  if (direct !== undefined) return direct;
  const fence = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence && fence[1]) {
    const f = tryParse(fence[1].trim());
    if (f !== undefined) return f;
  }
  const i = s.indexOf("{");
  const j = s.lastIndexOf("}");
  if (i >= 0 && j > i) {
    const b = tryParse(s.slice(i, j + 1));
    if (b !== undefined) return b;
  }
  return undefined;
}

/** Parse the `claude -p --output-format json` envelope. Pure + defensive (unit-tested). */
export function parseClaudeEnvelope(out: string, err: string, code: number | null): ClaudeRunResult {
  const trimmed = out.trim();
  if (!trimmed) {
    const e = err.trim();
    return { ok: false, text: "", raw: out, error: `claude produced no output (exit ${code})${e ? `; stderr: ${e.slice(0, 300)}` : ""}` };
  }

  let env = tryParse(trimmed);
  if (env === undefined) {
    // fallback: a leading banner/notice line before the JSON — take the last non-empty line
    const lines = trimmed.split("\n").map((l) => l.trim()).filter(Boolean);
    env = tryParse(lines[lines.length - 1] ?? "");
  }
  if (env === undefined || typeof env !== "object") {
    return { ok: false, text: "", raw: out, error: `claude: non-JSON output (exit ${code}): ${trimmed.slice(0, 300)}` };
  }

  const o = env as Record<string, unknown>;
  const isError = o["is_error"] === true || o["subtype"] === "error" || o["type"] === "error";
  const resultField = o["result"];
  const text = typeof resultField === "string" ? resultField : resultField !== undefined ? JSON.stringify(resultField) : "";

  let structured: unknown;
  if (typeof resultField === "object" && resultField !== null) structured = resultField;
  else if (typeof resultField === "string" && resultField.trim()) structured = extractJson(resultField);
  // Some configurations deliver structured output in a side field, not `result`.
  if (structured === undefined) {
    for (const k of ["structured_output", "structuredOutput", "output", "structured"]) {
      const alt = o[k];
      if (alt && typeof alt === "object") {
        structured = alt;
        break;
      }
      if (typeof alt === "string" && alt.trim()) {
        const a = extractJson(alt);
        if (a !== undefined) {
          structured = a;
          break;
        }
      }
    }
  }

  const sessionId = typeof o["session_id"] === "string" ? (o["session_id"] as string) : undefined;
  const costUsd = typeof o["total_cost_usd"] === "number" ? (o["total_cost_usd"] as number) : undefined;

  if (isError) return { ok: false, text, structured, sessionId, costUsd, raw: out, error: String(o["error"] ?? text ?? "claude error") };
  if (code !== 0) return { ok: false, text, structured, sessionId, costUsd, raw: out, error: `claude exited with code ${code}` };
  if (structured === undefined && !text.trim()) {
    const usage = o["usage"] as Record<string, unknown> | undefined;
    return {
      ok: false,
      text: "",
      structured,
      sessionId,
      costUsd,
      raw: out,
      error: `claude returned an empty result (turns=${o["num_turns"]}, output_tokens=${usage?.["output_tokens"]}); it likely used tools without emitting a final answer.`,
    };
  }
  return { ok: true, text, structured, sessionId, costUsd, raw: out };
}

/** Run `claude -p` headlessly with optional inline schema + read-only enforcement. */
export async function runClaude(opts: ClaudeRunOptions): Promise<ClaudeRunResult> {
  const bin = opts.bin || process.env.AGENTCONNECTOR_CLAUDE_BIN || "claude";

  // Prompt is a positional arg (right after -p) to avoid any stdin-delivery race.
  // --json-schema takes the schema INLINE (a JSON string), not a file path.
  // The variadic --disallowedTools goes LAST so it only consumes the tool names.
  const argv = ["-p", opts.prompt, "--output-format", "json"];
  if (opts.systemPrompt) argv.push("--append-system-prompt", opts.systemPrompt);
  if (opts.schema !== undefined) argv.push("--json-schema", JSON.stringify(opts.schema));
  if (opts.model) argv.push("--model", opts.model);
  argv.push("--add-dir", opts.cwd);
  // For planning/review we disable ALL tools so Claude answers directly in one
  // turn (with JSON) instead of going agentic — which returned empty results.
  if (opts.readOnly !== false) {
    argv.push(
      "--disallowedTools",
      "Bash",
      "Edit",
      "Write",
      "NotebookEdit",
      "Read",
      "Glob",
      "Grep",
      "Task",
      "Agent",
      "WebFetch",
      "WebSearch",
      "TodoWrite",
      "MultiEdit",
    );
  }

  return new Promise<ClaudeRunResult>((resolve) => {
    const child = spawn(bin, argv, { cwd: opts.cwd, stdio: ["ignore", "pipe", "pipe"], env: process.env });
    let out = "";
    let err = "";
    let settled = false;
    const finish = (r: ClaudeRunResult) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      resolve(r);
    };
    const timer = opts.timeoutMs
      ? setTimeout(() => {
          try {
            child.kill("SIGKILL");
          } catch {
            /* ignore */
          }
          finish({ ok: false, text: "", raw: out, error: `claude timed out after ${opts.timeoutMs}ms` });
        }, opts.timeoutMs)
      : undefined;

    opts.signal?.addEventListener("abort", () => {
      try {
        child.kill("SIGKILL");
      } catch {
        /* ignore */
      }
      finish({ ok: false, text: "", raw: out, error: "aborted" });
    });

    child.stdout?.on("data", (d) => (out += d));
    child.stderr?.on("data", (d) => (err += d));
    child.on("error", (e) => {
      log.error("claude spawn error", String(e));
      finish({ ok: false, text: "", raw: out, error: String(e) });
    });
    child.on("close", (code) => finish(parseClaudeEnvelope(out, err, code)));
  });
}
