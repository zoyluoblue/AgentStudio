// Long-term memory: plain Markdown files that every backend reads.
// A global file applies everywhere; each project gets its own file (keyed by a hash of its path).
// `memoryContext()` builds the block that gets injected into each model's prompt/system prompt,
// so claude / codex / deepseek all see the same memory regardless of backend.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { log } from "./log.js";

let dir = "";
/** Soft cap on the injected memory block so it can't blow up the context window. */
const MAX_CHARS = 12000;

export function initMemory(d: string): void {
  dir = d;
  try {
    mkdirSync(join(dir, "projects"), { recursive: true });
  } catch (e) {
    log("memory.init.error", { err: String(e) });
  }
}

function globalFile(): string {
  return join(dir, "global.md");
}
// Project memory lives INSIDE the project (`<project>/.agentstudio/memory.md`) so it travels
// with the project and can be inspected / version-controlled.
function projectFile(cwd: string): string {
  return join(cwd, ".agentstudio", "memory.md");
}
// Pre-move location (userData/memory/projects/<hash>.md) — migrated into the project on first read.
function legacyProjectFile(cwd: string): string {
  const hash = createHash("sha1").update(cwd).digest("hex").slice(0, 16);
  return join(dir, "projects", `${hash}.md`);
}
function read(file: string): string {
  try {
    return existsSync(file) ? readFileSync(file, "utf8") : "";
  } catch (e) {
    log("memory.read.error", { err: String(e) });
    return "";
  }
}
function write(file: string, content: string): void {
  try {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content);
  } catch (e) {
    log("memory.write.error", { err: String(e) });
  }
}

// ---- learned memory (auto-extracted from conversations; kept separate from curated) ----
function globalLearnedFile(): string {
  return join(dir, "global.auto.md");
}
function projectLearnedFile(cwd: string): string {
  return join(cwd, ".agentstudio", "memory.auto.md");
}
export function getGlobalLearned(): string {
  return read(globalLearnedFile());
}
export function getProjectLearned(cwd: string | null): string {
  return cwd ? read(projectLearnedFile(cwd)) : "";
}
export function setGlobalLearned(content: string): void {
  write(globalLearnedFile(), content);
  log("memory.learned.set", { scope: "global", len: content.length });
}
export function setProjectLearned(cwd: string | null, content: string): void {
  if (!cwd) return;
  write(projectLearnedFile(cwd), content);
  log("memory.learned.set", { scope: "project", len: content.length });
}
/** Append auto-extracted bullets to learned memory (project if a project is open, else global). */
export function appendLearned(cwd: string | null, lines: string[]): void {
  const items = lines.map((l) => l.trim()).filter(Boolean);
  if (!items.length) return;
  const cur = (cwd ? getProjectLearned(cwd) : getGlobalLearned()).trimEnd();
  const add = items.map((l) => `- ${l}`).join("\n");
  write(cwd ? projectLearnedFile(cwd) : globalLearnedFile(), `${cur ? `${cur}\n` : ""}${add}\n`);
  log("memory.learned.append", { scope: cwd ? "project" : "global", n: items.length });
}

export function getGlobalMemory(): string {
  return read(globalFile());
}
export function getProjectMemory(cwd: string | null): string {
  if (!cwd) return "";
  const f = projectFile(cwd);
  if (existsSync(f)) return read(f);
  // One-time migration: move legacy app-data project memory into the project.
  const legacy = legacyProjectFile(cwd);
  if (existsSync(legacy)) {
    const content = read(legacy);
    write(f, content);
    try {
      unlinkSync(legacy);
    } catch {
      /* ignore */
    }
    log("memory.migrate", { to: f });
    return content;
  }
  return "";
}
export function setGlobalMemory(content: string): void {
  write(globalFile(), content);
  log("memory.set", { scope: "global", len: content.length });
}
export function setProjectMemory(cwd: string | null, content: string): void {
  if (!cwd) return;
  write(projectFile(cwd), content);
  log("memory.set", { scope: "project", len: content.length });
}

/** Append one fact as a bullet — to the project memory if a project is open, else global. */
export function appendMemory(cwd: string | null, line: string): void {
  const fact = line.trim();
  if (!fact) return;
  // Read through the getters so a legacy project file is migrated before we append.
  const cur = (cwd ? getProjectMemory(cwd) : getGlobalMemory()).trimEnd();
  write(cwd ? projectFile(cwd) : globalFile(), `${cur ? `${cur}\n` : ""}- ${fact}\n`);
  log("memory.append", { scope: cwd ? "project" : "global", len: fact.length });
}

/** Combined memory block injected into prompts ("" when there is no memory). Curated first, learned after. */
export function memoryContext(cwd: string | null): string {
  const sections: string[] = [];
  const gc = getGlobalMemory().trim();
  const pc = getProjectMemory(cwd).trim();
  const gl = getGlobalLearned().trim();
  const pl = getProjectLearned(cwd).trim();
  if (gc) sections.push(`【全局记忆】\n${gc}`);
  if (pc) sections.push(`【项目记忆】\n${pc}`);
  if (gl) sections.push(`【全局·自动记忆】\n${gl}`);
  if (pl) sections.push(`【项目·自动记忆】\n${pl}`);
  if (!sections.length) return "";
  let body = sections.join("\n\n");
  if (body.length > MAX_CHARS) body = `${body.slice(0, MAX_CHARS)}\n…（记忆过长，已截断）`;
  return `以下是用户的长期记忆，请在本次回答中参考并遵循：\n${body}`;
}
