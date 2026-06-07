// User preferences (proxy + theme), persisted to userData/settings.json.
// The proxy choice is applied to every claude/codex child process env.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { AppSettings, Backend, ConnectMethod, Lane } from "../shared/ipc.js";
import { log } from "./log.js";

const DEFAULTS: AppSettings = {
  proxyMode: "system",
  proxyUrl: "",
  proxyScope: "both",
  theme: "system",
  masterBackend: "claude",
  slaveBackend: "codex",
  connectMethod: { claude: "app", codex: "app", deepseek: "key" },
  apiKeys: { claude: "", codex: "", deepseek: "" },
  autoMemory: true,
};
const PROXY_KEYS = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"];

let file = "";
let current: AppSettings = { ...DEFAULTS };

export function initSettings(path: string): void {
  file = path;
  try {
    if (existsSync(file)) {
      // `deepseekApiKey` is the pre-multi-backend field name, migrated into apiKeys.deepseek.
      const raw = JSON.parse(readFileSync(file, "utf8")) as Partial<AppSettings> & { deepseekApiKey?: string };
      current = {
        ...DEFAULTS,
        ...raw,
        // nested records: merge with defaults so a partial saved object keeps every backend key
        connectMethod: { ...DEFAULTS.connectMethod, ...raw.connectMethod },
        apiKeys: { ...DEFAULTS.apiKeys, ...raw.apiKeys },
      };
      if (raw.deepseekApiKey && !current.apiKeys.deepseek) current.apiKeys.deepseek = raw.deepseekApiKey;
    }
  } catch (e) {
    log("settings.load.error", { err: String(e) });
  }
  log("settings.loaded", { proxyMode: current.proxyMode, theme: current.theme, hasUrl: !!current.proxyUrl });
}

export function getSettings(): AppSettings {
  return current;
}

export function updateSettings(patch: Partial<AppSettings>): AppSettings {
  // Merge nested records against the PREVIOUS state so a partial patch (e.g. one backend's
  // key) can never drop the other backends' method / key.
  const next: AppSettings = { ...current, ...patch };
  if (patch.connectMethod) next.connectMethod = { ...current.connectMethod, ...patch.connectMethod };
  if (patch.apiKeys) next.apiKeys = { ...current.apiKeys, ...patch.apiKeys };
  current = next;
  try {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(current, null, 2));
  } catch (e) {
    log("settings.save.error", { err: String(e) });
  }
  log("settings.update", { proxyMode: current.proxyMode, theme: current.theme, hasUrl: !!current.proxyUrl });
  return current;
}

function inScope(lane: Lane): boolean {
  return current.proxyScope === "both" || current.proxyScope === lane;
}

/**
 * Apply the user's proxy choice onto a spawn env for a given lane (mutates + returns it).
 * Out-of-scope lanes get their proxy vars stripped so they go direct.
 */
export function applyProxy(env: NodeJS.ProcessEnv, lane: Lane): NodeJS.ProcessEnv {
  if (current.proxyMode === "none" || !inScope(lane)) {
    for (const k of PROXY_KEYS) delete env[k];
  } else if (current.proxyMode === "custom" && current.proxyUrl.trim()) {
    const u = current.proxyUrl.trim();
    env.HTTP_PROXY = u;
    env.HTTPS_PROXY = u;
    env.http_proxy = u;
    env.https_proxy = u;
  }
  // "system" + in scope → leave whatever the OS/shell provided untouched
  return env;
}

/** The proxy host:port a lane will actually use (for error hints), or null. */
export function effectiveProxy(lane: Lane): string | null {
  if (current.proxyMode === "none" || !inScope(lane)) return null;
  const p =
    current.proxyMode === "custom"
      ? current.proxyUrl.trim() || undefined
      : process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy;
  return p ? p.replace(/^https?:\/\//, "").replace(/\/$/, "") : null;
}

export function backendFor(lane: Lane): Backend {
  return lane === "master" ? current.masterBackend : current.slaveBackend;
}
/** How a backend authenticates. DeepSeek has no CLI login, so it is always "key". */
export function connectMethodFor(backend: Backend): ConnectMethod {
  return backend === "deepseek" ? "key" : (current.connectMethod[backend] ?? "app");
}
/** The API key configured for a backend ("" if none / not in key mode). */
export function apiKeyFor(backend: Backend): string {
  return (current.apiKeys[backend] ?? "").trim();
}
