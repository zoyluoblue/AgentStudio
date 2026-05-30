import { createPlainTextParser, type CliAdapterSpec } from "../cli/cliExecutor.js";
import type { ExecutorCapabilities } from "../types.js";

// EXPERIMENTAL / UNVERIFIED: the Grok CLI is not installed locally; this spec is
// best-effort and registered for routing + availability detection only. agent_start
// with executor:"grok" fails gracefully until the CLI exists. Verify the flags
// against the real CLI before relying on it.
const CAPABILITIES: ExecutorCapabilities = {
  structuredOutput: false,
  jsonEvents: false,
  cancel: true,
  resume: false,
  nativeReview: false,
  sandboxModes: ["read-only", "workspace-write", "danger-full-access"],
};

export const grokSpec: CliAdapterSpec = {
  name: "grok",
  bin: process.env.AGENTCONNECTOR_GROK_BIN || "grok",
  capabilities: CAPABILITIES,
  experimental: true,
  promptViaStdin: true,
  buildArgv(args) {
    const argv: string[] = [];
    if (args.model) argv.push("-m", args.model);
    return { argv };
  },
  createParser(onEvent) {
    return createPlainTextParser(onEvent);
  },
};
