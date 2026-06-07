import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, join } from "node:path";
import { BrowserWindow, app, dialog, ipcMain } from "electron";
import {
  type AgentKind,
  type AuthState,
  type AuthStatus,
  type Backend,
  type BusyState,
  CH,
  type ChatMessage,
  type Lane,
  type MemoryKind,
  type MemoryScope,
  type Mode,
  type ModelOption,
  type MsgKind,
  type ProjectInfo,
  type Role,
  type SessionLoad,
} from "../shared/ipc.js";
import { agentLogin, agentStatus } from "./auth.js";
import { askClaude } from "./claudeDriver.js";
import { askCodex } from "./codexDriver.js";
import { DEEPSEEK_EXECUTOR_SYSTEM, applyFiles, askDeepseek, parseFileBlocks } from "./deepseekDriver.js";
import { changesSince, projectContext, snapshot } from "./diff.js";
import { fixPath } from "./fixPath.js";
import { log, setLogFile, setLogSink } from "./log.js";
import {
  appendLearned,
  appendMemory,
  getGlobalLearned,
  getGlobalMemory,
  getProjectLearned,
  getProjectMemory,
  initMemory,
  memoryContext,
  setGlobalLearned,
  setGlobalMemory,
  setProjectLearned,
  setProjectMemory,
} from "./memory.js";
import { apiKeyFor, backendFor, connectMethodFor, getSettings, initSettings, updateSettings } from "./settings.js";
import * as store from "./store.js";

// GUI apps don't inherit the shell PATH — repair it so claude/codex/git resolve.
fixPath();

const MAX_REVISE = 3;

let win: BrowserWindow | null = null;
let projectCwd: string | null = null;
let mode: Mode = process.env.STUDIO_MODE === "collab" ? "collab" : "solo";
// Per-lane session continuity, keyed by lane (a lane can switch backends).
const claudeSessions: Record<AgentKind, string | undefined> = { claude: undefined, codex: undefined };
const codexThreads: Record<AgentKind, string | undefined> = { claude: undefined, codex: undefined };
let cancelOrchestration = false;
const busy: BusyState = { claude: false, codex: false };
const aborts: Record<AgentKind, AbortController | null> = { claude: null, codex: null };
const agentModel: Record<AgentKind, string> = { claude: "", codex: "" };
const intervene: Record<AgentKind, string> = { claude: "", codex: "" };

/** Prepend any pending user interjection for a lane to the prompt, then clear it. */
function withIntervene(prompt: string, lane: AgentKind): string {
  if (!intervene[lane]) return prompt;
  const extra = intervene[lane];
  intervene[lane] = "";
  log("intervene.consumed", { lane });
  return `（用户临时补充指令，请务必优先考虑）：${extra}\n\n${prompt}`;
}

const PLANNER_SYSTEM =
  "你是 AgentStudio 的规划助手，面向不懂编程的用户。用简洁、友好的中文交流，避免专业黑话。" +
  "把用户想做的东西拆成简短的分步实现计划（3 步以内），供右栏的执行方实现。只输出计划本身，不要写代码。";
const REVIEWER_SYSTEM =
  "你是严谨的代码审查员。基于用户目标和执行方刚做的改动（含文件内容），判断是否达成目标且没有明显问题。用简洁中文。";
const EXECUTOR_SYSTEM = "你是编码执行者，根据计划直接在当前项目里新建/修改文件实现需求，完成后用一两句话说明你做了哪些改动。";
const BACKEND_NAME: Record<Backend, string> = { claude: "Claude", codex: "Codex", deepseek: "DeepSeek" };
/** Left lane (claude key) is the master/planner; right lane (codex key) is the slave/executor. */
function laneOf(kind: AgentKind): Lane {
  return kind === "claude" ? "master" : "slave";
}

