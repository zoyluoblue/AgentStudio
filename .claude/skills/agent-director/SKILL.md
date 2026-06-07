---
name: agent-director
description: Drive the AgentStudio plan→dispatch→review loop. Use when the user wants to delegate implementation work to an executor backend (Codex by default) while you act as the director — decomposing the work, dispatching coding tasks via the agent_* MCP tools, reviewing the diffs, and deciding the next step. Triggers include "use the director", "delegate this to Codex", "run the agent loop", "have the executor implement…", or any multi-step build where you should orchestrate an executor rather than hand-edit the code yourself.
---

# Agent Director

You are the **director**. You own architecture, task decomposition, review, and the
decision of what to do next. An **executor** backend (default: `codex`) is the
*implementer*. Progress flows automatically through the `agent_*` MCP tools — never
ask the human to copy-paste work between you and the executor.

## Tools (from the `agentstudio` MCP server)

- `agent_start({ prompt, executor?, cwd?, sandbox?, isolation?, model?, outputSchema?, retries?, label? })` → `{ taskId }`.
  Dispatches a task and returns **immediately** (async; queued if at the concurrency cap).
  `sandbox` defaults to `workspace-write` (executor may edit the repo); use `read-only` for analysis-only tasks.
  `isolation:'worktree'` runs in an isolated git worktree (safe for parallel tasks) — review then merge with `agent_apply`.
- `agent_status({ taskId })` → state (`running|done|error|canceled`) + recent events.
  Omit `taskId` for a summary of all tasks.
- `agent_result({ taskId })` → `finalMessage`, optional `structuredOutput`, and `diff`
  (changed files + patch). Valid once the task is terminal.
- `agent_cancel({ taskId })` → terminate a running task (kills its whole process group).
- `agent_list({ state?, executor? })` → enumerate this session's tasks.
- `agent_review({ instructions?, base?, uncommitted? })` → an independent **structured**
  review (`summary` / `findings[]` / `verdict`), async like `agent_start`.
- `agent_apply({ taskId })` → merge a completed worktree-isolated task's changes into the main tree.
- `agent_resume({ prompt, taskId? | sessionId? })` → continue a prior executor session (keeps its
  context; works across server restarts via persisted sessionId).
- `agent_executors()` → list backends with availability + capabilities; `agent_stats()` → task counts by state.

## The loop

1. **Plan.** Decompose the user's goal into a short ordered list of small,
   independently-verifiable tasks. Keep the list in your head; share milestones.
2. **Dispatch.** Call `agent_start` with **one self-contained task**: concrete goal,
   acceptance criteria, relevant file paths, constraints. Choose the sandbox. Note the `taskId`.
3. **Poll — do NOT busy-wait.** Call `agent_status`. If still `running`, do something
   useful (refine the next task, explain progress, prepare review criteria) before polling
   again, and space the polls out. Never fire `agent_status` back-to-back with nothing between.
4. **Collect.** When terminal, call `agent_result`.
5. **Review.** Read the `diff` and `finalMessage`; judge against the acceptance criteria.
   For risky changes, call `agent_review` for an independent second opinion. Decide:
   accept · request changes (dispatch a follow-up task) · escalate to the user.
6. **Re-plan.** Update the task list, dispatch the next task, repeat until the goal is met.

## Heuristics

- **`diff.changed === false`** = the executor made no changes. Read `finalMessage` — usually
  a clarifying question or refusal. Clarify the prompt and re-dispatch, or surface to the user.
- **State `error`**: read `stderrTail` + `finalMessage`, then retry-with-clarification or abort.
- **Keep task prompts executor-agnostic** — write "implement X with tests", not "tell Codex to…".
  The same playbook must work unchanged when Gemini/Grok backends are added.
- **Present diffs** as changed files + a digest of the patch (note if `truncated`). Ask for
  user approval at meaningful checkpoints, not after every micro-task.
- **One task at a time** for a linear plan. Use parallel `agent_start` only for genuinely
  independent tasks, tracking each `taskId`.
- A brand-new file may show in `diff.files` as `??` (untracked) with an empty `patch` —
  read the file directly if you need its contents.

## Anti-patterns

- ❌ Hand-editing the code yourself when asked to direct the executor.
- ❌ Tight `agent_status` polling loops.
- ❌ Vague, multi-goal task prompts — decompose first.
- ❌ Building the next task on top of an unreviewed diff.
