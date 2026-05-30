import { EventEmitter } from "node:events";
import { mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { log } from "../util/log.js";
import { type Run, isTerminalRun } from "./runTypes.js";

export type RunEvent = { type: "run"; runId: string };

/** Owns Run records in-memory + mirrors them to <stateDir>/runs/<id>.json. */
export class RunStore {
  private readonly runs = new Map<string, Run>();
  private readonly dir: string;
  private readonly bus = new EventEmitter();

  constructor(stateDir: string) {
    this.dir = join(stateDir, "runs");
    try {
      mkdirSync(this.dir, { recursive: true });
    } catch (e) {
      log.warn("runStore mkdir failed", String(e));
    }
    this.load();
  }

  private load(): void {
    let files: string[];
    try {
      files = readdirSync(this.dir).filter((f) => f.endsWith(".json"));
    } catch {
      return;
    }
    for (const f of files) {
      try {
        const run = JSON.parse(readFileSync(join(this.dir, f), "utf8")) as Run;
        if (!run?.runId) continue;
        // A run mid-flight can't survive a restart's in-memory driver; mark paused so it can be resumed/inspected.
        if (!isTerminalRun(run.status) && run.status !== "awaiting_plan_approval" && run.status !== "awaiting_phase_approval") {
          run.status = "paused";
        }
        this.runs.set(run.runId, run);
      } catch (e) {
        log.warn(`runStore load failed for ${f}`, String(e));
      }
    }
  }

  on(cb: (e: RunEvent) => void): () => void {
    this.bus.on("evt", cb);
    return () => this.bus.off("evt", cb);
  }

  get(id: string): Run | undefined {
    return this.runs.get(id);
  }
  list(): Run[] {
    return [...this.runs.values()];
  }

  create(run: Run): void {
    this.runs.set(run.runId, run);
    this.save(run);
  }

  /** Persist + notify subscribers. Call after mutating a run. */
  save(run: Run): void {
    run.updatedAt = Date.now();
    const file = join(this.dir, `${run.runId}.json`);
    const tmp = `${file}.tmp`;
    try {
      writeFileSync(tmp, JSON.stringify(run), "utf8");
      renameSync(tmp, file);
    } catch (e) {
      log.warn("runStore save failed", String(e));
    }
    this.bus.emit("evt", { type: "run", runId: run.runId });
  }
}