function planPrompt(goal: string): string {
  return `用户目标：${goal}\n\n请给出一个简短的分步实现计划（3 步以内），供 Codex 执行。`;
}
function executePrompt(plan: string): string {
  return `请在当前项目里按以下计划实现，直接新建/修改文件；完成后用一两句话说明你做了什么改动：\n\n${plan}`;
}
function reviewPrompt(goal: string, diff: string): string {
  return (
    `用户目标：${goal}\n\n以下是 Codex 刚做的改动（含文件内容）：\n\n${diff}\n\n` +
    `请审查是否达成目标且无明显问题。若可以，回复以「✅ 通过」开头并一句话总结；` +
    `若需修改，回复以「❌ 需修改」开头，并简要列出要改的点。`
  );
}
function revisePrompt(feedback: string): string {
  return `审查反馈如下，请据此继续修改代码：\n\n${feedback}`;
}
function verdictPass(text: string): boolean {
  const head = text.trim().slice(0, 16);
  return head.includes("✅") || head.includes("通过");
}

function send(channel: string, payload: unknown): void {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}
function authCwd(): string {
  return projectCwd ?? homedir();
}
const activity: Record<AgentKind, string> = { claude: "", codex: "" };
/** Set an agent's live phase text ("" = idle). Drives both busy + the status pill. */
function setActivity(kind: AgentKind, text: string): void {
  activity[kind] = text;
  busy[kind] = text !== "";
  send(CH.busy, { ...busy });
  send(CH.activity, { ...activity });
}

// ---- messages (with a stable sequence number per id for referencing turns) ----
let msgSeq = 0;
const msgN = new Map<string, number>();
function post(role: Role, kind: MsgKind, text: string, pending: boolean, id: string | undefined, lane: AgentKind, agentName?: string): string {
  const mid = id ?? `m${Date.now().toString(36)}_${msgSeq}`;
  let n = msgN.get(mid);
  if (n === undefined) {
    n = ++msgSeq;
    msgN.set(mid, n);
  }
  const msg: ChatMessage = { id: mid, n, role, kind, text, ts: Date.now(), lane, agentName, pending };
  send(CH.event, msg);
  store.recordMessage(msg); // persist for History / Search
  return mid;
}

function projInfo(): ProjectInfo {
  return { cwd: projectCwd, name: projectCwd ? basename(projectCwd) : null };
}
/** Find a built HTML entry to show in the live preview, if any. */
function previewUrl(): string | null {
  if (!projectCwd) return null;
  for (const f of ["index.html", "public/index.html", "dist/index.html", "build/index.html", "src/index.html"]) {
    const p = join(projectCwd, f);
    if (existsSync(p)) return `file://${p}`;
  }
  return null;
}
function setProject(p: string): void {
  let resolved = p;
  try {
    resolved = realpathSync(p); // canonical path so claude & codex operate on the SAME dir (avoids /tmp symlink mismatch)
  } catch {
    /* keep as-is */
  }
  projectCwd = resolved;
  claudeSessions.claude = claudeSessions.codex = undefined;
  codexThreads.claude = codexThreads.codex = undefined;
  store.startSession(resolved, basename(resolved), mode); // begin a fresh saved conversation
  log("project.set", { cwd: resolved });
  send(CH.projectEvent, projInfo());
}

