// Library entry: the engine API surface consumed by frontends (the Electron app,
// and any other host). The MCP server (src/server.ts) builds on the same modules.

export { loadConfig } from "./config.js";
export type { Config, Isolation } from "./config.js";

export { TaskStore } from "./tasks/taskStore.js";
export type { StoreEvent, LaunchOptions } from "./tasks/taskStore.js";
export type { TaskRecord } from "./tasks/taskTypes.js";
export { toTaskView } from "./tasks/taskView.js";
export type { TaskView, EventView } from "./tasks/taskView.js";

export { ensureBuiltins, getExecutor, listExecutors, executorsInfo } from "./executor/registry.js";
export type { ExecutorInfo } from "./executor/registry.js";
export type { Executor, StartArgs, SandboxMode, TaskState, NormalizedEvent } from "./executor/types.js";

export type { DiffResult, DiffFile } from "./diff/gitDiff.js";
export { log } from "./util/log.js";

// Director (planner / reviewer) primitives.
export { plan } from "./director/planner.js";
export type { PlanResult, PlannerOptions } from "./director/planner.js";
export { review } from "./director/reviewer.js";
export type { ReviewResult, ReviewerOptions } from "./director/reviewer.js";
export { runClaude, parseClaudeEnvelope } from "./director/claudeRunner.js";
export type { ClaudeRunOptions, ClaudeRunResult } from "./director/claudeRunner.js";
export { coercePlan, coerceVerdict, PLAN_SCHEMA, VERDICT_SCHEMA } from "./director/schemas.js";
export type { Plan, PlanPhase, Verdict, Finding, Severity } from "./director/schemas.js";

// Orchestrator (the plan -> execute -> review -> revise loop).
export { Orchestrator } from "./orchestrator/orchestrator.js";
export type { OrchestratorDeps, StartRunInput, PlannerFn, ReviewerFn } from "./orchestrator/orchestrator.js";
export { RunStore } from "./orchestrator/runStore.js";
export type { RunEvent } from "./orchestrator/runStore.js";
export type { Run, PhaseRun, RunStatus, PhaseStatus, GateMode, RunOptions } from "./orchestrator/runTypes.js";
