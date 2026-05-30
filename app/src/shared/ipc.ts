// The IPC contract shared by main, preload, and renderer.
// Types are declared locally (mirroring the engine) so the renderer/preload
// never import Node engine code — only the main process talks to @engine.

export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type Isolation = "inplace" | "worktree";
export type TaskState = "queued" | "running" | "done" | "error" | "canceled";

export interface DiffFile {
  path: string;
  status: string;
}
export interface DiffResult {
  changed: boolean;
  files: DiffFile[];
  patch: string;
  truncated: boolean;
  totalBytes: number;
}
export interface EventView {
  kind: string;
  text?: string;
  ts: number;
}
export interface ExecutorCapabilities {
  structuredOutput: boolean;
  jsonEvents: boolean;
  cancel: boolean;
  resume: boolean;
  nativeReview: boolean;
  sandboxModes: SandboxMode[];
}
export interface ExecutorInfo {
  name: string;
  available: boolean;
  experimental: boolean;
  capabilities: ExecutorCapabilities;
}

export interface TaskView {
  taskId: string;
  label?: string;
  executor: string;
  state: TaskState;
  cwd: string;
  sandbox: SandboxMode;
  isolation: Isolation;
  model?: string;
  pid?: number;
  startedAt: number;
  finishedAt?: number;
  durationMs: number;
  exitCode?: number | null;
  attempt: number;
  maxRetries: number;
  sessionId?: string;
  resumeOfSessionId?: string;
  lastEventKind?: string;
  eventCount: number;
  recentEvents: EventView[];
  finalMessage?: string;
  structuredOutput?: unknown;
  structuredParseError?: string;
  diff?: DiffResult;
  stderrTail: string[];
  worktreePath?: string;
  appliedAt?: number;
  error?: string;
  hasResult: boolean;
  hasDiff: boolean;
}

export interface StartInput {
  prompt: string;
  executor?: string;
  cwd?: string;
  sandbox?: SandboxMode;
  isolation?: Isolation;
  model?: string;
  retries?: number;
  label?: string;
}
export interface ResumeInput {
  prompt: string;
  taskId?: string;
  sessionId?: string;
  executor?: string;
  sandbox?: SandboxMode;
  model?: string;
  cwd?: string;
}
export interface ReviewInput {
  instructions?: string;
  executor?: string;
  base?: string;
  uncommitted?: boolean;
  cwd?: string;
}
export interface ProjectInfo {
  cwd: string;
  isRepo: boolean;
  branch?: string;
  dirty?: number;
}
export interface StartResult {
  ok: boolean;
  taskId?: string;
  view?: TaskView;
  resumeOf?: string;
  error?: string;
}
export interface ApplyResult {
  ok: boolean;
  applied?: boolean;
  reason?: string;
  view?: TaskView;
  error?: string;
}
export interface Stats {
  total: number;
  queued: number;
  byState: Record<string, number>;
}
export interface StatusSummary extends Stats {
  tasks: TaskView[];
}

export interface ConfigView {
  defaultExecutor: string;
  defaultSandbox: SandboxMode;
  defaultIsolation: Isolation;
  maxConcurrent: number;
  maxRetries: number;
  maxDiffBytes: number;
  stateDir: string;
  logLevel: string;
}

export interface AgentApi {
  start(input: StartInput): Promise<StartResult>;
  status(taskId?: string): Promise<TaskView | StatusSummary | null>;
  result(taskId: string): Promise<TaskView | null>;
  getTask(taskId: string): Promise<TaskView | null>;
  cancel(taskId: string, signal?: "SIGTERM" | "SIGKILL"): Promise<{ ok: boolean; view?: TaskView; error?: string }>;
  list(filter?: { state?: string; executor?: string }): Promise<TaskView[]>;
  apply(taskId: string): Promise<ApplyResult>;
  resume(input: ResumeInput): Promise<StartResult>;
  review(input: ReviewInput): Promise<StartResult>;
  executors(): Promise<{ default: string; executors: ExecutorInfo[] }>;
  stats(): Promise<Stats>;
  getConfig(): Promise<ConfigView>;
  pickProject(): Promise<ProjectInfo | null>;
  getProject(): Promise<ProjectInfo>;
  setProject(cwd: string): Promise<ProjectInfo>;
  onUpdate(cb: (taskId: string) => void): () => void;
  onActivity(cb: (taskId: string, event: EventView) => void): () => void;
}

export const CHANNELS = {
  start: "agent:start",
  status: "agent:status",
  result: "agent:result",
  getTask: "agent:getTask",
  cancel: "agent:cancel",
  list: "agent:list",
  apply: "agent:apply",
  resume: "agent:resume",
  review: "agent:review",
  executors: "agent:executors",
  stats: "agent:stats",
  getConfig: "agent:getConfig",
  pickProject: "agent:pickProject",
  getProject: "agent:getProject",
  setProject: "agent:setProject",
  evtUpdate: "agent:update",
  evtActivity: "agent:activity",
} as const;
