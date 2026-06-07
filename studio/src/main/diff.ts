import { type Dirent, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const SKIP = new Set(["node_modules", "out", "release", "dist", ".next", ".cache"]);

function walk(dir: string, base: string, acc: Map<string, string>, depth: number): void {
  if (depth > 8) return;
  let entries: Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (SKIP.has(e.name)) continue;
    if (e.isDirectory() && e.name.startsWith(".")) continue; // skip .git, .next, ...
    const full = join(dir, e.name);
    if (e.isDirectory()) {
      walk(full, base, acc, depth + 1);
    } else if (e.isFile()) {
      try {
        const s = statSync(full);
        if (s.size > 2_000_000) continue; // skip very large files
        acc.set(relative(base, full), `${s.mtimeMs}:${s.size}`);
      } catch {
        /* ignore */
      }
    }
  }
}

export type Snapshot = Map<string, string>;

/** Snapshot a project's files (path -> mtime:size). Works for any folder, git or not. */
export function snapshot(cwd: string): Snapshot {
  const m = new Map<string, string>();
  walk(cwd, cwd, m, 0);
  return m;
}

const TEXT_EXT = new Set([
  "html", "htm", "css", "scss", "sass", "less", "js", "mjs", "cjs", "ts", "tsx", "jsx",
  "json", "md", "txt", "svg", "vue", "xml", "yml", "yaml", "toml", "py", "rb", "go", "rs", "sh",
]);

function collectText(dir: string, base: string, acc: { path: string; content: string }[], depth: number): void {
  if (depth > 6 || acc.length > 60) return;
  let entries: Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (SKIP.has(e.name) || e.name.startsWith(".")) continue;
    const full = join(dir, e.name);
    if (e.isDirectory()) {
      collectText(full, base, acc, depth + 1);
    } else if (e.isFile()) {
      const ext = e.name.split(".").pop()?.toLowerCase() ?? "";
      if (!TEXT_EXT.has(ext)) continue;
      try {
        if (statSync(full).size > 200_000) continue;
        acc.push({ path: relative(base, full), content: readFileSync(full, "utf8") });
      } catch {
        /* ignore */
      }
    }
  }
}

/** Concatenate the project's text files (path-headed, truncated) so a text-only LLM can edit them. */
export function projectContext(cwd: string, budget = 16000): string {
  const files: { path: string; content: string }[] = [];
  collectText(cwd, cwd, files, 0);
  let out = "";
  for (const f of files) {
    const body = f.content.length > 6000 ? `${f.content.slice(0, 6000)}\n…(已截断)` : f.content;
    const chunk = `\n### ${f.path}\n\`\`\`\n${body}\n\`\`\`\n`;
    if (out.length + chunk.length > budget) {
      out += "\n…(其余文件略)";
      break;
    }
    out += chunk;
  }
  return out.trim();
}

/**
 * Compare a prior snapshot to the current tree and produce a review-friendly summary
 * that INCLUDES the content of new/changed files — Claude reviews with tools disabled,
 * so it can only see what we put in the prompt (a plain `git diff` missed new files / non-git dirs).
 */
export function changesSince(before: Snapshot, cwd: string): string {
  const after = snapshot(cwd);
  const added: string[] = [];
  const modified: string[] = [];
  const deleted: string[] = [];
  for (const [p, sig] of after) {
    if (!before.has(p)) added.push(p);
    else if (before.get(p) !== sig) modified.push(p);
  }
  for (const [p] of before) if (!after.has(p)) deleted.push(p);

  if (!added.length && !modified.length && !deleted.length) return "（未检测到文件改动）";

  const parts: string[] = [`改动概览：新增 ${added.length}，修改 ${modified.length}，删除 ${deleted.length}`];
  if (deleted.length) parts.push(`删除：${deleted.join(", ")}`);

  const show = [
    ...added.map((p) => ["新增", p] as const),
    ...modified.map((p) => ["修改", p] as const),
  ];
  for (const [status, p] of show.slice(0, 25)) {
    parts.push(`\n### ${status}: ${p}`);
    try {
      const content = readFileSync(join(cwd, p), "utf8");
      parts.push(`\`\`\`\n${content.slice(0, 4000)}${content.length > 4000 ? "\n…(已截断)" : ""}\n\`\`\``);
    } catch {
      parts.push("（无法读取内容）");
    }
  }
  if (show.length > 25) parts.push(`…还有 ${show.length - 25} 个文件未展示`);
  return parts.join("\n");
}
