import { randomUUID } from "node:crypto";
import type { Config } from "../config.js";
import type { PlanResult } from "../director/planner.js";
import type { ReviewResult } from "../director/reviewer.js";
import type { Plan, PlanPhase } from "../director/schemas.js";
import type { Executor, SandboxMode, StartArgs } from "../executor/types.js";
import type { TaskStore } from "../tasks/taskStore.js";
import { log } from "../util/log.js";
import { buildExecutePrompt, buildRevisePrompt } from "./prompts.js";
import type { RunStore } from "./runStore.js";
import { type GateMode, type Run, isTerminalRun, newPhaseRun } from "./runTypes.js";

export type PlannerFn = (goal: string, opts: { cwd: string; model?: string; signal?: AbortSignal }) => Promise<PlanResult>;
export type ReviewerFn = (
  phase: PlanPhase,
  diff: string,
  opts: { cwd: string; model?: string; signal?: AbortSignal },
) => Promise<ReviewResult>;

export interface OrchestratorDeps {
  runStore: RunStore;
  taskStore: TaskStore;
  getExecutor: (name: string | undefined, fallback: string) => Executor;
  planner: PlannerFn;
  reviewer: ReviewerFn;
  cfg: Config;
}

export interface StartRunInput {
  goal: string;
  cwd: string;
  gateMode?: GateMode;
  maxReviseIters?: number;
  executor?: string;
  sandbox?: SandboxMode;
  plannerModel?: string;
  reviewerModel?: string;
  executorModel?: string;
}

/** Drives the plan -> execute -> review -> revise loop for a Run. */
export class Orchestrator {
  private readonly driving = new Set<string>();
  private readonly aborts = new Map<string, AbortController>();

  constructor(private readonly deps: OrchestratorDeps) {}

  startRun(input: StartRunInput): Run {
    const now = Date.now();
    const run: Run = {
      runId: "run_" + randomUUID().slice(0, 8),
      goal: input.goal,
      cwd: input.cwd,
      status: "planning",
      phases: [],
      currentPhase: 0,
      options: {
        gateMode: input.gateMode ?? "auto",
        maxReviseIters: input.maxReviseIters ?? 3,
        executor: input.executor ?? this.deps.cfg.defaultExecutor,
        sandbox: input.sandbox ?? "workspace-write",
        plannerModel: input.plannerModel,
        reviewerModel: input.reviewerModel,
        executorModel: input.executorModel,
      },
      createdAt: now,
      updatedAt: now,
    };
    this.deps.runStore.create(run);
    this.drive(run.runId);
    return run;
  }

  // ---- controls ----
  approvePlan(runId: string): void {
    const run = this.deps.runStore.get(runId);
    if (!run || run.status !== "awaiting_plan_approval") return;
    run.status = "running";
    this.deps.runStore.save(run);
    this.drive(runId);
  }

  editPlan(runId: string, plan: Plan): void {
    const run = this.deps.runStore.get(runId);
    if (!run) return;
    if (run.status !== "awaiting_plan_approval" && run.status !== "planning" && run.status !== "paused") return;
    run.plan = plan;
    run.phases = plan.phases.map(newPhaseRun);
    run.currentPhase = 0;
    this.deps.runStore.save(run);
  }

  approvePhase(runId: string): void {
    const run = this.deps.runStore.get(runId);
    if (!run || run.status !== "awaiting_phase_approval") return;
    run.status = "running";
    this.deps.runStore.save(run);
    this.drive(runId);
  }

  pause(runId: string): void {
    const run = this.deps.runStore.get(runId);
    if (!run || isTerminalRun(run.status)) return;
    run.status = "paused";
    this.deps.runStore.save(run);
  }

  resume(runId: string): void {
    const run = this.deps.runStore.get(runId);
    if (!run || isTerminalRun(run.status)) return;
    if (run.status === "paused" || run.status === "needs_human") {
      run.status = run.plan ? "running" : "planning";
      this.deps.runStore.save(run);
      this.drive(runId);
    }
  }

  async abort(runId: string): Promise<void> {
    const run = this.deps.runStore.get(runId);
    if (!run || isTerminalRun(run.status)) return;
    this.aborts.get(runId)?.abort();
    const pr = run.phases[run.currentPhase];
    const tid = pr?.executeTaskId;
    if (tid) {
      const t = this.deps.taskStore.get(tid);
      if (t) {
        try {
          await this.deps.taskStore.cancel(t, "SIGTERM");
        } catch {
          /* ignore */
        }
      }
    }
    run.status = "aborted";
    run.finishedAt = Date.now();
    this.deps.runStore.save(run);
  }

  intervene(runId: string, instruction: string): void {
    const run = this.deps.runStore.get(runId);
    if (!run) return;
    run.intervene = instruction;
    this.deps.runStore.save(run);
  }

  // ---- driver ----
  private drive(runId: string): void {
    if (this.driving.has(runId)) return;
    this.driving.add(runId);
    if (!this.aborts.has(runId)) this.aborts.set(runId, new AbortController());
    void this.loop(runId)
      .catch((e) => log.error(`run ${runId} loop error`, String(e)))
      .finally(() => this.driving.delete(runId));
  }

