// DeepSeek backend: a direct OpenAI-compatible chat call (api.deepseek.com is
// reachable directly in CN, so this does NOT go through the proxy).
// As MASTER it plans (plain text). As SLAVE/executor it has no agentic harness,
// so we use the "emit full files" protocol below and write the files ourselves.
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve, sep } from "node:path";
import { log } from "./log.js";

const ENDPOINT = "https://api.deepseek.com/chat/completions";

/** System prompt that makes DeepSeek emit whole files in a parseable envelope. */
export const DEEPSEEK_EXECUTOR_SYSTEM =
  "你是编码执行者。根据需求直接产出完整文件内容。每个要新建或修改的文件，严格用下面的标记输出，" +
  "标记必须独占一行，不要用 markdown 代码围栏把整段包起来，文件内容要完整、不要省略：\n" +
  "<<<FILE: 相对路径>>>\n（完整文件内容）\n<<<END FILE>>>\n" +
  "规则：路径相对项目根；只输出需要新建或修改的文件；可以在文件块之外用一两句中文说明你做了什么。";

/** Parse the <<<FILE: path>>> … <<<END FILE>>> blocks out of DeepSeek's output. */
export function parseFileBlocks(text: string): { files: { path: string; content: string }[]; prose: string } {
  const files: { path: string; content: string }[] = [];
  const re = /<<<FILE:\s*(.+?)\s*>>>\r?\n([\s\S]*?)\r?\n<<<END FILE>>>/g;
  for (let m = re.exec(text); m !== null; m = re.exec(text)) {
    // strip an accidental markdown fence wrapper inside the block
    const content = m[2].replace(/^```[\w-]*\r?\n/, "").replace(/\r?\n```\s*$/, "");
    files.push({ path: m[1].trim(), content });
  }
  const prose = text.replace(re, "").trim();
  return { files, prose };
}

/** Write parsed files into cwd, refusing any path that escapes the project root. */
export function applyFiles(cwd: string, files: { path: string; content: string }[]): string[] {
  const root = resolve(cwd);
  const written: string[] = [];
  for (const f of files) {
    const rel = f.path.replace(/^[/\\]+/, "");
    const abs = resolve(root, rel);
    if (abs !== root && !abs.startsWith(root + sep)) {
      log("deepseek.write.skip", { path: f.path, reason: "escapes project root" });
      continue;
    }
    try {
      mkdirSync(dirname(abs), { recursive: true });
      writeFileSync(abs, f.content);
      written.push(rel);
    } catch (e) {
      log("deepseek.write.error", { path: rel, err: String(e) });
    }
  }
  return written;
}

export interface DeepseekAsk {
  prompt: string;
  systemPrompt?: string;
  model?: string;
  apiKey: string;
  signal?: AbortSignal;
}

export interface DeepseekResult {
  ok: boolean;
  text: string;
  error?: string;
}

function fakeDeepseek(ask: DeepseekAsk): Promise<DeepseekResult> {
  const isExec = ask.systemPrompt?.includes("<<<FILE");
  const isReview = ask.prompt.includes("审查") || ask.prompt.includes("git diff");
  const text = isExec
    ? "我创建了一个可直接打开的单文件页面。\n<<<FILE: index.html>>>\n<!doctype html>\n<html lang=\"zh\"><head><meta charset=\"utf-8\"><title>DeepSeek</title></head>\n<body style=\"font-family:sans-serif;text-align:center;padding:40px\"><h1>🐬 DeepSeek 写的页面</h1></body></html>\n<<<END FILE>>>"
    : isReview
      ? "✅ 通过：DeepSeek 审查认为改动达成了目标。"
      : "好的（DeepSeek）：我把它拆成 3 步，交给右栏执行。";
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve({ ok: true, text }), Number(process.env.STUDIO_FAKE_DELAY ?? 900));
    ask.signal?.addEventListener("abort", () => {
      clearTimeout(t);
      resolve({ ok: false, text: "", error: "已停止" });
    });
  });
}

/** Single-turn DeepSeek completion. Context for collab is carried in the prompt itself. */
export async function askDeepseek(ask: DeepseekAsk): Promise<DeepseekResult> {
  if (process.env.STUDIO_FAKE) return fakeDeepseek(ask);
  if (!ask.apiKey) return { ok: false, text: "", error: "请先填写 DeepSeek API Key" };

  const messages: { role: string; content: string }[] = [];
  if (ask.systemPrompt) messages.push({ role: "system", content: ask.systemPrompt });
  messages.push({ role: "user", content: ask.prompt });
  const model = ask.model || "deepseek-chat";
  log("deepseek.exec", { model, promptLen: ask.prompt.length });

  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${ask.apiKey}` },
      body: JSON.stringify({ model, messages, stream: false }),
      signal: ask.signal,
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const msg = body.slice(0, 300) || `HTTP ${res.status}`;
      log("deepseek.error", { status: res.status, body: msg });
      return { ok: false, text: "", error: `DeepSeek 请求失败（${res.status}）：${msg}` };
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
    const text = data.choices?.[0]?.message?.content ?? "";
    log("deepseek.done", { len: text.length });
    return text ? { ok: true, text } : { ok: false, text: "", error: "DeepSeek 返回为空" };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (ask.signal?.aborted) return { ok: false, text: "", error: "已停止" };
    log("deepseek.error", { err: msg });
    return { ok: false, text: "", error: `DeepSeek 网络错误：${msg}` };
  }
}
