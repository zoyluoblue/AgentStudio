import { join } from "node:path";
import { app, BrowserWindow, dialog, ipcMain, Notification } from "electron";
import { CHANNELS } from "../shared/ipc.js";
import { EngineService } from "./engineService.js";
import { fixPath } from "./fixPath.js";

// GUI apps don't inherit the shell PATH — repair it so codex/git/etc. resolve.
fixPath();

let engine: EngineService;
let win: BrowserWindow | null = null;
const lastState = new Map<string, string>();

function notifyTerminal(taskId: string): void {
  const v = engine.getTask(taskId);
  if (!v) return;
  const prev = lastState.get(taskId);
  lastState.set(taskId, v.state);
  if (!prev || prev === v.state) return;
  if (v.state === "done" || v.state === "error" || v.state === "canceled") {
    const title = v.state === "done" ? "任务完成" : v.state === "error" ? "任务失败" : "任务已取消";
    try {
      new Notification({ title, body: v.label || v.taskId }).show();
    } catch {
      /* notifications unavailable */
    }
  }
}

function createWindow(): void {
  win = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 1000,
    minHeight: 620,
    title: "AgentConnector",
    backgroundColor: "#15161a",
    webPreferences: {
      preload: join(__dirname, "../preload/index.js"),
      contextIsolation: true,
      sandbox: false,
    },
  });

  if (process.env.ELECTRON_RENDERER_URL) {
    void win.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void win.loadFile(join(__dirname, "../renderer/index.html"));
  }

  // Surface renderer/preload failures in the terminal (they're otherwise only in DevTools).
  win.webContents.on("did-finish-load", () => console.error("[main] renderer loaded OK"));
  win.webContents.on("preload-error", (_e, p, err) => console.error(`[preload-error] ${p}:`, err));
  win.webContents.on("did-fail-load", (_e, code, desc) => console.error(`[did-fail-load] ${code} ${desc}`));
  win.webContents.on("render-process-gone", (_e, d) => console.error("[render-gone]", d));
  (win.webContents as unknown as { on: (e: string, cb: (...a: unknown[]) => void) => void }).on(
    "console-message",
    (...a: unknown[]) => {
      const d = (a[1] && typeof a[1] === "object" ? a[1] : { level: a[1], message: a[2], lineNumber: a[3], sourceId: a[4] }) as {
        level: unknown;
        message: string;
        lineNumber: number;
        sourceId: string;
      };
      if (d.level === "error" || d.level === 3 || d.level === 2) {
        console.error(`[renderer] ${d.message} @ ${d.sourceId}:${d.lineNumber}`);
      }
    },
  );

  const off = engine.onChange((e) => {
    if (!win || win.isDestroyed()) return;
    if (e.type === "update") {
      win.webContents.send(CHANNELS.evtUpdate, e.taskId);
      notifyTerminal(e.taskId);
    } else {
      win.webContents.send(CHANNELS.evtActivity, {
        taskId: e.taskId,
        event: { kind: e.event.kind, text: e.event.text, ts: e.event.ts },
      });
    }
  });

  const offRun = engine.onRunChange((e) => {
    if (win && !win.isDestroyed()) win.webContents.send(CHANNELS.evtRun, e.runId);
  });

  win.on("closed", () => {
    off();
    offRun();
    win = null;
  });
}

function registerIpc(): void {
  ipcMain.handle(CHANNELS.start, (_e, input) => engine.start(input));
  ipcMain.handle(CHANNELS.status, (_e, taskId) => engine.status(taskId));
  ipcMain.handle(CHANNELS.result, (_e, taskId) => engine.result(taskId));
  ipcMain.handle(CHANNELS.getTask, (_e, taskId) => engine.getTask(taskId));
  ipcMain.handle(CHANNELS.cancel, (_e, { taskId, signal }) => engine.cancel(taskId, signal));
  ipcMain.handle(CHANNELS.list, (_e, filter) => engine.list(filter));
  ipcMain.handle(CHANNELS.apply, (_e, taskId) => engine.apply(taskId));
  ipcMain.handle(CHANNELS.resume, (_e, input) => engine.resume(input));
  ipcMain.handle(CHANNELS.review, (_e, input) => engine.review(input));
  ipcMain.handle(CHANNELS.executors, () => engine.executors());
  ipcMain.handle(CHANNELS.stats, () => engine.stats());
  ipcMain.handle(CHANNELS.getConfig, () => engine.getConfig());
  ipcMain.handle(CHANNELS.runStart, (_e, input) => engine.runStart(input));
  ipcMain.handle(CHANNELS.runGet, (_e, runId) => engine.runGet(runId));
  ipcMain.handle(CHANNELS.runList, () => engine.runList());
  ipcMain.handle(CHANNELS.runApprovePlan, (_e, runId) => engine.runApprovePlan(runId));
  ipcMain.handle(CHANNELS.runEditPlan, (_e, { runId, plan }) => engine.runEditPlan(runId, plan));
  ipcMain.handle(CHANNELS.runApprovePhase, (_e, runId) => engine.runApprovePhase(runId));
  ipcMain.handle(CHANNELS.runPause, (_e, runId) => engine.runPause(runId));
  ipcMain.handle(CHANNELS.runResume, (_e, runId) => engine.runResume(runId));
  ipcMain.handle(CHANNELS.runAbort, (_e, runId) => engine.runAbort(runId));
  ipcMain.handle(CHANNELS.runIntervene, (_e, { runId, instruction }) => engine.runIntervene(runId, instruction));
  ipcMain.handle(CHANNELS.getProject, () => engine.getProject());
  ipcMain.handle(CHANNELS.setProject, (_e, cwd) => engine.setProject(cwd));
  ipcMain.handle(CHANNELS.pickProject, async () => {
    const target = win ?? BrowserWindow.getAllWindows()[0];
    const r = target
      ? await dialog.showOpenDialog(target, { properties: ["openDirectory"] })
      : await dialog.showOpenDialog({ properties: ["openDirectory"] });
    if (r.canceled || !r.filePaths[0]) return null;
    return engine.setProject(r.filePaths[0]);
  });
}

app.whenReady().then(() => {
  if (!process.env.AGENTCONNECTOR_STATE_DIR) {
    process.env.AGENTCONNECTOR_STATE_DIR = join(app.getPath("userData"), "state");
  }
  engine = new EngineService();
  registerIpc();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => {
  void engine?.shutdown();
});
