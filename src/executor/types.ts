// Executor-agnostic core types. The MCP tool layer and task store depend ONLY
// on these abstractions — never on a concrete backend (Codex/Gemini/Grok).

export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";

export type TaskState = "queued" | "running" | "done" | "error" | "canceled";

export type NormalizedEventKind =
  | "session_meta" // carries a backend session/thread id (for resume)
  | "assistant_text" // a message from the agent to the user
  | "reasoning" // model reasoning/thinking
  | "tool_call" // the agent invoked a tool/command
  | "tool_result" // a tool/command produced output
  | "token_usage" // usage accounting (often the turn-end marker)
  | "result" // an explicit final-result event, if the backend emits one
  | "error" // an error surfaced by the backend
  | "unknown"; // anything we don't (yet) model — raw is always retained

/** A backend event, normalized to a shape the rest of the app understands. */
export interface NormalizedEvent {
  kind: NormalizedEventKind;
  /** The original parsed payload (or raw line for unparseable input). Always kept. */
  raw: unknown;
  /** Human-relevant text, when applicable (message text, command, output…). */
  text?: string;
  /** Backend session/thread id, present on session_meta events. */
  sessionId?: string;
  ts: number;
}

export interface ExecutorCapabilities {
  structuredOutput: boolean; // can force final output into a JSON schema
  jsonEvents: boolean; // emits a parseable event stream
  cancel: boolean; // can be killed mid-run
  resume: boolean; // can continue a prior session
  nativeReview: boolean; // has a first-class review mode
  sandboxModes: SandboxMode[];
}

export interface StartArgs {
  prompt: string;
  cwd: string;
  sandbox: SandboxMode;
  model?: string;
  addDirs?: string[];
  /** A JSON Schema object; when set, the backend forces its final answer to match. */
  outputSchema?: unknown;
  /** When set, continue a prior backend session instead of starting fresh. */
  resumeSessionId?: string;
}

export interface RunExit {
  exitCode: number | null;
  signal: NodeJS.Signals | null;
}

/** A live handle to one running backend invocation. */
export interface RunHandle {
  readonly pid: number | undefined;
  /** Subscribe to normalized events. Events emitted before subscription are replayed. */
  onEvent(cb: (e: NormalizedEvent) => void): void;
  /** Subscribe to stderr lines (diagnostics). Buffered lines are replayed. */
  onStderr(cb: (line: string) => void): void;
  /** Resolves when the process exits, for any reason. */
  readonly done: Promise<RunExit>;
  /** The authoritative final agent message (e.g. from an output file). "" if unavailable. */
  readFinalMessage(): Promise<string>;
  /** Send a signal to the whole process group (so child subprocesses die too). */
  kill(signal: NodeJS.Signals): void;
  /** Best-effort cleanup of any temp resources. Call after the result is captured. */
  cleanup(): void;
}

export interface Executor {
  readonly name: string;
  readonly capabilities: ExecutorCapabilities;
  /** True if the backend's CLI/binary is installed and usable. */
  isAvailable(): boolean;
  /** Marks backends wired but not yet verified (e.g. CLI not installed locally). */
  readonly experimental?: boolean;
  /** Spawn the backend and return a handle immediately (non-blocking). */
  start(args: StartArgs): RunHandle;
}