  private async loop(runId: string): Promise<void> {
    const store = this.deps.runStore;
    const signal = this.aborts.get(runId)?.signal;
    const stopped = () => {
      const r = store.get(runId);
      return !r || r.status === "paused" || r.status === "aborted";
    };

    let run = store.get(runId);
    if (!run) return;

    // 1. Plan
    if (!run.plan) {
      run.status = "planning";
      store.save(run);
      const pr = await this.deps.planner(run.goal, { cwd: run.cwd, model: run.options.plannerModel, signal });
      run = store.get(runId);
      if (!run || run.status === "aborted") return;
      if (!pr.ok || !pr.plan) {
        run.status = "failed";
        run.planError = pr.error;
        run.error = pr.error;
        store.save(run);
        return;
      }
      run.plan = pr.plan;
      run.planRaw = pr.raw;
      run.phases = pr.plan.phases.map(newPhaseRun);
      store.save(run);
      if (run.options.gateMode === "manual_plan" || run.options.gateMode === "manual_both") {
        run.status = "awaiting_plan_approval";
        store.save(run);
        return;
      }
    }

    // 2. Phases
    while (true) {
      run = store.get(runId);
      if (!run || stopped()) return;
      if (run.currentPhase >= run.phases.length) {
        run.status = "done";
        run.finishedAt = Date.now();
        store.save(run);
        return;
      }
      run.status = "running";
      store.save(run);

      const ok = await this.runPhase(runId, run.currentPhase);
      run = store.get(runId);
      if (!run || !ok) return; // status was set inside (needs_human / aborted / paused)

      run.intervene = undefined; // consume any one-shot instruction
      const last = run.currentPhase >= run.phases.length - 1;
      const gatePhase = run.options.gateMode === "manual_phase" || run.options.gateMode === "manual_both";
      run.currentPhase++;
      if (gatePhase && !last) {
        run.status = "awaiting_phase_approval";
        store.save(run);
        return;
      }
      store.save(run);
    }
  }

  private async runPhase(runId: string, idx: number): Promise<boolean> {
    const store = this.deps.runStore;
    const ts = this.deps.taskStore;
    const signal = this.aborts.get(runId)?.signal;

    while (true) {
      let run = store.get(runId);
      if (!run || run.status === "aborted" || run.status === "paused") return false;
      let pr = run.phases[idx];
      if (!pr) return false;

      pr.startedAt ??= Date.now();
      const isRevise = pr.iteration > 0;
      pr.status = isRevise ? "revising" : "executing";
      store.save(run);

      let executor: Executor;
      try {
        executor = this.deps.getExecutor(run.options.executor, this.deps.cfg.defaultExecutor);
      } catch (e) {
        pr.status = "needs_human";
        pr.error = String(e);
        run.status = "needs_human";
        store.save(run);
        return false;
      }

      const startArgs: StartArgs = {
        prompt: isRevise ? buildRevisePrompt(run, pr) : buildExecutePrompt(run, pr, idx),
        cwd: run.cwd,
        sandbox: run.options.sandbox,
        model: run.options.executorModel,
        resumeSessionId: isRevise ? pr.lastSessionId : undefined,
      };
      const task = await ts.start(executor, startArgs, { label: `${pr.phase.title} #${pr.iteration}`, isolation: "inplace" });
      run = store.get(runId);
      if (!run) return false;
      pr = run.phases[idx];
      if (!pr) return false;
      pr.executeTaskId = task.taskId;
      pr.taskIds.push(task.taskId);
      store.save(run);

      await ts.settled(task.taskId);
      if (signal?.aborted) return false;
      run = store.get(runId);
      if (!run || run.status === "aborted") return false;
      pr = run.phases[idx];
      if (!pr) return false;

      const taskRec = ts.get(task.taskId);
      if (taskRec?.sessionId) pr.lastSessionId = taskRec.sessionId;
      if (!taskRec || taskRec.state === "error") {
        pr.status = "needs_human";
        pr.error = `executor ${taskRec?.state ?? "missing"}`;
        run.status = "needs_human";
        store.save(run);
        return false;
      }
      if (taskRec.state === "canceled") return false; // paused/aborted mid-task

      // Review
      pr.status = "reviewing";
      store.save(run);
      const diff = taskRec.diff?.patch ?? "";
      const rv = await this.deps.reviewer(pr.phase, diff, { cwd: run.cwd, model: run.options.reviewerModel, signal });
      run = store.get(runId);
      if (!run || run.status === "aborted") return false;
      pr = run.phases[idx];
      if (!pr) return false;

      if (!rv.ok || !rv.verdict) {
        pr.status = "needs_human";
        pr.error = rv.error ?? "review failed";
        run.status = "needs_human";
        store.save(run);
        return false;
      }
      pr.lastVerdict = rv.verdict;
      pr.verdicts.push(rv.verdict);
      store.save(run);

      if (rv.verdict.pass) {
        pr.status = "passed";
        pr.finishedAt = Date.now();
        store.save(run);
        return true;
      }

      if (pr.iteration >= run.options.maxReviseIters) {
        pr.status = "needs_human";
        pr.error = "revise iterations exhausted";
        run.status = "needs_human";
        store.save(run);
        return false;
      }
      pr.iteration++;
      store.save(run);
      // loop -> revise
    }
  }
}
