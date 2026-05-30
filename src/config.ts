import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { SandboxMode } from "./executor/types.js";
import { log } from "./util/log.js";

export type Isolation = "inplace" | "worktree";

export interface Config {
  defaultExecutor: string;
  defaultSandbox: SandboxMode;
  runSandbox: SandboxMode; // sandbox for orchestrated runs (needs installs -> full access)
  defaultIsolation: Isolation;
  maxConcurrent: number;
  maxRetries: number; // default auto-retry attempts on failure
  maxDiffBytes: number;
  maxEvents: number; // event ring-buffer size per task
  maxStderrLines: number; // stderr ring-buffer size per task
  killGraceMs: number; // SIGTERM -> SIGKILL escalation window
  stateDir: string; // where task snapshots are persisted
  logLevel: string; // for the startup banner (log.ts reads env directly)
}

function envInt(name: string, def: number): number {
  const v = process.env[name];
  if (!v) return def;
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? n : def;
}

const SANDBOXES: SandboxMode[] = ["read-only", "workspace-write", "danger-full-access"];

function envSandbox(name: string, def: SandboxMode): SandboxMode {
  const v = process.env[name] as SandboxMode | undefined;
  return v && SANDBOXES.includes(v) ? v : def;
}

function envIsolation(name: string, def: Isolation): Isolation {
  const v = process.env[name];
  return v === "worktree" || v === "inplace" ? v : def;
}

/** Optional JSON config file: $AGENTCONNECTOR_CONFIG or <cwd>/.agentconnector.json. */
function readConfigFile(): Partial<Config> {
  const path = process.env.AGENTCONNECTOR_CONFIG || join(process.cwd(), ".agentconnector.json");
  try {
    if (!existsSync(path)) return {};
    const raw = JSON.parse(readFileSync(path, "utf8"));
    if (raw && typeof raw === "object") {
      log.info(`loaded config file ${path}`);
      return raw as Partial<Config>;
    }
  } catch (e) {
    log.warn(`config file load failed (${path})`, String(e));
  }
  return {};
}

/** Precedence: environment variable > config file > built-in default. */
export function loadConfig(): Config {
  const f = readConfigFile();
  return {
    defaultExecutor: process.env.AGENTCONNECTOR_DEFAULT_EXECUTOR || f.defaultExecutor || "codex",
    defaultSandbox: envSandbox("AGENTCONNECTOR_DEFAULT_SANDBOX", f.defaultSandbox ?? "workspace-write"),
    runSandbox: envSandbox("AGENTCONNECTOR_RUN_SANDBOX", f.runSandbox ?? "danger-full-access"),
    defaultIsolation: envIsolation("AGENTCONNECTOR_ISOLATION", f.defaultIsolation ?? "inplace"),
    maxConcurrent: envInt("AGENTCONNECTOR_MAX_CONCURRENT", f.maxConcurrent ?? 4),
    maxRetries: envInt("AGENTCONNECTOR_MAX_RETRIES", f.maxRetries ?? 0),
    maxDiffBytes: envInt("AGENTCONNECTOR_MAX_DIFF_BYTES", f.maxDiffBytes ?? 200_000),
    maxEvents: envInt("AGENTCONNECTOR_MAX_EVENTS", f.maxEvents ?? 500),
    maxStderrLines: envInt("AGENTCONNECTOR_MAX_STDERR_LINES", f.maxStderrLines ?? 200),
    killGraceMs: envInt("AGENTCONNECTOR_KILL_GRACE_MS", f.killGraceMs ?? 3000),
    stateDir: process.env.AGENTCONNECTOR_STATE_DIR || f.stateDir || join(process.cwd(), ".agentconnector"),
    logLevel: process.env.AGENTCONNECTOR_LOG_LEVEL || f.logLevel || "info",
  };
}
