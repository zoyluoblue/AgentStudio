import type { CliAdapterSpec } from "../cli/cliExecutor.js";
import type { ExecutorCapabilities } from "../types.js";
import { buildExecArgv, buildResumeArgv } from "./argv.js";
import { createCodexJsonlParser } from "./jsonlParser.js";

const CAPABILITIES: ExecutorCapabilities = {
  structuredOutput: true,
  jsonEvents: true,
  cancel: true,
  resume: true,
  nativeReview: true,
  sandboxModes: ["read-only", "workspace-write", "danger-full-access"],
};

/** Codex adapter spec: wraps `codex exec` (and `codex exec resume`). */
export const codexSpec: CliAdapterSpec = {
  name: "codex",
  bin: process.env.AGENTCONNECTOR_CODEX_BIN || "codex",
  capabilities: CAPABILITIES,
  promptViaStdin: true,
  buildArgv(args, { tmpDir }) {
    const isResume = Boolean(args.resumeSessionId);
    const built = isResume
      ? buildResumeArgv(args, { tmpDir }, args.resumeSessionId as string)
      : buildExecArgv(args, { tmpDir });
    const schemaContent =
      !isResume && built.schemaFile && args.outputSchema !== undefined
        ? JSON.stringify(args.outputSchema)
        : undefined;
    return { argv: built.argv, outputFile: built.outputFile, schemaFile: built.schemaFile, schemaContent };
  },
  createParser(onEvent) {
    return createCodexJsonlParser(onEvent);
  },
};
