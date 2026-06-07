import { existsSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
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
  type Mode,
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
import { backendFor, deepseekKey, getSettings, initSettings, updateSettings } from "./settings.js";
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
      systemPrompt: system,
      disableTools: !write,
      allowWrite: write,
      lane,
      model,
      signal,
      onStatus: (s) => setActivity(kind, s),
    });
    if (r.sessionId) claudeSessions[kind] = r.sessionId;
    res = { ok: r.ok, text: r.text, error: r.error };
  } else if (backend === "codex") {
    const r = await askCodex({
      prompt,
      cwd: projectCwd as string,
      threadId: codexThreads[kind],
      sandbox: write ? "workspace-write" : "read-only",
      lane,
      model,
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
    const r = await askDeepseek({ prompt: full, systemPrompt: DEEPSEEK_EXECUTOR_SYSTEM, model, apiKey: deepseekKey(), signal });
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
    const r = await askDeepseek({ prompt, systemPrompt: system, model, apiKey: deepseekKey(), signal });
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
      return;
    }
    if (iter === MAX_REVISE - 1) {
      post("system", "text", `已自动修改 ${MAX_REVISE} 轮仍未通过，请人工查看或补充说明。`, false, undefined, "claude");
      log("orchestration.exhausted");
      return;
    }
    const revise = await laneTurn("codex", withIntervene(revisePrompt(review.text), "codex"), EXECUTOR_SYSTEM, "修订中", true);
    if (orchStopped()) return;
    if (!revise.ok) return;
  }
}

async function handleSend(text: string, target: AgentKind): Promise<void> {
  if (!projectCwd) {
    post("system", "error", "请先选择一个项目文件夹。", false, undefined, target);
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
    while (next) {
      const res =
        target === "claude"
          ? await laneTurn("claude", next, PLANNER_SYSTEM, "思考中", false)
          : await laneTurn("codex", next, EXECUTOR_SYSTEM, "执行中", true);
      if (!res.ok) break;
      next = intervene[target] || null; // a follow-up that was interjected mid-turn
      intervene[target] = "";
    }
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

/** Suggested model ids for a backend. DeepSeek is fetched live; CLIs use stable aliases. */
async function listModels(backend: Backend): Promise<string[]> {
  if (backend === "claude") return ["opus", "sonnet", "haiku"]; // CLI aliases resolve to latest
  if (backend === "codex") return []; // codex CLI has no list endpoint — free-text only
  const key = deepseekKey();
  const fallback = ["deepseek-chat", "deepseek-reasoner"];
  if (!key) return fallback;
  try {
    const res = await fetch("https://api.deepseek.com/models", { headers: { Authorization: `Bearer ${key}` } });
    if (!res.ok) return fallback;
    const data = (await res.json()) as { data?: { id?: string }[] };
    const ids = (data.data ?? []).map((d) => d.id).filter((x): x is string => !!x);
    log("models.list", { backend, n: ids.length });
    return ids.length ? ids.sort() : fallback;
  } catch (e) {
    log("models.list.error", { backend, err: String(e) });
    return fallback;
  }
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
