import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Orchestrator, RunStore, TaskStore, ensureBuiltins, executorsInfo, getExecutor, loadConfig, plan, review, toTaskView } from "@engine";
import type { Plan, Run, RunEvent, StartArgs, StoreEvent } from "@engine";
import type {
  ApplyResult,
  ConfigView,
  ExecutorInfo,
  ProjectInfo,
  ResumeInput,
  ReviewInput,
  RunStartInput,
  StartInput,
  StartResult,
  Stats,
  StatusSummary,
  TaskView,
} from "../shared/ipc.js";

const pExecFile = promisify(execFile);

const REVIEW_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: { type: "string" },
    findings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          severity: { type: "string", enum: ["info", "minor", "major", "critical"] },
          file: { type: "string" },
          line: { type: "number" },
          note: { type: "string" },
        },
        required: ["severity", "note"],
      },
    },
    verdict: { type: "string", enum: ["approve", "approve_with_nits", "request_changes"] },
  },
  required: ["summary", "findings", "verdict"],
};

/** Pure (no Electron) wrapper around the engine. Unit-testable; the IPC layer is thin over this. */
export class EngineService {
  private readonly cfg = loadConfig();
  private readonly store: TaskStore;
  private readonly runStore: RunStore;
  private readonly orch: Orchestrator;
  private projectCwd = process.cwd();

  constructor() {
    ensureBuiltins();
    this.store = new TaskStore(this.cfg);
    this.runStore = new RunStore(this.cfg.stateDir);
    this.orch = new Orchestrator({
      runStore: this.runStore,
      taskStore: this.store,
      getExecutor: (name, fallback) => getExecutor(name, fallback),
      planner: (goal, opts) => plan(goal, opts),
      reviewer: (phase, diff, opts) => review(phase, diff, opts),
      cfg: this.cfg,
    });
  }

  onChange(cb: (e: StoreEvent) => void): () => void {
    return this.store.on(cb);
  }

  onRunChange(cb: (e: RunEvent) => void): () => void {
    return this.runStore.on(cb);
  }

  // ---- orchestrated runs ----
  runStart(input: RunStartInput): Run {
    return this.orch.startRun({
      goal: input.goal,
      cwd: input.cwd ?? this.projectCwd,
      gateMode: input.gateMode,
      maxReviseIters: input.maxReviseIters,
      executor: input.executor,
      sandbox: this.cfg.defaultSandbox,
      plannerModel: input.plannerModel,
      reviewerModel: input.reviewerModel,
      executorModel: input.executorModel,
    });
  }
  runGet(runId: string): Run | null {
    return this.runStore.get(runId) ?? null;
  }
  runList(): Run[] {
    return this.runStore.list();
  }
  runApprovePlan(runId: string): void {
    this.orch.approvePlan(runId);
  }
  runEditPlan(runId: string, p: Plan): void {
    this.orch.editPlan(runId, p);
  }
  runApprovePhase(runId: string): void {
    this.orch.approvePhase(runId);
  }
  runPause(runId: string): void {
    this.orch.pause(runId);
  }
  runResume(runId: string): void {
    this.orch.resume(runId);
  }
  runAbort(runId: string): Promise<void> {
    return this.orch.abort(runId);
  }
  runIntervene(runId: string, instruction: string): void {
    this.orch.intervene(runId, instruction);
  }

  async start(input: StartInput): Promise<StartResult> {
    try {
      const executor = getExecutor(input.executor, this.cfg.defaultExecutor);
      if (!executor.isAvailable()) return { ok: false, error: `executor '${executor.name}' is not available (its CLI was not found on PATH)` };
      const args: StartArgs = {
        prompt: input.prompt,
        cwd: input.cwd ?? this.projectCwd,
        sandbox: input.sandbox ?? this.cfg.defaultSandbox,
        model: input.model,
      };
      const rec = await this.store.start(executor, args, {
        label: input.label,
        isolation: input.isolation,
        maxRetries: input.retries,
      });
      return { ok: true, taskId: rec.taskId, view: toTaskView(rec) };
    } catch (e) {
      return { ok: false, error: msg(e) };
    }
  }

  status(taskId?: string): TaskView | StatusSummary | null {
    if (!taskId) {
      return { ...this.store.stats(), tasks: this.store.list().map((r) => toTaskView(r)) };
    }
    const r = this.store.get(taskId);
    return r ? toTaskView(r) : null;
  }

  result(taskId: string): TaskView | null {
    const r = this.store.get(taskId);
    return r ? toTaskView(r) : null;
  }
  getTask(taskId: string): TaskView | null {
    return this.result(taskId);
  }

  list(filter?: { state?: string; executor?: string }): TaskView[] {
    let t = this.store.list();
    if (filter?.state) t = t.filter((x) => x.state === filter.state);
    if (filter?.executor) t = t.filter((x) => x.executor === filter.executor);
    return t.map((r) => toTaskView(r));
  }

