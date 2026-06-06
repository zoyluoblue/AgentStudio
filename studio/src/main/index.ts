import { existsSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, join } from "node:path";
import { BrowserWindow, app, dialog, ipcMain } from "electron";
import {
  type AgentKind,
  type AuthState,
  type AuthStatus,
  type BusyState,
  CH,
  type ChatMessage,
  type Mode,
  type MsgKind,
  type ProjectInfo,
  type Role,
} from "../shared/ipc.js";
import { agentLogin, agentStatus } from "./auth.js";
import { askClaude } from "./claudeDriver.js";
import { askCodex } from "./codexDriver.js";
import { changesSince, snapshot } from "./diff.js";
import { fixPath } from "./fixPath.js";
import { log, setLogFile, setLogSink } from "./log.js";

// GUI apps don't inherit the shell PATH — repair it so claude/codex/git resolve.
fixPath();

const MAX_REVISE = 3;

let win: BrowserWindow | null = null;
let projectCwd: string | null = null;
let mode: Mode = process.env.STUDIO_MODE === "collab" ? "collab" : "solo";
let claudeSession: string | undefined;
let codexThread: string | undefined;
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
  "你是 AgentConnector 的规划助手，面向不懂编程的用户。用简洁、友好的中文交流，避免专业黑话。" +
  "把用户想做的东西拆成简短的分步实现计划（3 步以内），供 Codex 执行。只输出计划本身，不要写代码。";
const REVIEWER_SYSTEM =
  "你是严谨的代码审查员。基于用户目标和 Codex 刚做的改动（含文件内容），判断是否达成目标且没有明显问题。用简洁中文。";

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
function setBusy(kind: AgentKind, v: boolean): void {
  busy[kind] = v;
  send(CH.busy, { ...busy });
}

// ---- messages (with a stable sequence number per id for referencing turns) ----
let msgSeq = 0;
const msgN = new Map<string, number>();
function post(role: Role, kind: MsgKind, text: string, pending: boolean, id: string | undefined, lane: AgentKind): string {
  const mid = id ?? `m${Date.now().toString(36)}_${msgSeq}`;
  let n = msgN.get(mid);
  if (n === undefined) {
    n = ++msgSeq;
    msgN.set(mid, n);
  }
  send(CH.event, { id: mid, n, role, kind, text, ts: Date.now(), lane, pending } satisfies ChatMessage);
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
  claudeSession = undefined;
  codexThread = undefined;
  log("project.set", { cwd: resolved });
  send(CH.projectEvent, projInfo());
}

