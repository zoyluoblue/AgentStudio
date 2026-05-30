import type { NormalizedEvent } from "../types.js";

// Codex `exec --json` emits one JSON object per line. The top-level
// discriminator is `type` (dotted, e.g. "thread.started", "item.completed",
// "turn.completed"). For item.* events, the nested `item.type` is the
// sub-discriminator ("command_execution", "agent_message", "reasoning", …).
//
// This normalizer is deliberately TOLERANT: any event/item shape it doesn't
// recognize maps to "unknown" while always retaining `raw`. New event kinds in
// future Codex versions therefore never crash the parser.

export function normalizeCodexEvent(raw: unknown, ts: number): NormalizedEvent {
  if (!raw || typeof raw !== "object") {
    return { kind: "unknown", raw, ts };
  }
  const obj = raw as Record<string, unknown>;
  const type = typeof obj["type"] === "string" ? (obj["type"] as string) : undefined;

  switch (type) {
    case "thread.started": {
      const sessionId = asString(obj["thread_id"]);
      return { kind: "session_meta", raw, ts, sessionId };
    }
    case "turn.completed":
      return { kind: "token_usage", raw, ts };
    case "turn.failed":
    case "error":
      return { kind: "error", raw, ts, text: stringifyMaybe(obj["message"] ?? obj["error"]) };
    case "item.started":
    case "item.updated":
    case "item.completed":
      return normalizeItem(obj, type, raw, ts);
    default:
      return { kind: "unknown", raw, ts };
  }
}

function normalizeItem(
  obj: Record<string, unknown>,
  type: string,
  raw: unknown,
  ts: number,
): NormalizedEvent {
  const item =
    obj["item"] && typeof obj["item"] === "object"
      ? (obj["item"] as Record<string, unknown>)
      : undefined;
  const itemType = item && typeof item["type"] === "string" ? (item["type"] as string) : undefined;
  const completed = type === "item.completed";

  switch (itemType) {
    case "agent_message":
      return { kind: "assistant_text", raw, ts, text: asString(item?.["text"]) };
    case "reasoning":
      return { kind: "reasoning", raw, ts, text: asString(item?.["text"]) };
    case "command_execution":
      return completed
        ? { kind: "tool_result", raw, ts, text: asString(item?.["aggregated_output"]) }
        : { kind: "tool_call", raw, ts, text: asString(item?.["command"]) };
    default:
      // file_change, mcp_tool_call, web_search, patch, … — keep generic.
      return { kind: completed ? "tool_result" : "tool_call", raw, ts, text: itemType };
  }
}

/** Scan events newest-first for the last agent message text (fallback for final message). */
export function lastAgentMessage(events: NormalizedEvent[]): string | undefined {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i];
    if (e && e.kind === "assistant_text" && e.text) return e.text;
  }
  return undefined;
}

function asString(v: unknown): string | undefined {
  return typeof v === "string" ? v : undefined;
}

function stringifyMaybe(v: unknown): string | undefined {
  if (v === undefined || v === null) return undefined;
  if (typeof v === "string") return v;
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}
