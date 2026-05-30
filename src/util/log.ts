// IMPORTANT: every log line goes to STDERR only. stdout is the MCP stdio
// transport (JSON-RPC frames); writing anything else to stdout corrupts it.
//
// Config via env (read once at startup):
//   AGENTCONNECTOR_LOG_LEVEL = debug | info | warn | error   (default info)
//   AGENTCONNECTOR_LOG_JSON  = 1 | true                       (structured JSON lines)

type Level = "debug" | "info" | "warn" | "error";

const ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };

const threshold = ORDER[(process.env.AGENTCONNECTOR_LOG_LEVEL as Level) || "info"] ?? ORDER.info;
const asJson = process.env.AGENTCONNECTOR_LOG_JSON === "1" || process.env.AGENTCONNECTOR_LOG_JSON === "true";

function emit(level: Level, msg: string, extra?: unknown): void {
  if (ORDER[level] < threshold) return;

  if (asJson) {
    let line: string;
    try {
      line = JSON.stringify({ ts: new Date().toISOString(), level, msg, extra });
    } catch {
      line = JSON.stringify({ ts: new Date().toISOString(), level, msg, extra: "[unserializable]" });
    }
    process.stderr.write(line + "\n");
    return;
  }

  let line = `[${new Date().toISOString()}] [agentconnector] [${level}] ${msg}`;
  if (extra !== undefined) {
    let rendered: string;
    if (typeof extra === "string") rendered = extra;
    else {
      try {
        rendered = JSON.stringify(extra);
      } catch {
        rendered = "[unserializable]";
      }
    }
    line += " " + rendered;
  }
  process.stderr.write(line + "\n");
}

export const log = {
  debug: (msg: string, extra?: unknown) => emit("debug", msg, extra),
  info: (msg: string, extra?: unknown) => emit("info", msg, extra),
  warn: (msg: string, extra?: unknown) => emit("warn", msg, extra),
  error: (msg: string, extra?: unknown) => emit("error", msg, extra),
};
