// AgentStudio ⇄ Claude Agent SDK bridge (Plan B: drives the Anthropic-key lane).
//
// Protocol: read ONE JSON command line from stdin, run a single agent turn via the SDK, stream
// newline-delimited JSON events to stdout, then exit. AgentStudio (Swift) spawns one bridge per
// write turn — mirroring how it already spawns the `claude` CLI, but now with the full agent
// harness (streaming, tool events, sessions, MCP) instead of a hand-rolled loop.
//
// Command (stdin, one line):
//   { prompt, cwd, model?, system?, apiKey?, baseURL?, allowCommands?, mcpServers?, resume?, maxTurns? }
// Events (stdout, one JSON per line):
//   { type:"init", sessionId, model }
//   { type:"text", text }                       // assistant prose (latest block)
//   { type:"tool", name, path?, command? }       // a tool the agent invoked (for activity UI)
//   { type:"result", ok, text, error?, costUSD, inputTokens, outputTokens, numTurns, sessionId, changed[] }

import { query } from '@anthropic-ai/claude-agent-sdk';
import process from 'node:process';

const send = (o) => process.stdout.write(JSON.stringify(o) + '\n');
const logErr = (s) => process.stderr.write(s + '\n');

async function readFirstLine() {
  let buf = '';
  for await (const chunk of process.stdin) {
    buf += chunk;
    const nl = buf.indexOf('\n');
    if (nl >= 0) return buf.slice(0, nl);
  }
  return buf;
}

const EDIT_TOOLS = ['Write', 'Edit', 'MultiEdit', 'NotebookEdit'];

async function main() {
  let cmd;
  try {
    cmd = JSON.parse(await readFirstLine());
  } catch (e) {
    send({ type: 'result', ok: false, error: 'bad command JSON: ' + String(e), changed: [] });
    process.exit(0);
  }

  const {
    prompt, cwd, model, system,
    apiKey, baseURL,
    allowCommands = false,
    mcpServers = {},
    resume,
    maxTurns = 40,
  } = cmd;

  // Tool gate: edits/reads always; Bash only when the user enabled "run commands".
  const baseTools = ['Read', 'Write', 'Edit', 'MultiEdit', 'Glob', 'Grep', 'TodoWrite', 'LS'];
  const allowed = new Set([...baseTools, ...(allowCommands ? ['Bash'] : [])]);

  // Hand the subprocess a CURATED env, not the inherited one — the user exports their own
  // ANTHROPIC_*/CLAUDE_* vars for their personal setup, and any of them leaking in poisons auth.
  // (Proven: the bundled binary authenticates cleanly under `env -i` + our explicit creds.)
  const passthrough = ['HOME', 'PATH', 'USER', 'LOGNAME', 'SHELL', 'TMPDIR', 'LANG', 'LC_ALL', 'TZ', 'TERM'];
  const env = {};
  for (const k of passthrough) if (process.env[k] != null) env[k] = process.env[k];
  env.TERM = env.TERM || 'xterm-256color';
  env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1';

  const isDefaultEndpoint = !baseURL || /(^https?:\/\/)?api\.anthropic\.com/.test(baseURL);
  if (baseURL) env.ANTHROPIC_BASE_URL = baseURL;
  if (apiKey) {
    if (isDefaultEndpoint) {
      env.ANTHROPIC_API_KEY = apiKey;          // real Anthropic API → x-api-key
    } else {
      env.ANTHROPIC_AUTH_TOKEN = apiKey;       // custom gateway/proxy → Bearer (skips api-key approval gate)
    }
  }

  const changed = new Set();
  let finalText = '';

  // Anchor the model on the REAL working directory. Without this the agent confabulates container
  // paths like /app or /home/provider and writes to the wrong place (same failure mode AgentEngine hit).
  const rooted =
    `Your working directory (the project root) is exactly: ${cwd}\n` +
    `Create and edit files there using paths relative to it (e.g. note.txt, src/app.js), or this exact absolute path. ` +
    `Do NOT invent paths like /app, /home/..., or /workspace — those do not exist.\n\n` +
    prompt;

  try {
    const q = query({
      prompt: rooted,
      options: {
        cwd,
        model: model || undefined,
        // Keep Claude Code's coding harness; append AgentStudio's executor nudge.
        systemPrompt: system
          ? { type: 'preset', preset: 'claude_code', append: system }
          : { type: 'preset', preset: 'claude_code' },
        permissionMode: 'default',
        // Every tool decision routes through here → enforces the gate, never hangs on a prompt.
        canUseTool: async (toolName, input) => {
          const ok = allowed.has(toolName) || toolName.startsWith('mcp__');
          return ok
            ? { behavior: 'allow', updatedInput: input }
            : { behavior: 'deny', message: `${toolName} is not allowed in this run` };
        },
        mcpServers,
        resume: resume || undefined,
        env,
        includePartialMessages: false,
        maxTurns,
        settingSources: [], // isolated run — don't inherit the user's ~/.claude config
        stderr: (d) => logErr('[claude] ' + String(d).slice(0, 240)),
      },
    });

    for await (const msg of q) {
      if (msg.type === 'assistant') {
        for (const block of msg.message?.content ?? []) {
          if (block.type === 'text' && block.text) {
            finalText = block.text;
            send({ type: 'text', text: block.text });
          } else if (block.type === 'tool_use') {
            const fp = block.input?.file_path;
            if (EDIT_TOOLS.includes(block.name) && fp) changed.add(fp);
            send({ type: 'tool', name: block.name, path: fp ?? null, command: block.input?.command ?? null });
          }
        }
      } else if (msg.type === 'system' && msg.subtype === 'init') {
        send({ type: 'init', sessionId: msg.session_id ?? null, model: msg.model ?? null });
      } else if (msg.type === 'result') {
        const ok = msg.subtype === 'success';
        send({
          type: 'result',
          ok,
          text: (ok ? msg.result : '') || finalText,
          error: ok ? null : (msg.errors?.join('; ') || msg.subtype),
          costUSD: msg.total_cost_usd ?? 0,
          inputTokens: msg.usage?.input_tokens ?? 0,
          outputTokens: msg.usage?.output_tokens ?? 0,
          numTurns: msg.num_turns ?? 0,
          sessionId: msg.session_id ?? null,
          changed: [...changed],
        });
      }
    }
  } catch (e) {
    send({ type: 'result', ok: false, error: String(e?.message ?? e), changed: [...changed], text: finalText, costUSD: 0, inputTokens: 0, outputTokens: 0, numTurns: 0, sessionId: null });
  }
  process.exit(0);
}

main();
