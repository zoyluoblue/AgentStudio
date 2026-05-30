import { contextBridge, ipcRenderer, type IpcRendererEvent } from "electron";
import { type AgentApi, CHANNELS, type EventView } from "../shared/ipc.js";

const api: AgentApi = {
  start: (input) => ipcRenderer.invoke(CHANNELS.start, input),
  status: (taskId) => ipcRenderer.invoke(CHANNELS.status, taskId),
  result: (taskId) => ipcRenderer.invoke(CHANNELS.result, taskId),
  getTask: (taskId) => ipcRenderer.invoke(CHANNELS.getTask, taskId),
  cancel: (taskId, signal) => ipcRenderer.invoke(CHANNELS.cancel, { taskId, signal }),
  list: (filter) => ipcRenderer.invoke(CHANNELS.list, filter),
  apply: (taskId) => ipcRenderer.invoke(CHANNELS.apply, taskId),
  resume: (input) => ipcRenderer.invoke(CHANNELS.resume, input),
  review: (input) => ipcRenderer.invoke(CHANNELS.review, input),
  executors: () => ipcRenderer.invoke(CHANNELS.executors),
  stats: () => ipcRenderer.invoke(CHANNELS.stats),
  getConfig: () => ipcRenderer.invoke(CHANNELS.getConfig),
  pickProject: () => ipcRenderer.invoke(CHANNELS.pickProject),
  getProject: () => ipcRenderer.invoke(CHANNELS.getProject),
  setProject: (cwd) => ipcRenderer.invoke(CHANNELS.setProject, cwd),
  onUpdate: (cb) => {
    const h = (_e: IpcRendererEvent, taskId: string) => cb(taskId);
    ipcRenderer.on(CHANNELS.evtUpdate, h);
    return () => ipcRenderer.off(CHANNELS.evtUpdate, h);
  },
  onActivity: (cb) => {
    const h = (_e: IpcRendererEvent, p: { taskId: string; event: EventView }) => cb(p.taskId, p.event);
    ipcRenderer.on(CHANNELS.evtActivity, h);
    return () => ipcRenderer.off(CHANNELS.evtActivity, h);
  },
};

contextBridge.exposeInMainWorld("agent", api);