// ---- one lane's turn, dispatched to its configured backend ----
// `write` = executor role (edits files): slave lane, or anything that should change the project.
async function laneTurn(kind: AgentKind, prompt: string, system: string, phase: string, write: boolean) {
  const lane = laneOf(kind);
  const backend = backendFor(lane);
  const name = BACKEND_NAME[backend];
  // api-key method: hand the CLI/driver the configured key; app method leaves it undefined (uses login).
  const apiKey = connectMethodFor(backend) === "key" ? apiKeyFor(backend) || undefined : undefined;
  // Long-term memory injected so every backend reads the same notes (see memory.ts).
  const mem = memoryContext(projectCwd);
  const withMem = (s: string) => (mem ? `${mem}\n\n${s}` : s);
  const pid = post(kind, write ? "progress" : "text", write ? `${name} 正在处理…` : "", true, undefined, kind, name);
  setActivity(kind, phase);
  aborts[kind] = new AbortController();
  const signal = aborts[kind]?.signal;
  const model = agentModel[kind] || undefined;
  log("lane.turn.start", { lane, backend, phase, write, model: model ?? "default", promptLen: prompt.length, cwd: projectCwd });

  let res: { ok: boolean; text: string; error?: string };
  if (backend === "claude") {
    const r = await askClaude({
      prompt,
      cwd: projectCwd as string,
      sessionId: claudeSessions[kind],
      systemPrompt: withMem(system),
      disableTools: !write,
      allowWrite: write,
      lane,
      model,
      apiKey,
      signal,
      onStatus: (s) => setActivity(kind, s),
    });
    if (r.sessionId) claudeSessions[kind] = r.sessionId;
    res = { ok: r.ok, text: r.text, error: r.error };
  } else if (backend === "codex") {
    // Codex has no system-prompt flag, so inject memory into the prompt — but only on a
    // fresh thread, since `resume` already carries the earlier (memory-bearing) turns.
    const codexPrompt = mem && !codexThreads[kind] ? `${mem}\n\n${prompt}` : prompt;
    const r = await askCodex({
      prompt: codexPrompt,
      cwd: projectCwd as string,
      threadId: codexThreads[kind],
      sandbox: write ? "workspace-write" : "read-only",
      lane,
      model,
      apiKey,
      signal,
      onDelta: (t) => post(kind, "text", t, true, pid, kind, name),
      onStatus: (s) => setActivity(kind, s),
    });
    if (r.threadId) codexThreads[kind] = r.threadId;
    const suffix = r.ok && r.steps ? `\n\n（执行了 ${r.steps} 步操作）` : "";
    res = { ok: r.ok, text: r.ok ? r.text + suffix : r.text, error: r.error };
  } else if (write) {
    // DeepSeek executor (Option B): it has no agentic harness, so it emits whole files
    // (with the current files as context) and WE write them; the master then reviews the diff.
    const ctx = projectContext(projectCwd as string);
    const full = `${prompt}\n\n当前项目文件（在此基础上新建/修改；为空则从零创建）：\n${ctx || "（空项目）"}`;
    const r = await askDeepseek({ prompt: full, systemPrompt: withMem(DEEPSEEK_EXECUTOR_SYSTEM), model, apiKey: apiKeyFor("deepseek"), signal });
    if (!r.ok) {
      res = { ok: false, text: "", error: r.error };
    } else {
      setActivity(kind, "写入文件中");
      const { files, prose } = parseFileBlocks(r.text);
      const written = applyFiles(projectCwd as string, files);
      log("deepseek.exec.applied", { files: written.length });
      const summary = written.length
        ? `\n\n📄 已写入 ${written.length} 个文件：${written.join("、")}`
        : "\n\n（未解析到文件块——请让 DeepSeek 按 <<<FILE>>> 格式输出）";
      res = { ok: true, text: (prose || "（已处理）") + summary };
    }
  } else {
    const r = await askDeepseek({ prompt, systemPrompt: withMem(system), model, apiKey: apiKeyFor("deepseek"), signal });
    res = { ok: r.ok, text: r.text, error: r.error };
  }

  log("lane.turn.done", { lane, backend, ok: res.ok, len: res.text.length, err: res.error });
  store.setAgentIds({ claudeSession: claudeSessions.claude, codexThread: codexThreads.codex }); // best-effort resume ids
  post(res.ok ? kind : "system", res.ok ? "text" : "error", res.ok ? res.text : (res.error ?? "出错了"), false, pid, kind, name);
  setActivity(kind, "");
  aborts[kind] = null;
  if (write) send(CH.previewRefresh, previewUrl()); // executor may have changed files
  return res;
}

