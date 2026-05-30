import { describe, it, expect } from "vitest";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Config } from "../src/config";
import type { PlanPhase } from "../src/director/schemas";
import type { Executor, NormalizedEvent, RunHandle, StartArgs } from "../src/executor/types";
import { Orchestrator, type PlannerFn, type ReviewerFn } from "../src/orchestrator/orchestrator";
import { RunStore } from "../src/orchestrator/runStore";
import type { Run } from "../src/orchestrator/runTypes";
import { TaskStore } from "../src/tasks/taskStore";

function cfg(): Config {
  return {
    defaultExecutor: "codex",
    defaultSandbox: "workspace-write",
    defaultIsolation: "inplace",
    maxConcurrent: 8,
    maxRetries: 0,
    maxDiffBytes: 10000,
    maxEvents: 100,
    maxStderrLines: 50,
    killGraceMs: 100,
    stateDir: mkdtempSync(join(tmpdir(), "ac-orch-")),
    logLevel: "error",
  };
}

const phaseA: PlanPhase = { id: "p1", title: "A", goal: "ga", codePlan: "ca", uiPlan: "N/A", acceptanceCriteria: ["a1"] };
const phaseB: PlanPhase = { id: "p2", title: "B", goal: "gb", codePlan: "cb", uiPlan: "N/A", acceptanceCriteria: ["b1"] };

function mockCodex(): Executor {
  let n = 0;
  return {
    name: "codex",
    isAvailable: () => true,
    capabilities: { structuredOutput: true, jsonEvents: true, cancel: true, resume: true, nativeReview: true, sandboxModes: ["read-only", "workspace-write", "danger-full-access"] },
    start(_args: StartArgs): RunHandle {
      const id = `sess-${++n}`;
      return {
        pid: 1,
        onEvent(cb: (e: NormalizedEvent) => void) {
          setTimeout(() => cb({ kind: "session_meta", raw: {}, sessionId: id, ts: Date.now() }), 1);
        },
        onStderr() {},
        done: new Promise((res) => setTimeout(() => res({ exitCode: 0, signal: null }), 5)),
        readFinalMessage: async () => "did the phase",
        kill() {},
        cleanup() {},
      };
    },
  };
}

const okPlan = (phases: PlanPhase[]): PlannerFn => async () => ({ ok: true, plan: { summary: "s", phases }, raw: "" });
const pass = { pass: true, score: 100, summary: "ok", findings: [], requiredChanges: [] };
const fail = { pass: false, score: 0, summary: "no", findings: [{ severity: "major" as const, note: "x" }], requiredChanges: ["fix it"] };
const alwaysPass: ReviewerFn = async () => ({ ok: true, verdict: pass, raw: "" });

function failNtimes(phaseId: string, n: number): ReviewerFn {
  let count = 0;
  return async (phase) => {
    if (phase.id === phaseId && count < n) {
      count++;
      return { ok: true, verdict: fail, raw: "" };
    }
    return { ok: true, verdict: pass, raw: "" };
  };
}

function makeOrch(planner: PlannerFn, reviewer: ReviewerFn) {
  const c = cfg();
  const taskStore = new TaskStore(c);
  const runStore = new RunStore(c.stateDir);
  const exec = mockCodex();
  const orch = new Orchestrator({ runStore, taskStore, getExecutor: () => exec, planner, reviewer, cfg: c });
  const scratch = mkdtempSync(join(tmpdir(), "ac-orch-cwd-"));
  return { orch, runStore, scratch };
}

async function waitFor(runStore: RunStore, runId: string, pred: (r: Run) => boolean, ms = 4000): Promise<Run> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const r = runStore.get(runId);
    if (r && pred(r)) return r;
    await new Promise((res) => setTimeout(res, 10));
  }
  return runStore.get(runId) as Run;
}

const settled = (r: Run) => r.status === "done" || r.status === "failed" || r.status === "needs_human" || r.status === "aborted";

describe("Orchestrator", () => {
  it("auto: plans and runs all phases to done when reviews pass", async () => {
    const { orch, runStore, scratch } = makeOrch(okPlan([phaseA, phaseB]), alwaysPass);
    const run = orch.startRun({ goal: "g", cwd: scratch });
    const final = await waitFor(runStore, run.runId, settled);
    expect(final.status).toBe("done");
    expect(final.phases.map((p) => p.status)).toEqual(["passed", "passed"]);
    expect(final.currentPhase).toBe(2);
  });

  it("revises a failing phase then passes", async () => {
    const { orch, runStore, scratch } = makeOrch(okPlan([phaseA, phaseB]), failNtimes("p1", 1));
    const run = orch.startRun({ goal: "g", cwd: scratch });
    const final = await waitFor(runStore, run.runId, settled);
    expect(final.status).toBe("done");
    expect(final.phases[0]?.iteration).toBe(1);
    expect(final.phases[0]?.taskIds.length).toBe(2); // execute + 1 revise
    expect(final.phases[0]?.verdicts.length).toBe(2); // fail then pass
  });

  it("escalates to needs_human after exhausting revises", async () => {
    const { orch, runStore, scratch } = makeOrch(okPlan([phaseA, phaseB]), failNtimes("p1", 99));
    const run = orch.startRun({ goal: "g", cwd: scratch, maxReviseIters: 1 });
    const final = await waitFor(runStore, run.runId, settled);
    expect(final.status).toBe("needs_human");
    expect(final.phases[0]?.status).toBe("needs_human");
    expect(final.phases[0]?.iteration).toBe(1);
    expect(final.phases[1]?.status).toBe("pending"); // never reached
  });

  it("manual_plan gate waits for approval, then runs to done", async () => {
    const { orch, runStore, scratch } = makeOrch(okPlan([phaseA, phaseB]), alwaysPass);
    const run = orch.startRun({ goal: "g", cwd: scratch, gateMode: "manual_plan" });
    const afterPlan = await waitFor(runStore, run.runId, (r) => r.status === "awaiting_plan_approval");
    expect(afterPlan.status).toBe("awaiting_plan_approval");
    expect(afterPlan.plan?.phases.length).toBe(2);
    expect(afterPlan.phases.every((p) => p.status === "pending")).toBe(true);
    orch.approvePlan(run.runId);
    const final = await waitFor(runStore, run.runId, settled);
    expect(final.status).toBe("done");
  });

  it("marks run failed when planning fails", async () => {
    const failingPlanner: PlannerFn = async () => ({ ok: false, error: "nope", raw: "" });
    const { orch, runStore, scratch } = makeOrch(failingPlanner, alwaysPass);
    const run = orch.startRun({ goal: "g", cwd: scratch });
    const final = await waitFor(runStore, run.runId, settled);
    expect(final.status).toBe("failed");
    expect(final.planError).toBe("nope");
  });
});
