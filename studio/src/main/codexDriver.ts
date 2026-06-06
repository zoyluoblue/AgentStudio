import { type ChildProcess, spawn } from "node:child_process";
import { log } from "./log.js";
import { resolveBin } from "./which.js";

export type Sandbox = "read-only" | "workspace-write" | "danger-full-access";

export interface CodexAsk {
  prompt: string;
  cwd: string;
  /** resume a prior session (thread id) for multi-turn continuity */
  threadId?: string;
  sandbox?: Sandbox;
  model?: string;
  signal?: AbortSignal;
  /** partial agent_message text as it streams in */
  onDelta?: (text: string) => void;
}

export interface CodexResult {
  ok: boolean;
  text: string;
  threadId?: string;
  steps?: number;
  error?: string;
}

function buildArgs(ask: CodexAsk): string[] {
  const sandbox = ask.sandbox ?? "workspace-write";
  const a: string[] = ["exec"];
  if (ask.threadId) a.push("resume", ask.threadId);
  a.push("--json", "--skip-git-repo-check");
  // `codex exec resume` has no -s flag; set the sandbox via a config override.
  if (ask.threadId) a.push("-c", `sandbox_mode=${sandbox}`);
  else a.push("-s", sandbox);
  if (ask.model) a.push("-m", ask.model);
  a.push(ask.prompt);
  return a;
}

// Dev stub (STUDIO_FAKE=1): canned result so the UI/orchestration can be exercised fast.
function fakeCodex(ask: CodexAsk): Promise<CodexResult> {
  return new Promise((resolve) => {
    const t = setTimeout(
      () => resolve({ ok: true, text: "已按计划创建 index.html / styles.css / app.js，实现了添加、勾选完成与本地保存。", threadId: "fake", steps: 3 }),
      Number(process.env.STUDIO_FAKE_DELAY ?? 1000),
    );
    ask.signal?.addEventListener("abort", () => {
      clearTimeout(t);
      resolve({ ok: false, text: "", error: "已停止" });
    });
  });
}

/** Run `codex exec` (or resume) and stream its agent messages. Codex actually edits files. */
export function askCodex(ask: CodexAsk): Promise<CodexResult> {
  if (process.env.STUDIO_FAKE) return fakeCodex(ask);
  return new Promise((resolve) => {
    const bin = resolveBin("codex");
    if (!bin) return resolve({ ok: false, text: "", error: "codex 未找到（PATH）" });

    let threadId = ask.threadId;
    let text = "";
    let steps = 0;
    let buf = "";
    let err = "";
    let settled = false;
    const finish = (r: CodexResult) => {
      if (settled) return;
      settled = true;
      resolve(r);
    };

    const args = buildArgs(ask);
    log("codex.exec", { argv: args.slice(0, -1), promptLen: ask.prompt.length, cwd: ask.cwd });
    // stdin MUST be ignored: codex reads piped stdin as input and hangs waiting for EOF otherwise.
    const child: ChildProcess = spawn(bin, args, { cwd: ask.cwd, env: process.env, stdio: ["ignore", "pipe", "pipe"] });

    const onEvent = (ev: Record<string, unknown>) => {
      const type = ev.type as string | undefined;
      if (type === "thread.started" && typeof ev.thread_id === "string") {
        threadId = ev.thread_id;
      } else if (type === "item.completed") {
        const item = ev.item as Record<string, unknown> | undefined;
        const it = item?.type as string | undefined;
        if (it === "agent_message" && typeof item?.text === "string") {
          text += (text ? "\n" : "") + item.text;
          ask.onDelta?.(text);
        } else if (it) {
          steps += 1; // command_execution / file_change / reasoning / ...
        }
      } else if (type === "error" && typeof ev.message === "string") {
        finish({ ok: false, text, threadId, error: ev.message });
      }
    };

    child.stdout?.on("data", (d) => {
      buf += d.toString();
      let nl: number;
      // biome-ignore lint/suspicious/noAssignInExpressions: standard line splitter
      while ((nl = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line) continue;
        try {
          onEvent(JSON.parse(line) as Record<string, unknown>);
        } catch {
          /* non-JSON notice line — ignore */
        }
      }
    });
    child.stderr?.on("data", (d) => (err += d.toString()));
    ask.signal?.addEventListener("abort", () => {
      try {
        child.kill("SIGKILL");
      } catch {
        /* ignore */
      }
      finish({ ok: false, text, threadId, error: "已停止" });
    });
    child.on("error", (e) => finish({ ok: false, text, threadId, error: e.message }));
    child.on("close", (code) => {
      if (text || code === 0) finish({ ok: true, text: text || "（已完成）", threadId, steps });
      else finish({ ok: false, text, threadId, error: err.trim() || `codex exited ${code}` });
    });
  });
}
