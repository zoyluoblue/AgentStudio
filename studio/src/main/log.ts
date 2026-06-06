import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

let logFile = "";
let sink: ((line: string) => void) | null = null;

/** Also forward every log line somewhere live (e.g. the renderer's terminal panel). */
export function setLogSink(fn: (line: string) => void): void {
  sink = fn;
}

export function setLogFile(p: string): void {
  logFile = p;
  try {
    mkdirSync(dirname(p), { recursive: true });
    appendFileSync(logFile, `\n${new Date().toISOString()} ===== session start =====\n`);
  } catch {
    /* ignore */
  }
}

export function getLogFile(): string {
  return logFile;
}

function fmt(d: unknown): string {
  if (d === undefined) return "";
  if (typeof d === "string") return ` ${d}`;
  try {
    return ` ${JSON.stringify(d)}`;
  } catch {
    return ` ${String(d)}`;
  }
}

/** Append a timestamped event to the log file (and stderr) for retroactive debugging. */
export function log(event: string, data?: unknown): void {
  const line = `${new Date().toISOString()} ${event}${fmt(data)}`;
  console.error("[log]", line);
  if (logFile) {
    try {
      appendFileSync(logFile, `${line}\n`);
    } catch {
      /* ignore */
    }
  }
  if (sink) {
    try {
      sink(line);
    } catch {
      /* ignore */
    }
  }
}
