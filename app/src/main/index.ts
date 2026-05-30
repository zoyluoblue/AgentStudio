import { join } from "node:path";
import { app, BrowserWindow, dialog, ipcMain, Notification } from "electron";
import { CHANNELS } from "../shared/ipc.js";
import { EngineService } from "./engineService.js";

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

  win.on("closed", () => {
    off();
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