// ---- collab: automatic plan -> execute -> review -> revise (no human button) ----
function orchStopped(): boolean {
  if (cancelOrchestration) {
    post("system", "text", "⏹ 已停止。", false, undefined, "claude");
    log("orchestration.cancelled");
    return true;
  }
  return false;
}
async function runOrchestration(goal: string): Promise<void> {
  cancelOrchestration = false;
  log("orchestration.start", { goal: goal.slice(0, 120) });
  post("user", "text", goal, false, undefined, "claude");

  const plan = await laneTurn("claude", withIntervene(planPrompt(goal), "claude"), PLANNER_SYSTEM, "规划中", false);
  if (orchStopped()) return;
  if (!plan.ok) return;

  const before = snapshot(projectCwd as string);
  const exec = await laneTurn("codex", withIntervene(executePrompt(plan.text), "codex"), EXECUTOR_SYSTEM, "执行中", true);
  if (orchStopped()) return;
  if (!exec.ok) return;

  for (let iter = 0; iter < MAX_REVISE; iter++) {
    const diff = changesSince(before, projectCwd as string);
    log("orchestration.review", { iter, diffLen: diff.length });
    const review = await laneTurn("claude", withIntervene(reviewPrompt(goal, diff), "claude"), REVIEWER_SYSTEM, "审查中", false);
    if (orchStopped()) return;
    if (!review.ok) return;
    if (verdictPass(review.text)) {
      post("system", "text", `✅ 完成：${BACKEND_NAME[backendFor("master")]} 审查通过。`, false, undefined, "claude");
      log("orchestration.done", { iter });
      void autoExtractMemory(`目标：${goal}\n计划：${plan.text}\n审查：${review.text}`, backendFor("master"));
      return;
    }
    if (iter === MAX_REVISE - 1) {
      post("system", "text", `已自动修改 ${MAX_REVISE} 轮仍未通过，请人工查看或补充说明。`, false, undefined, "claude");
      log("orchestration.exhausted");
      void autoExtractMemory(`目标：${goal}\n计划：${plan.text}\n最近审查：${review.text}`, backendFor("master"));
      return;
    }
    const revise = await laneTurn("codex", withIntervene(revisePrompt(review.text), "codex"), EXECUTOR_SYSTEM, "修订中", true);
    if (orchStopped()) return;
    if (!revise.ok) return;
  }
}

// ---- learned memory: auto-extract durable facts from a finished conversation (Codex/CC style) ----
const MEMORY_EXTRACT_SYSTEM =
  "你是记忆助理。从对话中提炼“值得长期记住”的稳定信息：用户偏好、项目约定、技术栈选择、明确决定、踩过的坑。" +
  "忽略一次性的、临时的、显而易见的内容。不要重复“已有记忆”里已存在的条目。" +
  "只输出新增条目，每行一条、精炼中文、不加序号；若没有值得记的，只输出“无”。";
const MEMORY_CONSOLIDATE_SYSTEM =
  "你是记忆整理助手。把给定的记忆条目去重、合并同类项、精简措辞，保留全部关键信息。只输出整理后的要点列表，每行一条，不要解释。";

/** One-shot text completion for memory extraction/consolidation — cheap model, no memory injection. */
async function llmComplete(backend: Backend, prompt: string, system: string): Promise<string> {
  const cwd = authCwd();
  const keyOf = (b: Backend) => (connectMethodFor(b) === "key" ? apiKeyFor(b) || undefined : undefined);
  try {
    if (backend === "deepseek") {
      const r = await askDeepseek({ prompt, systemPrompt: system, model: "deepseek-chat", apiKey: apiKeyFor("deepseek") });
      return r.ok ? r.text : "";
    }
    if (backend === "claude") {
      const r = await askClaude({ prompt, cwd, systemPrompt: system, disableTools: true, model: "haiku", lane: "master", apiKey: keyOf("claude") });
      return r.ok ? r.text : "";
    }
    const r = await askCodex({ prompt: `${system}\n\n${prompt}`, cwd, sandbox: "read-only", lane: "master", apiKey: keyOf("codex") });
    return r.ok ? r.text : "";
  } catch (e) {
    log("memory.llm.error", { backend, err: String(e) });
    return "";
  }
}

/** Silently extract durable facts from a finished conversation into learned memory. */
async function autoExtractMemory(transcript: string, backend: Backend): Promise<void> {
  if (!getSettings().autoMemory) return;
  const cwd = projectCwd;
  const known = `${cwd ? getProjectMemory(cwd) : getGlobalMemory()}\n${cwd ? getProjectLearned(cwd) : getGlobalLearned()}`.trim();
  const prompt =
    `已有记忆（不要重复其中已有的）：\n${known || "（空）"}\n\n本次对话：\n${transcript.slice(0, 6000)}\n\n请只输出新增、值得长期记住的要点：`;
  const text = await llmComplete(backend, prompt, MEMORY_EXTRACT_SYSTEM);
  const lines = text
    .split("\n")
    .map((s) => s.replace(/^[-*•\d.、)\s]+/, "").trim())
    .filter((l) => l && l !== "无" && l.length > 2);
  if (lines.length) appendLearned(cwd, lines);
}

