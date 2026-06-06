// Channel names + payload types shared across main / preload / renderer.

export type Role = "user" | "claude" | "codex" | "system";
export type MsgKind = "text" | "plan" | "diff" | "review" | "progress" | "error";
export type AgentKind = "claude" | "codex";
export type Mode = "solo" | "collab";

export interface ChatMessage {
  id: string;
  /** stable sequence number for referencing turns ("上一句是 #3") */
  n: number;
  role: Role;
  kind: MsgKind;
  text: string;
  ts: number;
  /** which conversation this belongs to: claude (left) or codex (right) */
  lane: AgentKind;
  /** still being produced (shows a thinking/working state) */
  pending?: boolean;
}

export interface ProjectInfo {
  cwd: string | null;
  name: string | null;
}

export interface AuthStatus {
  connected: boolean;
  /** e.g. account email or "ChatGPT" */
  detail?: string;
}

export interface AuthState {
  claude: AuthStatus;
  codex: AuthStatus;
}

export interface BusyState {
  claude: boolean;
  codex: boolean;
}

/** Live phase text per agent ("" = idle): e.g. 规划中 / 执行中 / 审查中 / 思考中 / 重连中 */
export interface ActivityState {
  claude: string;
  codex: string;
}

export const CH = {
  send: "chat:send",
  abort: "chat:abort",
  event: "chat:event",
  busy: "chat:busy",
  activity: "chat:activity",
  projectGet: "project:get",
  projectPick: "project:pick",
  projectEvent: "project:event",
  authGet: "auth:get",
  authConnect: "auth:connect",
  authEvent: "auth:event",
  modeGet: "mode:get",
  modeSet: "mode:set",
  modeEvent: "mode:event",
  modelSet: "model:set",
  previewGet: "preview:get",
  previewRefresh: "preview:refresh",
  logLine: "log:line",
} as const;

/** The surface exposed to the renderer as `window.studio`. */
export interface StudioApi {
  /** Send a message to one agent's conversation. */
  send(text: string, target: AgentKind): Promise<void>;
  abort(target: AgentKind): void;
  getMode(): Promise<Mode>;
  setMode(mode: Mode): void;
  onMode(cb: (m: Mode) => void): () => void;
  /** Set the model an agent should use ("" = the CLI default). */
  setModel(agent: AgentKind, model: string): void;
  /** Live preview: URL of the project's HTML entry, if any. */
  getPreview(): Promise<{ url: string | null }>;
  onPreviewRefresh(cb: (url: string | null) => void): () => void;
  onLog(cb: (line: string) => void): () => void;
  /** A new or updated message (upsert by id). */
  onEvent(cb: (m: ChatMessage) => void): () => void;
  onBusy(cb: (b: BusyState) => void): () => void;
  onActivity(cb: (a: ActivityState) => void): () => void;
  getProject(): Promise<ProjectInfo>;
  pickProject(): Promise<ProjectInfo>;
  onProject(cb: (p: ProjectInfo) => void): () => void;
  getAuth(): Promise<AuthState>;
  connect(kind: AgentKind): Promise<AuthStatus>;
  onAuth(cb: (s: AuthState) => void): () => void;
}
