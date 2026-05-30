# Configuration & Tool Reference

## Configuration

Precedence: **environment variable > config file > built-in default**.

Optional config file: `$AGENTCONNECTOR_CONFIG`, else `<cwd>/.agentconnector.json` (JSON
object with any of the keys below, camelCased, e.g. `{ "defaultSandbox": "read-only" }`).

| Env var | Default | Meaning |
|---|---|---|
| `AGENTCONNECTOR_DEFAULT_EXECUTOR` | `codex` | Backend used when a tool omits `executor`. |
| `AGENTCONNECTOR_DEFAULT_SANDBOX` | `workspace-write` | `read-only` \| `workspace-write` \| `danger-full-access`. |
| `AGENTCONNECTOR_ISOLATION` | `inplace` | `inplace` \| `worktree` default for tasks. |
| `AGENTCONNECTOR_MAX_CONCURRENT` | `4` | Max simultaneously running tasks; extra are queued. |
| `AGENTCONNECTOR_MAX_RETRIES` | `0` | Default auto-retry attempts on failure (backoff). |
| `AGENTCONNECTOR_MAX_DIFF_BYTES` | `200000` | Diff truncation budget (head+tail). |
| `AGENTCONNECTOR_MAX_EVENTS` | `500` | Per-task event ring-buffer size. |
| `AGENTCONNECTOR_MAX_STDERR_LINES` | `200` | Per-task stderr ring-buffer size. |
| `AGENTCONNECTOR_KILL_GRACE_MS` | `3000` | SIGTERM→SIGKILL escalation window on cancel. |
| `AGENTCONNECTOR_STATE_DIR` | `<cwd>/.agentconnector` | Where task snapshots are persisted. |
| `AGENTCONNECTOR_LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error`. |
| `AGENTCONNECTOR_LOG_JSON` | _(off)_ | `1`/`true` → structured JSON log lines (stderr). |
| `AGENTCONNECTOR_CODEX_BIN` | `codex` | Path/name of the Codex CLI. |
| `AGENTCONNECTOR_GEMINI_BIN` | `gemini` | Path/name of the Gemini CLI (experimental). |
| `AGENTCONNECTOR_GROK_BIN` | `grok` | Path/name of the Grok CLI (experimental). |

## Tools

All results are returned as pretty-printed JSON text with an `ok` boolean. Every
executor-targeting tool accepts an optional `executor` (default from config).

| Tool | Key inputs | Returns |
|---|---|---|
| `agent_start` | `prompt`, `cwd?`, `sandbox?`, `isolation?`, `model?`, `addDirs?`, `outputSchema?`, `retries?`, `label?` | `{ taskId, state, ... }` (async) |
| `agent_status` | `taskId?` (omit = summary + stats) | task status / `{ total, byState, queued, tasks[] }` |
| `agent_result` | `taskId`, `includeDiff?`, `includeEvents?`, `maxDiffBytes?` | `{ finalMessage, structuredOutput?, diff?, ... }` |
| `agent_cancel` | `taskId`, `signal?` | `{ state }` |
| `agent_list` | `state?`, `executor?` | `{ count, tasks[] }` |
| `agent_apply` | `taskId` | merges a worktree task's changes to the main tree |
| `agent_resume` | `prompt`, `taskId?` or `sessionId?`, `sandbox?`, `model?`, `cwd?` | `{ taskId, resumeOf }` (async) |
| `agent_review` | `instructions?`, `base?`, `uncommitted?`, `cwd?` | `{ taskId }` (read-only, structured findings) |
| `agent_executors` | — | registered backends + availability + capabilities |
| `agent_stats` | — | `{ total, queued, byState }` |
