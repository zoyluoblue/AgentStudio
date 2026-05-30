import { CliExecutor } from "./cli/cliExecutor.js";
import { codexSpec } from "./codex/codexExecutor.js";
import { geminiSpec } from "./gemini/geminiExecutor.js";
import { grokSpec } from "./grok/grokExecutor.js";
import type { Executor, ExecutorCapabilities } from "./types.js";

const executors = new Map<string, Executor>();
let initialized = false;

export function registerExecutor(ex: Executor): void {
  executors.set(ex.name, ex);
}

/**
 * Register built-in executors once. Adding a backend is a one-line change here —
 * the tool surface and director skill are untouched (that's the whole point of
 * the Executor abstraction).
 */
export function ensureBuiltins(): void {
  if (initialized) return;
  registerExecutor(new CliExecutor(codexSpec));
  registerExecutor(new CliExecutor(geminiSpec));
  registerExecutor(new CliExecutor(grokSpec));
  initialized = true;
}

export function listExecutors(): string[] {
  return [...executors.keys()];
}

export interface ExecutorInfo {
  name: string;
  available: boolean;
  experimental: boolean;
  capabilities: ExecutorCapabilities;
}

export function executorsInfo(): ExecutorInfo[] {
  return [...executors.values()].map((e) => ({
    name: e.name,
    available: e.isAvailable(),
    experimental: e.experimental === true,
    capabilities: e.capabilities,
  }));
}

/** Resolve an executor by name, falling back to `fallback`. Throws if unknown. */
export function getExecutor(name: string | undefined, fallback: string): Executor {
  const key = name || fallback;
  const ex = executors.get(key);
  if (!ex) {
    throw new Error(`unknown executor '${key}'; available: [${listExecutors().join(", ")}]`);
  }
  return ex;
}
