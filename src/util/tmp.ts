import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(tmpdir(), "agentconnector");

/** Create a unique per-run temp dir, e.g. /tmp/agentconnector/run-XXXXXX. */
export function createRunTmpDir(): string {
  mkdirSync(ROOT, { recursive: true });
  return mkdtempSync(join(ROOT, "run-"));
}

/** Best-effort recursive removal; never throws. */
export function cleanupTmpDir(dir: string): void {
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {
    // best-effort: leftover temp files are harmless
  }
}
