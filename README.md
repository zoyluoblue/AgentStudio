<p align="center">
  <img src="assets/logo.svg" width="120" alt="AgentStudio logo" />
</p>

<h1 align="center">AgentStudio</h1>

<p align="center">
  <b>Two AI agents in one clean desktop studio — one plans &amp; reviews, one writes the code.</b><br/>
  Describe what you want in plain language; watch Claude, Codex (and DeepSeek) build it for you. No terminal required.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-2E6BFF.svg" alt="License: Apache 2.0" /></a>
  <img src="https://img.shields.io/badge/platform-macOS-111?logo=apple&logoColor=white" alt="macOS" />
  <img src="https://img.shields.io/badge/Electron-42-47848F?logo=electron&logoColor=white" alt="Electron" />
  <img src="https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=white" alt="React" />
  <img src="https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white" alt="TypeScript" />
  <img src="https://img.shields.io/badge/PRs-welcome-2E7D32.svg" alt="PRs welcome" />
</p>

<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="https://github.com/zoyluoblue/AgentStudio/wiki">Wiki</a>
</p>

<p align="center">
  <img src="assets/screenshot-collab.png" width="860" alt="AgentStudio — dual-lane collaboration" />
</p>

---

## What is AgentStudio?

AgentStudio is a macOS desktop app that puts two top coding AIs side by side, each with a clear job:

- **Master lane — plan &amp; review.** Understands your goal, breaks it into a short plan, and reviews the resulting code for quality.
- **Slave lane — write &amp; execute.** Actually creates and edits files in your project to make it real.

The problem it solves: regular people have ideas, but "get an AI to build it for me" usually means opening a terminal, configuring environments, and reading walls of red error text. AgentStudio folds all of that into a friendly, chat-like window — **describe → it builds → preview the result.**

Each lane can run **Claude**, **Codex**, or **DeepSeek**, mixed and matched however you like.

## Highlights

- 🤝 **Plan → code → review, fully automatic.** In Dual mode the two lanes collaborate on their own — no buttons to press.
- 💬 **Interject anytime.** Type while it's running to add or correct instructions mid-task.
- 👀 **Live preview.** Built web pages render in an embedded browser the moment they're written.
- 🧠 **Built-in memory that every model shares.** A two-tier memory (your notes + auto-learned facts) is injected into **all** backends, so Claude, Codex, and DeepSeek stay on the same page across sessions — and it's isolated from your machine's own CLI memory.
- 🔌 **Connect your way.** Per-backend **App login** (OAuth) **or API key**, with one-click connect/disconnect.
- 🎛 **Pick any model.** Real, auto-updating model lists per backend (Opus 4.8 / Sonnet 4.6 / Haiku … for Claude; GPT-5.5 / 5.4 … for Codex from its own cache; live list for DeepSeek).
- 🌓 **Polished &amp; bilingual.** Light/dark themes, English/中文 UI, conversation history with full-text search, and per-lane proxy control.
- 🍎 **Native feel.** Pick a folder, say a sentence, go. No terminal.

## How it works

Switch modes at the top of the window:

**Solo mode** — chat with each lane independently (left and right are two separate conversations). Use it to drive one AI at a time.

**Dual mode** — give one goal and the lanes run the whole loop themselves:

```
You: "Build a dark-mode to-do web page"
      │
      ▼
  Claude (plan) ─▶ Codex (write files) ─▶ Claude (review the diff)
                         ▲                          │
                         └──── revise (up to 3×) ◀──┘
                                                    │
                                                    ▼
                                                 ✅ done
```

No clicks required end to end — and you can type an interjection at any moment to steer it.

## Memory

AgentStudio keeps its **own** memory, shared by every backend and kept separate from the machine's native CLI memory (Codex's cross-session `memories` is turned off for AgentStudio runs). Two tiers, each scoped **global** (all projects) or **project** (stored in `<project>/.agentstudio/`, so it travels with the repo and is versionable):

- **Manual memory** — what you write yourself, plus anything you save with a trigger phrase in chat: `记住 / 别忘了 / remember / don't forget / note that …`.
- **Auto memory** — silently summarized from finished conversations (Codex/Claude-Code style), then injected into the next runs. Editable, with one-click **Tidy** (dedup/compress) and **Clear**.

<p align="center">
  <img src="assets/screenshot-memory.png" width="820" alt="AgentStudio — shared memory" />
</p>

## Backends &amp; connection

| Backend | Typical role | Connect via |
| --- | --- | --- |
| **Claude** | plan · review (or code) | App login (`claude` CLI / subscription) **or** Anthropic API key |
| **Codex** | code · execute | App login (`codex` CLI / ChatGPT) **or** OpenAI API key |
| **DeepSeek** | plan or write (text/whole-file) | DeepSeek API key |

Any lane can use any backend. App-login keeps your normal subscription; API-key mode injects the key into that backend only.

## Quick start

**Prerequisites**

- macOS, Node.js 18+ and npm.
- For **App login** backends: the [`claude`](https://claude.com/claude-code) and/or [`codex`](https://developers.openai.com/codex/cli) CLIs installed and logged in.
- For **API-key** backends: an Anthropic / OpenAI / DeepSeek key (entered in the app).

**Run from source**

```bash
git clone https://github.com/zoyluoblue/AgentStudio.git
cd AgentStudio/studio
npm install
npm run dev        # launch in development
```

**Build a double-clickable app (.dmg)**

```bash
npm run dist       # outputs to studio/release/
```

Then: pick a project folder → connect a backend in each lane → choose a mode → describe what you want.

## Project structure

```
AgentStudio/
├─ assets/                 # logo + screenshots
├─ LICENSE                 # Apache-2.0
└─ studio/
   ├─ electron-builder.yml # packaging config (macOS dmg)
   └─ src/
      ├─ main/             # Electron main: orchestration, CLI drivers, memory, settings, auth
      ├─ preload/          # contextBridge → window.studio API
      ├─ renderer/         # React + Tailwind UI
      └─ shared/           # IPC channel + type contracts
```

## Tech stack

Electron 42 · React 19 · TypeScript 5 · Tailwind CSS · `electron-vite`. The engine drives the official CLIs — `claude -p` (structured, read-only planning/review) and `codex exec --json` (real file edits, resumable sessions) — and calls DeepSeek over its OpenAI-compatible HTTP API. Code changes are reviewed via snapshot-based content diffs.

## Documentation

Full guides live in the **[Wiki](https://github.com/zoyluoblue/AgentStudio/wiki)** — getting started, concepts, backends &amp; connection, the memory system, settings &amp; proxy, and troubleshooting.

## Contributing

Issues and PRs are welcome. Please run `npm run typecheck` (in `studio/`) before opening a PR, and keep changes focused. For larger features, open an issue first to discuss.

## License

[Apache License 2.0](LICENSE) © ZoyLuo.

## Acknowledgements

Built on [Claude Code](https://claude.com/claude-code), [OpenAI Codex](https://developers.openai.com/codex), and [DeepSeek](https://deepseek.com). UI inspired by the craft of Linear &amp; Raycast.