// ---- single agent turns (post to a lane + return the result) ----
async function claudeTurn(prompt: string, system: string) {
  const pid = post("claude", "text", "", true, undefined, "claude");
  setBusy("claude", true);
  aborts.claude = new AbortController();
  log("claude.turn.start", { model: agentModel.claude || "default", promptLen: prompt.length, cwd: projectCwd });
  const res = await askClaude({
    prompt,
    cwd: projectCwd as string,
    sessionId: claudeSession,
    systemPrompt: system,
    disableTools: true,
    model: agentModel.claude || undefined,
    signal: aborts.claude.signal,
  });
  log("claude.turn.done", { ok: res.ok, len: res.text.length, err: res.error });
  if (res.sessionId) claudeSession = res.sessionId;
  post(res.ok ? "claude" : "system", res.ok ? "text" : "error", res.ok ? res.text : (res.error ?? "出错了"), false, pid, "claude");
  setBusy("claude", false);
  aborts.claude = null;
  return res;
}
async function codexTurn(prompt: string) {
  const pid = post("codex", "progress", "Codex 正在处理…", true, undefined, "codex");
  setBusy("codex", true);
  aborts.codex = new AbortController();
  log("codex.turn.start", { model: agentModel.codex || "default", promptLen: prompt.length, cwd: projectCwd });
  const res = await askCodex({
    prompt,
    cwd: projectCwd as string,
    threadId: codexThread,
    sandbox: "workspace-write",
    model: agentModel.codex || undefined,
    signal: aborts.codex.signal,
    onDelta: (t) => post("codex", "text", t, true, pid, "codex"),
  });
  log("codex.turn.done", { ok: res.ok, len: res.text.length, steps: res.steps, err: res.error });
  if (res.threadId) codexThread = res.threadId;
  const suffix = res.ok && res.steps ? `\n\n（执行了 ${res.steps} 步操作）` : "";
  post(res.ok ? "codex" : "system", res.ok ? "text" : "error", res.ok ? res.text + suffix : (res.error ?? "出错了"), false, pid, "codex");
  setBusy("codex", false);
  aborts.codex = null;
  send(CH.previewRefresh, previewUrl()); // codex may have changed files -> refresh the live preview
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

  const plan = await claudeTurn(withIntervene(planPrompt(goal), "claude"), PLANNER_SYSTEM);
  if (orchStopped()) return;
  if (!plan.ok) return;

  const before = snapshot(projectCwd as string);
  const exec = await codexTurn(withIntervene(executePrompt(plan.text), "codex"));
  if (orchStopped()) return;
  if (!exec.ok) return;

  for (let iter = 0; iter < MAX_REVISE; iter++) {
    const diff = changesSince(before, projectCwd as string);
    log("orchestration.review", { iter, diffLen: diff.length });
    const review = await claudeTurn(withIntervene(reviewPrompt(goal, diff), "claude"), REVIEWER_SYSTEM);
    if (orchStopped()) return;
    if (!review.ok) return;
    if (verdictPass(review.text)) {
      post("system", "text", "✅ 完成：Claude 审查通过。", false, undefined, "claude");
      log("orchestration.done", { iter });
      return;
    }
    if (iter === MAX_REVISE - 1) {
      post("system", "text", `已自动修改 ${MAX_REVISE} 轮仍未通过，请人工查看或补充说明。`, false, undefined, "claude");
      log("orchestration.exhausted");
      return;
    }
    const revise = await codexTurn(withIntervene(revisePrompt(review.text), "codex"));
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
      const res = target === "claude" ? await claudeTurn(next, PLANNER_SYSTEM) : await codexTurn(next);
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
    width: 1440,
    height: 920,
    minWidth: 1040,
    minHeight: 640,
    title: "AgentConnector",
    backgroundColor: "#0e0f13",
    webPreferences: { preload: join(__dirname, "../preload/index.js"), contextIsolation: true, sandbox: false, webviewTag: true },
  });

  if (process.env.ELECTRON_RENDERER_URL) void win.loadURL(process.env.ELECTRON_RENDERER_URL);
  else void win.loadFile(join(__dirname, "../renderer/index.html"));

  win.webContents.on("did-finish-load", () => console.error("[main] renderer loaded OK"));
  win.webContents.on("preload-error", (_e, p, err) => console.error(`[preload-error] ${p}:`, err));
  win.webContents.on("did-fail-load", (_e, code, desc) => console.error(`[did-fail-load] ${code} ${desc}`));

  // Dev affordances.
  const shotPath = process.env.STUDIO_SHOT;
  const demo = process.env.STUDIO_DEMO;
  win.webContents.on("did-finish-load", () => {
    if (demo) {
      const demoDir = process.env.STUDIO_DEMO_DIR || join(tmpdir(), "agentconnector-demo");
      try {
        mkdirSync(demoDir, { recursive: true });
      } catch {
        /* ignore */
      }
      setProject(demoDir);
      void handleSend(demo, "claude").then(async () => {
        const cd = process.env.STUDIO_DEMO_CODEX;
        if (cd && mode === "solo") await handleSend(cd, "codex");
        if (shotPath) setTimeout(() => capture(shotPath), 3500);
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
  setLogFile(join(app.getPath("userData"), "logs", "agentconnector.log"));
  setLogSink((line) => send(CH.logLine, line));
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

  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
