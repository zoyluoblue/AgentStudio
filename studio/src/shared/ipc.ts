// Channel names + payload types shared across main / preload / renderer.

export type Role = "user" | "claude" | "codex" | "system";
export type MsgKind = "text" | "plan" | "diff" | "review" | "progress" | "error";
/** Left lane (master/planner) is keyed "claude", right lane (slave/executor) is keyed "codex". */
export type AgentKind = "claude" | "codex";
/** The two lane roles, surfaced to the user and used for proxy scoping. */
export type Lane = "master" | "slave";
/** Which LLM actually runs in a lane. DeepSeek is master-only (text planning, no file writes). */
export type Backend = "claude" | "codex" | "deepseek";
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
  /** display name of the backend that produced it (e.g. "Claude", "Codex", "DeepSeek") */
  agentName?: string;
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

/** Saved-conversation metadata used for history lists and search rows. */
export interface SessionMeta {
  id: string;
  projectCwd: string;
  projectName: string;
  mode: Mode;
  /** auto-derived from the first user message, user-editable */
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
}

/** A full saved conversation: metadata + transcript + agent resume ids. */
export interface Session extends SessionMeta {
  messages: ChatMessage[];
  /** claude --resume id, so "继续" restores Claude's context */
  claudeSession?: string;
  /** codex resume thread id, so "继续" restores Codex's context */
  codexThread?: string;
}

/** One search match inside a saved session. */
export interface SearchHit {
  sessionId: string;
  sessionTitle: string;
  projectName: string;
  messageId: string;
  n: number;
  role: Role;
  lane: AgentKind;
  ts: number;
  /** text around the match, trimmed for display */
  snippet: string;
}

export type ProxyMode = "system" | "custom" | "none";
/** Which lanes the proxy applies to. */
export type ProxyScope = "master" | "slave" | "both";
export type ThemeMode = "system" | "light" | "dark";
/** How a backend authenticates: app = CLI / OAuth login, key = API key. */
export type ConnectMethod = "app" | "key";

/** A selectable model: `id` is passed to the CLI/API; `label` is the friendly display name. */
export interface ModelOption {
  id: string;
  label: string;
}

/** Long-term memory scope: global (all projects) or the current project only. */
export type MemoryScope = "global" | "project";
/** Memory kind: curated (user-written / explicit "记住") or learned (auto-extracted from chats). */
export type MemoryKind = "curated" | "learned";

/** User preferences, persisted to userData/settings.json. */
export interface AppSettings {
  /** system = inherit env proxy; custom = use proxyUrl; none = no proxy */
  proxyMode: ProxyMode;
  /** e.g. http://127.0.0.1:7890 — used when proxyMode === "custom" */
  proxyUrl: string;
  /** master = left only, slave = right only, both = all */
  proxyScope: ProxyScope;
  theme: ThemeMode;
  /** LLM running in the left (master/planner) lane */
  masterBackend: Backend;
  /** LLM running in the right (slave/executor) lane */
  slaveBackend: Backend;
  /** Per-backend auth method. DeepSeek is always "key" (no CLI login). */
  connectMethod: Record<Backend, ConnectMethod>;
  /** Per-backend API key: claude→ANTHROPIC_API_KEY, codex→OPENAI_API_KEY, deepseek→DeepSeek key */
  apiKeys: Record<Backend, string>;
  /** Auto-extract learned memory from finished conversations (Codex/CC-style). */
  autoMemory: boolean;
}

/** Payload pushed to the renderer when a saved session is resumed into the live chat. */
export interface SessionLoad {
  project: ProjectInfo;
  mode: Mode;
  messages: ChatMessage[];
  /** message to scroll to + briefly highlight (e.g. a search hit) */
  focusMessageId?: string;
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
  authDisconnect: "auth:disconnect",
  authEvent: "auth:event",
  modeGet: "mode:get",
  modeSet: "mode:set",
  modeEvent: "mode:event",
  modelSet: "model:set",
  previewGet: "preview:get",
  previewRefresh: "preview:refresh",
  logLine: "log:line",
  historyList: "history:list",
  historyGet: "history:get",
  historyResume: "history:resume",
  historyDelete: "history:delete",
  historyRename: "history:rename",
  searchQuery: "search:query",
  sessionLoad: "session:load",
  settingsGet: "settings:get",
  settingsSet: "settings:set",
  modelsList: "models:list",
  memoryGet: "memory:get",
  memorySet: "memory:set",
  memoryConsolidate: "memory:consolidate",
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
  /** Forget an app-login connection inside the app (does NOT log the CLI out globally). */
  disconnect(kind: AgentKind): Promise<void>;
  onAuth(cb: (s: AuthState) => void): () => void;
  // ---- history & search ----
  /** All saved conversations, newest first. */
  listHistory(): Promise<SessionMeta[]>;
  /** Full transcript of one saved conversation (read-only view). */
  getSession(id: string): Promise<Session | null>;
  /** Load a saved conversation into the live chat and restore agent context. */
  resumeSession(id: string, focusMessageId?: string): Promise<void>;
  deleteSession(id: string): Promise<void>;
  renameSession(id: string, title: string): Promise<void>;
  /** Full-text search across every saved conversation. */
  search(query: string): Promise<SearchHit[]>;
  onSessionLoad(cb: (p: SessionLoad) => void): () => void;
  // ---- settings ----
  getSettings(): Promise<AppSettings>;
  /** Merge a partial update, persist, and return the full settings. */
  setSettings(patch: Partial<AppSettings>): Promise<AppSettings>;
  /** Selectable models for a backend (Codex from its local cache, DeepSeek/Anthropic fetched live, Claude curated). */
  listModels(backend: Backend): Promise<ModelOption[]>;
  // ---- memory ----
  /** Read long-term memory for a scope+kind (project scope returns "" when no project is open). */
  getMemory(scope: MemoryScope, kind?: MemoryKind): Promise<string>;
  /** Replace long-term memory for a scope+kind. */
  setMemory(scope: MemoryScope, content: string, kind?: MemoryKind): Promise<void>;
  /** Dedup/compress the learned memory of a scope (returns the consolidated text). */
  consolidateMemory(scope: MemoryScope): Promise<string>;
}
