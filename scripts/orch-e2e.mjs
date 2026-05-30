// Orchestrator e2e: REAL Codex executor + MOCK Claude planner/reviewer.
// Verifies the loop drives real Codex through multiple phases (the Claude-in-loop
// part is mocked here because nested `claude -p` doesn't run in this env; it's
// unit-tested separately and works on a normal machine). Run: node scripts/orch-e2e.mjs
import { execSync } from "node:child_process";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Orchestrator, RunStore, TaskStore, ensureBuiltins, getExecutor, loadConfig } from "../dist/core.js";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function scratchRepo() {
  const dir = mkdtempSync(join(tmpdir(), "ac-orch-e2e-"));
  execSync("git init -q && git config user.email t@t && git config user.name t && echo seed > seed.txt && git add -A && git commit -qm seed", { cwd: dir });
  return dir;
}

async function main() {
  ensureBuiltins();
  const scratch = scratchRepo();
  process.env.AGENTCONNECTOR_STATE_DIR = mkdtempSync(join(tmpdir(), "ac-orch-e2e-state-"));
  const cfg = loadConfig();
  const taskStore = new TaskStore(cfg);
  const runStore = new RunStore(cfg.stateDir);

  const planner = async () => ({
    ok: true,
    raw: "",
    plan: {
      summary: "create two files",
      phases: [
        { id: "p1", title: "create a.txt", goal: "create a.txt", codePlan: "Create a file named a.txt containing exactly: AAA", uiPlan: "N/A", acceptanceCriteria: ["a.txt exists with content AAA"] },
        { id: "p2", title: "create b.txt", goal: "create b.txt", codePlan: "Create a file named b.txt containing exactly: BBB", uiPlan: "N/A", acceptanceCriteria: ["b.txt exists with content BBB"] },
      ],
    },
  });
  const reviewer = async () => ({ ok: true, raw: "", verdict: { pass: true, score: 100, summary: "ok", findings: [], requiredChanges: [] } });

  const orch = new Orchestrator({ runStore, taskStore, getExecutor: (n, f) => getExecutor(n, f), planner, reviewer, cfg });
  const run = orch.startRun({ goal: "create two files", cwd: scratch, gateMode: "auto", maxReviseIters: 1 });
  console.log("run", run.runId, "started in", scratch);

  const deadline = Date.now() + 240000;
  let final = runStore.get(run.runId);
  let lastLog = "";
  while (Date.now() < deadline) {
    final = runStore.get(run.runId);
    const line = `${final.status} [${final.phases.map((p) => p.status).join(",")}]`;
    if (line !== lastLog) {
      console.log("  ", line);
      lastLog = line;
    }
    if (["done", "failed", "needs_human", "aborted"].includes(final.status)) break;
    await sleep(2500);
  }

  let fail = 0;
  const check = (c, l) => {
    console.log(`${c ? "✓" : "✗"} ${l}`);
    if (!c) fail++;
  };
  check(final.status === "done", `run reached done (got ${final.status})`);
  check(final.phases.length === 2 && final.phases.every((p) => p.status === "passed"), "both phases passed");
  check(existsSync(join(scratch, "a.txt")), "Codex created a.txt (phase 1)");
  check(existsSync(join(scratch, "b.txt")), "Codex created b.txt (phase 2)");

  console.log(fail === 0 ? "\nORCH-E2E: PASS" : `\nORCH-E2E: FAIL (${fail})`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("orch-e2e crashed:", e);
  process.exit(2);
});
