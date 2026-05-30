import type { Plan, PlanPhase, Verdict } from "../director/schemas.js";
import type { SandboxMode } from "../executor/types.js";

export type RunStatus =
  | "planning"
  | "awaiting_plan_approval"
  | "running"
  | "awaiting_phase_approval"
  | "paused"
  | "needs_human"
  | "done"
  | "failed"
  | "aborted";

export type PhaseStatus = "pending" | "executing" | "reviewing" | "revising" | "passed" | "failed" | "needs_human";

export type GateMode = "auto" | "manual_plan" | "manual_phase" | "manual_both";

export interface PhaseRun {
  phase: PlanPhase;
  status: PhaseStatus;
  iteration: number; // 0 = first execute; >0 = revise rounds
  executeTaskId?: string; // current/last codex task id
  taskIds: string[]; // all codex task ids across iterations
  lastSessionId?: string; // codex session to resume for revises
  lastVerdict?: Verdict;
  verdicts: Verdict[];
  startedAt?: number;
  finishedAt?: number;
  error?: string;
}

export interface RunOptions {
  gateMode: GateMode;
  maxReviseIters: number;
  executor: string; // codex
  sandbox: SandboxMode; // for execute/revise (workspace-write)
  plannerModel?: string;
  reviewerModel?: string;
  executorModel?: string;
}

export interface Run {
  runId: string;
  goal: string;
  cwd: string;
  status: RunStatus;
  plan?: Plan;
  planRaw?: string;
  planError?: string;
  phases: PhaseRun[];
  currentPhase: number;
  options: RunOptions;
  intervene?: string; // one-shot human instruction injected into the next execute
  createdAt: number;
  updatedAt: number;
  finishedAt?: number;
  error?: string;
}

export function isTerminalRun(s: RunStatus): boolean {
  return s === "done" || s === "failed" || s === "aborted";
}

export function newPhaseRun(phase: PlanPhase): PhaseRun {
  return { phase, status: "pending", iteration: 0, taskIds: [], verdicts: [] };
}