  stats(): Stats {
    return this.store.stats();
  }

  executors(): { default: string; executors: ExecutorInfo[] } {
    return { default: this.cfg.defaultExecutor, executors: executorsInfo() };
  }

  getConfig(): ConfigView {
    return {
      defaultExecutor: this.cfg.defaultExecutor,
      defaultSandbox: this.cfg.defaultSandbox,
      defaultIsolation: this.cfg.defaultIsolation,
      maxConcurrent: this.cfg.maxConcurrent,
      maxRetries: this.cfg.maxRetries,
      maxDiffBytes: this.cfg.maxDiffBytes,
      stateDir: this.cfg.stateDir,
      logLevel: this.cfg.logLevel,
    };
  }

  async cancel(taskId: string, signal?: "SIGTERM" | "SIGKILL"): Promise<{ ok: boolean; view?: TaskView; error?: string }> {
    const r = this.store.get(taskId);
    if (!r) return { ok: false, error: `no task ${taskId}` };
    await this.store.cancel(r, signal ?? "SIGTERM");
    return { ok: true, view: toTaskView(r) };
  }

  async apply(taskId: string): Promise<ApplyResult> {
    const r = this.store.get(taskId);
    if (!r) return { ok: false, error: `no task ${taskId}` };
    const res = await this.store.apply(r);
    return { ok: res.applied, applied: res.applied, reason: res.reason, view: toTaskView(r) };
  }

  async resume(input: ResumeInput): Promise<StartResult> {
    try {
      const executor = getExecutor(input.executor, this.cfg.defaultExecutor);
      if (!executor.isAvailable()) return { ok: false, error: `executor '${executor.name}' is not available` };
      if (!executor.capabilities.resume) return { ok: false, error: `executor '${executor.name}' does not support resume` };
      let sessionId = input.sessionId;
      if (!sessionId && input.taskId) sessionId = this.store.get(input.taskId)?.sessionId;
      if (!sessionId) return { ok: false, error: "no sessionId (and the given taskId has none)" };
      const args: StartArgs = {
        prompt: input.prompt,
        cwd: input.cwd ?? this.projectCwd,
        sandbox: input.sandbox ?? this.cfg.defaultSandbox,
        model: input.model,
        resumeSessionId: sessionId,
      };
      const rec = await this.store.start(executor, args, { label: "resume", isolation: "inplace" });
      return { ok: true, taskId: rec.taskId, view: toTaskView(rec), resumeOf: sessionId };
    } catch (e) {
      return { ok: false, error: msg(e) };
    }
  }

  async review(input: ReviewInput): Promise<StartResult> {
    try {
      const executor = getExecutor(input.executor, this.cfg.defaultExecutor);
      if (!executor.isAvailable()) return { ok: false, error: `executor '${executor.name}' is not available` };
      const scope = input.base
        ? `the changes vs base branch '${input.base}' (use \`git diff ${input.base}...HEAD\`)`
        : "the uncommitted changes (use `git diff` and `git status`)";
      const prompt = [
        `You are a code reviewer. Review ${scope}.`,
        input.instructions ? `Focus: ${input.instructions}` : "",
        "Inspect the diff using git, then return your review STRICTLY as JSON matching the provided output schema.",
      ]
        .filter(Boolean)
        .join("\n");
      const args: StartArgs = { prompt, cwd: input.cwd ?? this.projectCwd, sandbox: "read-only", outputSchema: REVIEW_SCHEMA };
      const rec = await this.store.start(executor, args, { label: "review", isolation: "inplace" });
      return { ok: true, taskId: rec.taskId, view: toTaskView(rec) };
    } catch (e) {
      return { ok: false, error: msg(e) };
    }
  }

  async setProject(cwd: string): Promise<ProjectInfo> {
    this.projectCwd = cwd;
    return this.projectInfo();
  }
  getProject(): Promise<ProjectInfo> {
    return this.projectInfo();
  }

  private async projectInfo(): Promise<ProjectInfo> {
    const cwd = this.projectCwd;
    let isRepo = false;
    let branch: string | undefined;
    let dirty: number | undefined;
    try {
      isRepo = (await pExecFile("git", ["rev-parse", "--is-inside-work-tree"], { cwd })).stdout.trim() === "true";
    } catch {
      /* not a repo */
    }
    if (isRepo) {
      try {
        branch = (await pExecFile("git", ["branch", "--show-current"], { cwd })).stdout.trim();
      } catch {
        /* detached */
      }
      try {
        dirty = (await pExecFile("git", ["status", "--porcelain"], { cwd })).stdout.split("\n").filter((l) => l.trim()).length;
      } catch {
        /* ignore */
      }
    }
    return { cwd, isRepo, branch, dirty };
  }

  async shutdown(): Promise<void> {
    await this.store.shutdown();
  }
}

function msg(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
