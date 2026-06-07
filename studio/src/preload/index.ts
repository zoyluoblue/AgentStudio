import { type IpcRendererEvent, contextBridge, ipcRenderer } from "electron";
import {
  type ActivityState,
  type AgentKind,
  type AuthState,
  type BusyState,
  CH,
  type ChatMessage,
  type Mode,
  type ProjectInfo,
  type SessionLoad,
  type StudioApi,
} from "../shared/ipc.js";

const api: StudioApi = {
  send: (text, target) => ipcRenderer.invoke(CH.send, { text, target }),
  abort: (target) => ipcRenderer.send(CH.abort, target),
  getMode: () => ipcRenderer.invoke(CH.modeGet),
  setMode: (m) => ipcRenderer.send(CH.modeSet, m),
  onMode: (cb) => {
    const h = (_e: IpcRendererEvent, m: Mode) => cb(m);
    ipcRenderer.on(CH.modeEvent, h);
    return () => ipcRenderer.off(CH.modeEvent, h);
  },
  setModel: (agent, model) => ipcRenderer.send(CH.modelSet, { agent, model }),
  getPreview: () => ipcRenderer.invoke(CH.previewGet),
  onPreviewRefresh: (cb) => {
    const h = (_e: IpcRendererEvent, u: string | null) => cb(u);
    ipcRenderer.on(CH.previewRefresh, h);
    return () => ipcRenderer.off(CH.previewRefresh, h);
  },
  onLog: (cb) => {
    const h = (_e: IpcRendererEvent, line: string) => cb(line);
    ipcRenderer.on(CH.logLine, h);
    return () => ipcRenderer.off(CH.logLine, h);
  },
  onEvent: (cb) => {
    const h = (_e: IpcRendererEvent, m: ChatMessage) => cb(m);
    ipcRenderer.on(CH.event, h);
    return () => ipcRenderer.off(CH.event, h);
  },
  onBusy: (cb) => {
    const h = (_e: IpcRendererEvent, b: BusyState) => cb(b);
    ipcRenderer.on(CH.busy, h);
    return () => ipcRenderer.off(CH.busy, h);
  },
  onActivity: (cb) => {
    const h = (_e: IpcRendererEvent, a: ActivityState) => cb(a);
    ipcRenderer.on(CH.activity, h);
    return () => ipcRenderer.off(CH.activity, h);
  },
  getProject: () => ipcRenderer.invoke(CH.projectGet),
  pickProject: () => ipcRenderer.invoke(CH.projectPick),
  onProject: (cb) => {
    const h = (_e: IpcRendererEvent, p: ProjectInfo) => cb(p);
    ipcRenderer.on(CH.projectEvent, h);
    return () => ipcRenderer.off(CH.projectEvent, h);
  },
  getAuth: () => ipcRenderer.invoke(CH.authGet),
  connect: (kind: AgentKind) => ipcRenderer.invoke(CH.authConnect, kind),
  disconnect: (kind: AgentKind) => ipcRenderer.invoke(CH.authDisconnect, kind),
  onAuth: (cb) => {
    const h = (_e: IpcRendererEvent, s: AuthState) => cb(s);
    ipcRenderer.on(CH.authEvent, h);
    return () => ipcRenderer.off(CH.authEvent, h);
  },
  listHistory: () => ipcRenderer.invoke(CH.historyList),
  getSession: (id) => ipcRenderer.invoke(CH.historyGet, id),
  resumeSession: (id, focusMessageId) => ipcRenderer.invoke(CH.historyResume, { id, focusMessageId }),
  deleteSession: (id) => ipcRenderer.invoke(CH.historyDelete, id),
  renameSession: (id, title) => ipcRenderer.invoke(CH.historyRename, { id, title }),
  search: (query) => ipcRenderer.invoke(CH.searchQuery, query),
  onSessionLoad: (cb) => {
    const h = (_e: IpcRendererEvent, p: SessionLoad) => cb(p);
    ipcRenderer.on(CH.sessionLoad, h);
    return () => ipcRenderer.off(CH.sessionLoad, h);
  },
  getSettings: () => ipcRenderer.invoke(CH.settingsGet),
  setSettings: (patch) => ipcRenderer.invoke(CH.settingsSet, patch),
  listModels: (backend) => ipcRenderer.invoke(CH.modelsList, backend),
  getMemory: (scope, kind) => ipcRenderer.invoke(CH.memoryGet, { scope, kind }),
  setMemory: (scope, content, kind) => ipcRenderer.invoke(CH.memorySet, { scope, content, kind }),
  consolidateMemory: (scope) => ipcRenderer.invoke(CH.memoryConsolidate, scope),
};

contextBridge.exposeInMainWorld("studio", api);
