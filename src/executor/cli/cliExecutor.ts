import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { log } from "../../util/log.js";
import { cleanupTmpDir, createRunTmpDir } from "../../util/tmp.js";
import { binExists } from "../../util/which.js";
import type { Executor, ExecutorCapabilities, NormalizedEvent, RunExit, RunHandle, StartArgs } from "../types.js";

export interface StreamParser {
  push(chunk: Buffer | string): void;
  flush(): void;
}

export interface BuiltArgv {
  argv: string[];
  /** File the final agent message is written to, if the CLI supports it. */
  outputFile?: string;
  /** File to write a JSON schema to before spawning (paired with schemaContent). */
  schemaFile?: string;
  schemaContent?: string;
}

/**
 * Everything backend-specific about a CLI executor. Adding a new backend =
 * writing one of these (see codex/gemini/grok) and registering it. The tool
 * surface and director skill never change.
 */
export interface CliAdapterSpec {
  name: string;
  bin: string;
  capabilities: ExecutorCapabilities;
  experimental?: boolean;
  /** Deliver the prompt via the child's stdin (default true). */
  promptViaStdin?: boolean;
  buildArgv(args: StartArgs, ctx: { tmpDir: string }): BuiltArgv;
  createParser(onEvent: (e: NormalizedEvent) => void): StreamParser;
}

/** Plain-text backends: accumulate stdout, emit it as one assistant_text on flush. */
export function createPlainTextParser(onEvent: (e: NormalizedEvent) => void): StreamParser {
  let buf = "";
  return {
    push(chunk) {
      buf += typeof chunk === "string" ? chunk : chunk.toString("utf8");
    },
    flush() {
      if (buf.trim().length > 0) onEvent({ kind: "assistant_text", raw: buf, text: buf, ts: Date.now() });
    },
  };
}

/** Generic Executor that spawns a CLI according to an adapter spec. */
export class CliExecutor implements Executor {
  constructor(private readonly spec: CliAdapterSpec) {}

  get name(): string {
    return this.spec.name;
  }
  get capabilities(): ExecutorCapabilities {
    return this.spec.capabilities;
  }
  get experimental(): boolean {
    return this.spec.experimental === true;
  }
  isAvailable(): boolean {
    return binExists(this.spec.bin);
  }

  start(args: StartArgs): RunHandle {
    const tmpDir = createRunTmpDir();
    const { argv, outputFile, schemaFile, schemaContent } = this.spec.buildArgv(args, { tmpDir });
    if (schemaFile && schemaContent !== undefined) writeFileSync(schemaFile, schemaContent, "utf8");

    const child = spawn(this.spec.bin, argv, {
      cwd: args.cwd,
      detached: true, // own process group so cancel kills the whole tree
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
    });

    if (this.spec.promptViaStdin !== false && child.stdin) {
      child.stdin.write(args.prompt);
      child.stdin.end();
    }

    let eventListener: ((e: NormalizedEvent) => void) | undefined;
    const eventBuffer: NormalizedEvent[] = [];
    const emitEvent = (e: NormalizedEvent) => {
      if (eventListener) eventListener(e);
      else eventBuffer.push(e);
    };

    let stderrListener: ((line: string) => void) | undefined;
    const stderrBuffer: string[] = [];
    const emitStderr = (line: string) => {
      if (stderrListener) stderrListener(line);
      else stderrBuffer.push(line);
    };

    const parser = this.spec.createParser(emitEvent);
    if (child.stdout) {
      child.stdout.on("data", (d: Buffer) => parser.push(d));
      child.stdout.on("end", () => parser.flush());
    }
    if (child.stderr) {
      let serr = "";
      child.stderr.setEncoding("utf8");
      child.stderr.on("data", (d: string) => {
        serr += d;
        let idx: number;
        while ((idx = serr.indexOf("\n")) >= 0) {
          emitStderr(serr.slice(0, idx));
          serr = serr.slice(idx + 1);
        }
      });
      child.stderr.on("end", () => {
        if (serr.trim().length > 0) emitStderr(serr);
      });
    }

    const name = this.spec.name;
    const done = new Promise<RunExit>((resolve) => {
      child.on("error", (err) => {
        log.error(`${name} spawn error`, String(err));
        emitEvent({ kind: "error", raw: { error: String(err) }, text: String(err), ts: Date.now() });
        resolve({ exitCode: null, signal: null });
      });
      child.on("close", (code, signal) => {
        parser.flush();
        resolve({ exitCode: code, signal: signal ?? null });
      });
    });

    const handle: RunHandle = {
      pid: child.pid,
      onEvent(cb) {
        eventListener = cb;
        while (eventBuffer.length > 0) cb(eventBuffer.shift()!);
      },
      onStderr(cb) {
        stderrListener = cb;
        while (stderrBuffer.length > 0) cb(stderrBuffer.shift()!);
      },
      done,
      async readFinalMessage() {
        if (!outputFile) return "";
        try {
          return await readFile(outputFile, "utf8");
        } catch {
          return "";
        }
      },
      kill(signal) {
        try {
          if (child.pid !== undefined) process.kill(-child.pid, signal);
        } catch {
          /* already dead / ESRCH */
        }
      },
      cleanup() {
        cleanupTmpDir(tmpDir);
      },
    };

    return handle;
  }
}