async function handleSend(text: string, target: AgentKind): Promise<void> {
  if (!projectCwd) {
    post("system", "error", "请先选择一个项目文件夹。", false, undefined, target);
    return;
  }

  // 记住/别忘了/… xxx — store a fact in curated memory instead of running a turn.
  const remember = text.match(
    /^\s*(?:记住|记一下|记下来|记下|别忘了|别忘记|不要忘记|不要忘|牢记|务必记住|以后记得|以后注意|请记住|remember|don'?t forget|note that|keep in mind|make a note)\s*(?:[:：,，]|\s)\s*([\s\S]+?)\s*$/i,
  );
  if (remember?.[1]) {
    const fact = remember[1].trim();
    appendMemory(projectCwd, fact);
    post("user", "text", text, false, undefined, target);
    post("system", "text", `🧠 已记住（${projectCwd ? "项目记忆" : "全局记忆"}）：${fact}`, false, undefined, target);
    log("memory.remember", { lane: target, len: fact.length });
    return;
  }

  // 随时插话: if something is already running, inject this message instead of starting fresh.
  const running = mode === "collab" ? busy.claude || busy.codex : busy[target];
  if (running) {
    const lane: AgentKind = mode === "collab" ? "claude" : target;
    log("interject", { target, mode, len: text.length });
    post("user", "text", text, false, undefined, lane);
    if (mode === "collab") {
      intervene.claude += (intervene.claude ? "\n" : "") + text;
      intervene.codex += (intervene.codex ? "\n" : "") + text;
    } else {
      intervene[target] += (intervene[target] ? "\n" : "") + text;
    }
    return;
  }

  log("send", { target, mode, len: text.length });
  if (mode === "collab") {
    await runOrchestration(text);
  } else {
    post("user", "text", text, false, undefined, target);
    let next: string | null = text;
    let lastReply = "";
    while (next) {
      const res =
        target === "claude"
          ? await laneTurn("claude", next, PLANNER_SYSTEM, "思考中", false)
          : await laneTurn("codex", next, EXECUTOR_SYSTEM, "执行中", true);
      if (!res.ok) break;
      lastReply = res.text;
      next = intervene[target] || null; // a follow-up that was interjected mid-turn
      intervene[target] = "";
    }
    if (lastReply) void autoExtractMemory(`用户：${text}\n助手：${lastReply}`, backendFor(laneOf(target)));
  }
}

function abortAll(): void {
  cancelOrchestration = true;
  aborts.claude?.abort();
  aborts.codex?.abort();
  log("abort.all");
}

/** Load a saved conversation into the live chat and restore agent context for "继续对话". */
function resumeSession(id: string, focusMessageId?: string): void {
  const s = store.get(id);
  if (!s) return;
  abortAll();
  cancelOrchestration = false;
  projectCwd = s.projectCwd;
  claudeSessions.claude = s.claudeSession; // best-effort: master claude / slave codex
  claudeSessions.codex = undefined;
  codexThreads.codex = s.codexThread;
  codexThreads.claude = undefined;
  mode = s.mode;
  store.adoptSession(s); // new messages append to this conversation
  log("history.resume", { id, msgs: s.messages.length, mode });
  send(CH.modeEvent, mode);
  send(CH.sessionLoad, { project: projInfo(), mode, messages: s.messages, focusMessageId } satisfies SessionLoad);
}

// ---- auth: session-scoped, NOT persisted (disconnected by default each launch) ----
const sessionAuth: AuthState = { claude: { connected: false }, codex: { connected: false } };
async function connectAgent(kind: AgentKind): Promise<AuthStatus> {
  log("auth.connect.start", { kind });
  const cur = await agentStatus(kind, authCwd());
  if (cur.connected) {
    sessionAuth[kind] = cur;
    log("auth.connect.done", { kind, connected: true, via: "existing-login" });
    return cur;
  }
  const label = kind === "claude" ? "Claude" : "Codex";
  const st = await agentLogin(kind, authCwd(), (url) => {
    post("system", "text", `如果浏览器没有自动打开，请手动访问以下链接完成 ${label} 登录：\n${url}`, false, undefined, kind);
  });
  sessionAuth[kind] = st;
  log("auth.connect.done", { kind, connected: st.connected, via: "login-flow" });
  return st;
}

/** Fetch model ids from an OpenAI-compatible `/models` endpoint; [] on any failure. */
async function fetchModelIds(url: string, headers: Record<string, string>, backend: Backend): Promise<string[]> {
  try {
    const res = await fetch(url, { headers });
    if (!res.ok) {
      log("models.list.http", { backend, status: res.status });
      return [];
    }
    const data = (await res.json()) as { data?: { id?: string }[] };
    const ids = (data.data ?? []).map((d) => d.id).filter((x): x is string => !!x);
    log("models.list", { backend, n: ids.length });
    return ids;
  } catch (e) {
    log("models.list.error", { backend, err: String(e) });
    return [];
  }
}

// Claude's selectable models. The CLI's --model accepts these full ids (and the [1m] 1M-context
// variants), so the picker can offer the same set the official Claude Code menu shows.
const CLAUDE_MODELS: ModelOption[] = [
  { id: "claude-opus-4-8", label: "Opus 4.8" },
  { id: "claude-opus-4-8[1m]", label: "Opus 4.8 (1M context)" },
  { id: "claude-sonnet-4-6", label: "Sonnet 4.6" },
  { id: "claude-haiku-4-5", label: "Haiku 4.5" },
  { id: "claude-opus-4-7", label: "Opus 4.7 (Legacy)" },
  { id: "claude-opus-4-7[1m]", label: "Opus 4.7 (1M context, Legacy)" },
  { id: "claude-opus-4-6", label: "Opus 4.6 (Legacy)" },
];

/** Read Codex's own model cache (`~/.codex/models_cache.json`) — the list `codex -m` accepts. */
function codexModels(): ModelOption[] {
  try {
    const p = join(homedir(), ".codex", "models_cache.json");
    if (!existsSync(p)) return [];
    const data = JSON.parse(readFileSync(p, "utf8")) as { models?: { slug?: string; display_name?: string; visibility?: string }[] };
    const list = (data.models ?? [])
      .filter((m) => m.visibility === "list" && !!m.slug)
      .map((m) => ({ id: m.slug as string, label: m.display_name || (m.slug as string) }));
    log("models.codex.cache", { n: list.length });
    return list;
  } catch (e) {
    log("models.codex.cache.error", { err: String(e) });
    return [];
  }
}

/**
 * Selectable models for a backend. Codex comes from its local cache (kept fresh by Codex itself),
 * DeepSeek/Anthropic are fetched live in api-key mode (so new models like DeepSeek V4 appear
 * automatically), and Claude has a curated list mirroring the official picker.
 */
async function listModels(backend: Backend): Promise<ModelOption[]> {
  const key = apiKeyFor(backend);
  const usingKey = connectMethodFor(backend) === "key" && !!key;
  const toOptions = (ids: string[]): ModelOption[] => ids.map((id) => ({ id, label: id }));

  if (backend === "deepseek") {
    const fallback = toOptions(["deepseek-chat", "deepseek-reasoner"]);
    if (!key) return fallback;
    const ids = await fetchModelIds("https://api.deepseek.com/models", { Authorization: `Bearer ${key}` }, backend);
    return ids.length ? toOptions(ids.sort()) : fallback;
  }

  if (backend === "claude") {
    if (!usingKey) return CLAUDE_MODELS; // app login → curated set (the CLI accepts these ids)
    // api-key mode: keep the curated set, append any newer ids the live API reports
    const ids = await fetchModelIds("https://api.anthropic.com/v1/models", { "x-api-key": key, "anthropic-version": "2023-06-01" }, backend);
    const known = new Set(CLAUDE_MODELS.map((m) => m.id));
    const extra = toOptions(ids.filter((id) => !known.has(id)).sort().reverse());
    return [...CLAUDE_MODELS, ...extra];
  }

  // codex — its CLI takes the slugs from its own cache regardless of auth mode
  const codex = codexModels();
  if (codex.length) return codex;
  if (usingKey) {
    const ids = await fetchModelIds("https://api.openai.com/v1/models", { Authorization: `Bearer ${key}` }, backend);
    const chat = ids.filter((id) => /^(?:gpt-|o\d|chatgpt|codex)/.test(id));
    return toOptions((chat.length ? chat : ids).sort().reverse());
  }
  return codex; // empty → the picker falls back to a free-text field
}

function capture(path: string): void {
  void win?.webContents
    .capturePage()
    .then((img) => {
      writeFileSync(path, img.toPNG());
      console.error(`[main] captured screenshot -> ${path}`);
    })
    .catch((e) => console.error("[main] capture failed", e));
}

function createWindow(): void {
  win = new BrowserWindow({
    width: Number(process.env.STUDIO_WIN_WIDTH) || 1440,
    height: Number(process.env.STUDIO_WIN_HEIGHT) || 920,
    minWidth: 1040,
    minHeight: 640,
    title: "AgentStudio",
    backgroundColor: "#0e0f13",
    webPreferences: { preload: join(__dirname, "../preload/index.js"), contextIsolation: true, sandbox: false, webviewTag: true },
  });

  // Dev-only: STUDIO_VIEW=history|search opens straight to that view (for screenshots).
  const initialHash = process.env.STUDIO_VIEW ? `view=${process.env.STUDIO_VIEW}` : "";
  if (process.env.ELECTRON_RENDERER_URL) void win.loadURL(process.env.ELECTRON_RENDERER_URL + (initialHash ? `#${initialHash}` : ""));
  else void win.loadFile(join(__dirname, "../renderer/index.html"), initialHash ? { hash: initialHash } : undefined);

  win.webContents.on("did-finish-load", () => console.error("[main] renderer loaded OK"));
  win.webContents.on("preload-error", (_e, p, err) => console.error(`[preload-error] ${p}:`, err));
  win.webContents.on("did-fail-load", (_e, code, desc) => console.error(`[did-fail-load] ${code} ${desc}`));

  // Dev affordances.
  const shotPath = process.env.STUDIO_SHOT;
  const demo = process.env.STUDIO_DEMO;
  win.webContents.on("did-finish-load", () => {
    if (demo) {
      const demoDir = process.env.STUDIO_DEMO_DIR || join(tmpdir(), "agentstudio-demo");
      try {
        mkdirSync(demoDir, { recursive: true });
      } catch {
        /* ignore */
      }
      setProject(demoDir);
      // When STUDIO_SHOT_DELAY is set, capture on a fixed timer (can land mid-orchestration);
      // otherwise capture once the turn(s) settle.
      const fixedDelay = process.env.STUDIO_SHOT_DELAY;
      if (shotPath && fixedDelay) setTimeout(() => capture(shotPath), Number(fixedDelay));
      void handleSend(demo, "claude").then(async () => {
        const cd = process.env.STUDIO_DEMO_CODEX;
        if (cd && mode === "solo") await handleSend(cd, "codex");
        if (shotPath && !fixedDelay) setTimeout(() => capture(shotPath), 3500);
      });
    } else if (shotPath) {
      setTimeout(() => capture(shotPath), Number(process.env.STUDIO_SHOT_DELAY ?? 8000));
    }
  });

  win.on("closed", () => {
    win = null;
  });
}

app.whenReady().then(() => {
  setLogFile(join(app.getPath("userData"), "logs", "agentstudio.log"));
  setLogSink((line) => send(CH.logLine, line));
  store.initStore(join(app.getPath("userData"), "history"));
  initSettings(join(app.getPath("userData"), "settings.json"));
  initMemory(join(app.getPath("userData"), "memory"));
  log("app.ready", { mode, userData: app.getPath("userData") });

  ipcMain.handle(CH.send, (_e, p: { text: string; target: AgentKind }) => handleSend(p.text, p.target));
  ipcMain.on(CH.abort, (_e, target: AgentKind) => {
    log("abort", { target, mode });
    if (mode === "collab") abortAll();
    else aborts[target]?.abort();
  });

  ipcMain.handle(CH.modeGet, () => mode);
  ipcMain.on(CH.modeSet, (_e, m: Mode) => {
    mode = m;
    store.setMode(m);
    log("mode.set", { mode });
    send(CH.modeEvent, mode);
  });
  ipcMain.on(CH.modelSet, (_e, p: { agent: AgentKind; model: string }) => {
    agentModel[p.agent] = p.model;
    log("model.set", { agent: p.agent, model: p.model || "default" });
  });

  ipcMain.handle(CH.projectGet, () => projInfo());
  ipcMain.handle(CH.projectPick, async () => {
    const target = win ?? BrowserWindow.getAllWindows()[0];
    const r = await dialog.showOpenDialog(target, { properties: ["openDirectory", "createDirectory"], buttonLabel: "选择项目" });
    if (!r.canceled && r.filePaths[0]) setProject(r.filePaths[0]);
    return projInfo();
  });

  ipcMain.handle(CH.previewGet, () => ({ url: previewUrl() }));

  ipcMain.handle(CH.authGet, () => sessionAuth);
  ipcMain.handle(CH.authConnect, async (_e, kind: AgentKind) => {
    const st = await connectAgent(kind);
    send(CH.authEvent, sessionAuth);
    return st;
  });
  // Soft disconnect: forget the connection in-app only. We deliberately do NOT run the CLI
  // logout, so the user's global `claude` / `codex` login (shared with their terminal) is kept.
  ipcMain.handle(CH.authDisconnect, (_e, kind: AgentKind) => {
    sessionAuth[kind] = { connected: false };
    log("auth.disconnect", { kind });
    send(CH.authEvent, sessionAuth);
  });

  // ---- history & search ----
  ipcMain.handle(CH.historyList, () => store.list());
  ipcMain.handle(CH.historyGet, (_e, id: string) => store.get(id));
  ipcMain.handle(CH.historyResume, (_e, p: { id: string; focusMessageId?: string }) => resumeSession(p.id, p.focusMessageId));
  ipcMain.handle(CH.historyDelete, (_e, id: string) => store.remove(id));
  ipcMain.handle(CH.historyRename, (_e, p: { id: string; title: string }) => store.rename(p.id, p.title));
  ipcMain.handle(CH.searchQuery, (_e, q: string) => store.search(q));

  // ---- settings ----
  ipcMain.handle(CH.settingsGet, () => getSettings());
  ipcMain.handle(CH.settingsSet, (_e, patch) => updateSettings(patch));
  ipcMain.handle(CH.modelsList, (_e, backend: Backend) => listModels(backend));

  // ---- memory ----
  ipcMain.handle(CH.memoryGet, (_e, p: { scope: MemoryScope; kind?: MemoryKind }) => {
    if (p.kind === "learned") return p.scope === "global" ? getGlobalLearned() : getProjectLearned(projectCwd);
    return p.scope === "global" ? getGlobalMemory() : getProjectMemory(projectCwd);
  });
  ipcMain.handle(CH.memorySet, (_e, p: { scope: MemoryScope; content: string; kind?: MemoryKind }) => {
    if (p.kind === "learned") {
      if (p.scope === "global") setGlobalLearned(p.content);
      else setProjectLearned(projectCwd, p.content);
    } else if (p.scope === "global") setGlobalMemory(p.content);
    else setProjectMemory(projectCwd, p.content);
  });
  ipcMain.handle(CH.memoryConsolidate, async (_e, scope: MemoryScope) => {
    const cur = scope === "global" ? getGlobalLearned() : getProjectLearned(projectCwd);
    if (!cur.trim()) return cur;
    const cleaned = (await llmComplete(backendFor("master"), `请整理以下记忆：\n\n${cur}`, MEMORY_CONSOLIDATE_SYSTEM)).trim();
    if (!cleaned) return cur;
    if (scope === "global") setGlobalLearned(cleaned);
    else setProjectLearned(projectCwd, cleaned);
    return cleaned;
  });

  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("before-quit", () => store.flush()); // persist the in-flight conversation

app.on("window-all-closed", () => {
  store.flush();
  if (process.platform !== "darwin") app.quit();
});
