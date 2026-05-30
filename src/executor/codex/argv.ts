import { join } from "node:path";
import type { StartArgs } from "../types.js";

export interface ArgvResult {
  argv: string[];
  /** Path the agent's final message is written to (`-o`). */
  outputFile: string;
  /** Path the JSON schema is written to (`--output-schema`), when requested. */
  schemaFile?: string;
}

export interface ArgvOptions {
  tmpDir: string;
  /** Forced approval policy; defaults to "never" (detached child can't answer prompts). */
  approvalPolicy?: string;
}

/**
 * Build argv for a fresh `codex exec`. The prompt is NEVER an argv element — it is
 * delivered via stdin (the trailing "-"), avoiding all shell-quoting / arg-length
 * issues. `-s` and `approval_policy` are ALWAYS set explicitly so the child never
 * inherits a dangerous global default or blocks on an approval prompt.
 */
export function buildExecArgv(args: StartArgs, opts: ArgvOptions): ArgvResult {
  const approval = opts.approvalPolicy ?? "never";
  const outputFile = join(opts.tmpDir, "last-message.txt");

  const argv: string[] = [
    "exec",
    "--json",
    "-s",
    args.sandbox,
    "-c",
    `approval_policy="${approval}"`,
    "--skip-git-repo-check",
    "-C",
    args.cwd,
  ];

  // Enable network in the workspace-write sandbox so installs (npm/pip/...) work.
  if (args.sandbox === "workspace-write" && process.env.AGENTCONNECTOR_CODEX_NO_NETWORK !== "1") {
    argv.push("-c", "sandbox_workspace_write.network_access=true");
  }

  if (args.model) argv.push("-m", args.model);
  for (const dir of args.addDirs ?? []) argv.push("--add-dir", dir);

  let schemaFile: string | undefined;
  if (args.outputSchema !== undefined) {
    schemaFile = join(opts.tmpDir, "schema.json");
    argv.push("--output-schema", schemaFile);
  }

  argv.push("-o", outputFile);
  argv.push("-"); // read the prompt from stdin
  return { argv, outputFile, schemaFile };
}

/**
 * Build argv for `codex exec resume <sessionId>`. NOTE: resume does NOT accept
 * `-s`, `-C`, `--add-dir`, or `--output-schema` (verified via --help), so the
 * sandbox is set through `-c sandbox_mode=...`, the working dir is set via the
 * spawned process's cwd, and structured output is unavailable on resume.
 */
export function buildResumeArgv(args: StartArgs, opts: ArgvOptions, sessionId: string): ArgvResult {
  const approval = opts.approvalPolicy ?? "never";
  const outputFile = join(opts.tmpDir, "last-message.txt");

  const argv: string[] = [
    "exec",
    "resume",
    sessionId,
    "--json",
    "-c",
    `approval_policy="${approval}"`,
    "-c",
    `sandbox_mode="${args.sandbox}"`,
    "--skip-git-repo-check",
  ];

  if (args.sandbox === "workspace-write" && process.env.AGENTCONNECTOR_CODEX_NO_NETWORK !== "1") {
    argv.push("-c", "sandbox_workspace_write.network_access=true");
  }

  if (args.model) argv.push("-m", args.model);

  argv.push("-o", outputFile);
  argv.push("-"); // read the prompt from stdin
  return { argv, outputFile };
}
