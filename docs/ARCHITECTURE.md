# Architecture

AgentConnector is an **"agent router" MCP server**. Interactive Claude Code is the
**director** (architecture, task decomposition, review, deciding the next step); the
server routes each task to a pluggable **executor** backend that does the implementation.

```
Claude Code (director)
   │  executor-agnostic MCP tools:
   │  agent_start / agent_status / agent_result / agent_cancel / agent_list
   │  agent_apply / agent_resume / agent_review / agent_executors / agent_stats
   ▼
AgentConnector MCP server (stdio)
   ├─ server.ts        tool surface (zod input schemas; JSON-in-text results)
   ├─ tasks/TaskStore  in-memory Map + disk snapshots; lifecycle, queue, retry
   ├─ git/worktree     per-task isolation + apply-back
   ├─ diff/gitDiff     working-tree diff capture
   └─ executor/        Executor abstraction + registry
        ├─ cli/CliExecutor  generic spawn/track/cancel/stream by an adapter spec
        ├─ codex/           codexSpec  (wraps `codex exec` / `codex exec resume`)
        ├─ gemini/          geminiSpec (experimental; CLI not installed)
        └─ grok/            grokSpec   (experimental; CLI not installed)
              ▼ spawns
        Codex / Gemini / Grok CLI  (in repo dir or an isolated git worktree)
```

## Key ideas

- **Executor-agnostic tool surface.** Tools never import a concrete backend. Each tool
  takes an optional `executor` param (default from config). Adding a backend = one new
  `CliAdapterSpec` + one registry line; the tool surface and the director skill are untouched.

- **Async fire-and-poll.** `agent_start` spawns a detached child and returns a `taskId`
  immediately. The director polls `agent_status` and fetches `agent_result` when terminal.
  Long tasks never block the director's turn; tasks can run concurrently.

- **The `Executor` interface** (`src/executor/types.ts`): `start(StartArgs): RunHandle`,
  `capabilities`, `isAvailable()`. `RunHandle` exposes an event stream (`onEvent`), stderr,
  a `done` promise, `readFinalMessage()`, `kill(signal)`, and `cleanup()`.

- **Generic `CliExecutor`** does all process work (spawn with `detached:true` for a process
  group, stdin prompt delivery, stream parsing, cancel-by-group-kill, temp-file cleanup).
  A backend only supplies `buildArgv` + `createParser` + `capabilities`.

- **Normalized events.** Each backend's output stream is normalized to `NormalizedEvent`
  (`session_meta`/`assistant_text`/`tool_call`/`tool_result`/`token_usage`/`error`/…),
  always retaining the raw payload. Codex emits JSONL (`thread.started`, `item.*`,
  `turn.completed`); the parser is defensive and tolerates unknown kinds.

- **Task lifecycle.** `queued → running → done|error|canceled`. Coarse state follows the
  child's exit code (cancel takes precedence). The final message is read authoritatively
  from Codex's `-o` file, falling back to the last assistant event. A `git diff` is captured
  on completion.

- **Worktree isolation** (`isolation:"worktree"`). The task runs in a throwaway
  `git worktree` branched from HEAD, so its edits are isolated (enables safe parallel tasks).
  `agent_apply` merges a completed task's changes back into the main tree via `git apply`.

- **Persistence & recovery.** Task snapshots are written to `<stateDir>/tasks/<id>.json`
  (atomic tmp+rename). On startup they're reloaded; any non-terminal state is reconciled to
  `error` ("interrupted by server restart"). A recorded `sessionId` enables `agent_resume`
  across restarts.

- **Concurrency & retry.** Beyond `maxConcurrent`, tasks are `queued` and dispatched as slots
  free. `retries` re-launches failed tasks with exponential backoff.

- **Resume.** `agent_resume` continues a prior backend session (`codex exec resume <id>`).
  Note: Codex resume cannot take `-s`/`-C`/`--output-schema`; sandbox is passed via
  `-c sandbox_mode=...` and the working dir via the spawn cwd.

- **stdout is sacred.** It carries the MCP JSON-RPC frames; all logging goes to **stderr**.

## Phases

- **P1** vertical slice (tools + Codex + director skill).
- **P2** worktree isolation, persistence/recovery, resume, queue, retry.
- **P3** generic `CliExecutor`, Gemini/Grok adapters + availability detection.
- **P4** config file, leveled/JSON logging, metrics, docs, packaging.
