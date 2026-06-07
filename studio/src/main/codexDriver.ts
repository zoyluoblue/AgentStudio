import { type ChildProcess, spawn } from "node:child_process";
import type { Lane } from "../shared/ipc.js";
import { log } from "./log.js";
import { applyProxy } from "./settings.js";
import { resolveBin } from "./which.js";

export type Sandbox = "read-only" | "workspace-write" | "danger-full-access";

export interface CodexAsk {
  prompt: string;
  cwd: string;
  /** resume a prior session (thread id) for multi-turn continuity */
  threadId?: string;
  sandbox?: Sandbox;
  model?: string;
  /** API key (api-key method): injected as OPENAI_API_KEY. Omit to use the ChatGPT login. */
  apiKey?: string;
  /** lane this run belongs to (for proxy scoping) */
  lane?: Lane;
  signal?: AbortSignal;
  /** partial agent_message text as it streams in */
  onDelta?: (text: string) => void;
  /** live phase text as codex works (思考中 / 运行命令 / 修改文件 / …) */
  onStatus?: (text: string) => void;
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
  // Isolate from the machine's own Codex memory (~/.codex/memories etc.) — AgentStudio injects
  // its own memory instead, so every lane uses only our memory. `-c` works for exec + resume.
  a.push("-c", "features.memories=false", "-c", "features.goals=false", "-c", "features.chronicle=false");
  // `codex exec resume` has no -s flag; set the sandbox via a config override.
  if (ask.threadId) a.push("-c", `sandbox_mode=${sandbox}`);
  else a.push("-s", sandbox);
  if (ask.model) a.push("-m", ask.model);
  a.push(ask.prompt);
  return a;
}

/** Map a codex stream item to a short live status pill ("" = no change). */
function itemStatus(item: Record<string, unknown> | undefined): string | null {
  const it = item?.type as string | undefined;
  switch (it) {
    case "reasoning":
      return "思考中";
    case "command_execution": {
      const cmd = typeof item?.command === "string" ? item.command : "";
      const short = cmd.replace(/\s+/g, " ").trim().slice(0, 36);
      return short ? `运行命令：${short}` : "运行命令中";
    }
    case "file_change": {
      const changes = (item?.changes as Array<Record<string, unknown>> | undefined) ?? [];
      const first = changes[0]?.path;
      const name = typeof first === "string" ? (first.split("/").pop() ?? first) : "";
      const more = changes.length > 1 ? ` 等 ${changes.length} 个文件` : "";
      return name ? `修改 ${name}${more}` : "修改文件中";
    }
    case "mcp_tool_call":
      return "调用工具中";
    case "web_search":
      return "联网搜索中";
    case "agent_message":
      return "整理结果中";
    default:
      return it ? "执行中" : null;
  }
}

// Dev stub (STUDIO_FAKE=1): canned result so the UI/orchestration can be exercised fast.
function fakeCodex(ask: CodexAsk): Promise<CodexResult> {
  const total = Number(process.env.STUDIO_FAKE_DELAY ?? 1000);
  const stages = ["思考中", "运行命令：npm install", "修改 index.html 等 3 个文件", "整理结果中"];
  const timers: ReturnType<typeof setTimeout>[] = [];
  return new Promise((resolve) => {
    stages.forEach((s, i) => {
      timers.push(setTimeout(() => ask.onStatus?.(s), Math.floor((total * (i + 1)) / (stages.length + 1))));
    });
    timers.push(
      setTimeout(
        () => resolve({ ok: true, text: "已按计划创建 index.html / styles.css / app.js，实现了添加、勾选完成与本地保存。", threadId: "fake", steps: 3 }),
        total,
      ),
    );
    ask.signal?.addEventListener("abort", () => {
      for (const t of timers) clearTimeout(t);
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
    const env = applyProxy({ ...process.env }, ask.lane ?? "slave"); // honor proxy setting + scope
    if (ask.apiKey) env.OPENAI_API_KEY = ask.apiKey; // api-key method: authenticate with the key, not the ChatGPT login
    const child: ChildProcess = spawn(bin, args, { cwd: ask.cwd, env, stdio: ["ignore", "pipe", "pipe"] });

    const onEvent = (ev: Record<string, unknown>) => {
      const type = ev.type as string | undefined;
      if (type === "thread.started" && typeof ev.thread_id === "string") {
        threadId = ev.thread_id;
      } else if (type === "item.started") {
        // Surface what codex is about to do as a live status pill.
        const s = itemStatus(ev.item as Record<string, unknown> | undefined);
        if (s) ask.onStatus?.(s);
      } else if (type === "item.completed") {
        const item = ev.item as Record<string, unknown> | undefined;
        const it = item?.type as string | undefined;
        if (it === "agent_message" && typeof item?.text === "string") {
          text += (text ? "\n" : "") + item.text;
          ask.onDelta?.(text);
        } else if (it) {
          steps += 1; // command_execution / file_change / reasoning / ...
          const s = itemStatus(item);
          if (s) ask.onStatus?.(s); // keep the pill meaningful between steps
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
