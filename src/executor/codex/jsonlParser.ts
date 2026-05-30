import { StringDecoder } from "node:string_decoder";
import type { NormalizedEvent } from "../types.js";
import { normalizeCodexEvent } from "./events.js";

export interface JsonlParser {
  /** Feed a chunk (Buffer or string). Complete lines are parsed and emitted. */
  push(chunk: Buffer | string): void;
  /** Emit any buffered trailing partial line. Call once the stream ends. */
  flush(): void;
}

/**
 * Streaming JSONL parser for `codex exec --json`. Handles:
 *  - chunks that split mid-line (buffers the remainder across pushes)
 *  - multiple lines per chunk
 *  - multi-byte UTF-8 split across chunk boundaries (StringDecoder)
 *  - blank lines (ignored) and unparseable lines (-> "unknown" event, never throws)
 *
 * `now` is injectable for deterministic tests.
 */
export function createCodexJsonlParser(
  onEvent: (e: NormalizedEvent) => void,
  now: () => number = () => Date.now(),
): JsonlParser {
  const decoder = new StringDecoder("utf8");
  let buffer = "";

  function handleLine(line: string): void {
    const trimmed = line.trim();
    if (trimmed === "") return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      onEvent({ kind: "unknown", raw: trimmed, ts: now() });
      return;
    }
    onEvent(normalizeCodexEvent(parsed, now()));
  }

  return {
    push(chunk) {
      buffer += typeof chunk === "string" ? chunk : decoder.write(chunk);
      let idx: number;
      while ((idx = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 1);
        handleLine(line);
      }
    },
    flush() {
      buffer += decoder.end();
      if (buffer.length > 0) {
        const rest = buffer;
        buffer = "";
        handleLine(rest);
      }
    },
  };
}
