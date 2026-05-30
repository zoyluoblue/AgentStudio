import { createPlainTextParser, type CliAdapterSpec } from "../cli/cliExecutor.js";
import type { ExecutorCapabilities } from "../types.js";

// EXPERIMENTAL / UNVERIFIED: the Gemini CLI is not installed locally, so this
// spec's argv is best-effort. It is registered for routing + availability
// detection; agent_start with executor:"gemini" fails gracefully until the CLI
// exists. When you install `gemini`, verify these flags and adjust if needed.
const CAPABILITIES: ExecutorCapabilities = {
  structuredOutput: false, // no verified --output-schema equivalent
  jsonEvents: false, // parsed as plain text
  cancel: true, // process-group kill works for any CLI
  resume: false,
  nativeReview: false,
  sandboxModes: ["read-only", "workspace-write", "danger-full-access"],
};

export const geminiSpec: CliAdapterSpec = {
  name: "gemini",
  bin: process.env.AGENTCONNECTOR_GEMINI_BIN || "gemini",
  capabilities: CAPABILITIES,
  experimental: true,
  promptViaStdin: true,
  buildArgv(args) {
    // Gemini CLI non-interactive: read the prompt from stdin, auto-approve tools.
    const argv: string[] = ["-y"];
    if (args.model) argv.push("-m", args.model);
    return { argv };
  },
  createParser(onEvent) {
    return createPlainTextParser(onEvent);
  },
};
