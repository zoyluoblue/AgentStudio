<p align="center">
  <img src="assets/logo.svg" width="120" alt="AgentStudio logo — AI coding agents for macOS" />
</p>

<h1 align="center">AgentStudio</h1>

<p align="center">
  <b>AI coding agents on your Mac — describe it, and watch two AIs build it.</b><br/>
  Two agents work side by side: one (Claude) plans &amp; reviews, the other (Codex) writes the code.
  Build apps, websites &amp; scripts in plain language — no terminal needed.
  Claude · Codex · DeepSeek, via App login or your own API key.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-2E6BFF.svg" alt="License: Apache 2.0" /></a>
  <a href="https://github.com/zoyluoblue/AgentStudio/stargazers"><img src="https://img.shields.io/github/stars/zoyluoblue/AgentStudio?style=flat&color=2E6BFF" alt="GitHub stars" /></a>
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
  <a href="#what-is-agentstudio">What is it</a> ·
  <a href="#who-is-it-for">Use cases</a> ·
  <a href="#features">Features</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#how-is-agentstudio-different">Comparison</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#faq">FAQ</a>
</p>

<p align="center">
  <img src="assets/screenshot-collab.png" width="860" alt="AgentStudio screenshot — two AI coding agents (Claude and Codex) collaborating in dual-lane mode on macOS" />
</p>

---

## What is AgentStudio?

**AgentStudio is a free, open-source macOS app for AI coding — and a no-code, vibe-coding app builder** that runs two AI coding agents (Claude + Codex) side by side and lets them collaborate. One lane (by default **Claude**) plans the work and reviews the result; the other (by default **Codex**) actually writes and edits the files in your project. You describe what you want in plain English or 中文, and AgentStudio turns it into working code — **apps, websites, scripts, small games** — without a terminal, environment setup, or reading walls of red error text.

In short, AgentStudio is a friendly **GUI for Claude Code and Codex** that turns "get an AI to build it for me" into **describe → it builds → preview the result.** Each lane can also run **DeepSeek**, and you connect with either an existing **App login** (your Claude / Codex subscription) or your own **API key**.

- **Master lane — plan &amp; review.** The planner/reviewer agent understands your goal, breaks it into a short plan, and checks the resulting code for quality.
- **Slave lane — write &amp; execute.** The builder/executor agent creates and edits real files in your project to make the idea work.

It's an AI pair-programming and **no-code / vibe-coding** workbench in one: developers get an orchestrated multi-agent loop; non-coders get an app builder that needs no command line.

## Who is it for

AgentStudio works as a no-code, vibe-coding app builder for non-coders and as an AI pair-programming workbench for developers.

- **Non-coders & makers** who want to build a website, landing page, portfolio, to-do app, or small tool by just describing it.
- **Developers** who want a two-agent **plan → build → review** loop with shared memory, instead of babysitting a single terminal CLI.
- **Claude Code / Codex users** who'd rather drive their existing subscription from a clean desktop GUI with live preview.
- **Anyone comparing AI coding tools** who wants multiple models (Claude, Codex, DeepSeek) in one window, mixed and matched per task.

## Features

- 🤝 **Plan → code → review, fully automatic.** In Dual mode the two agents collaborate on their own — no buttons to press.
- 💬 **Interject anytime.** Type while it's running to add or correct instructions mid-task.
- 👀 **Live preview.** Web pages render in an embedded browser the moment they're written.
- 🧠 **Built-in memory that every model shares.** A two-tier memory (your notes + auto-learned facts) is injected into **all** backends, so Claude, Codex, and DeepSeek stay on the same page across sessions — isolated from your machine's own CLI memory.
- 🔌 **Connect your way.** Per-backend **App login** (OAuth / subscription) **or API key**, with one-click connect/disconnect.
- 🎛 **Pick any model.** Real, auto-updating model lists per backend (Opus 4.8 / Sonnet 4.6 / Haiku … for Claude; GPT-5.5 / 5.4 … for Codex; live list for DeepSeek).
- 🌓 **Polished &amp; bilingual.** Light/dark themes, English/中文 UI, conversation history with full-text search, and per-lane proxy control.
- 🔒 **Local-first &amp; private.** Your prompts and API keys go straight from your Mac to the provider you chose — nothing is sent to us, and there's no tracking.
- 🍎 **Native feel, no terminal.** Pick a folder, say a sentence, go.

## How it works

Switch modes at the top of the window:

**Solo mode** — chat with each agent independently (left and right are two separate conversations). Use it to drive one AI at a time.

**Dual mode** — give one goal and the two agents run the whole loop themselves:

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

## How is AgentStudio different?

| | AgentStudio | Terminal CLIs (Claude Code / Codex) | AI IDE plugins (Copilot / Cursor) |
| --- | --- | --- | --- |
| Interface | Clean desktop GUI, no terminal | Command line | Inside a code editor |
| Agents | **Two** specialized agents that plan, build & review together | One agent per session | One assistant |
| Models | Claude **+** Codex **+** DeepSeek, mixed per lane | One vendor per tool | Mostly one vendor |
| Memory | Shared across all models, global + per-project | Per-tool, separate | Editor-scoped |
| Built for | Non-coders **and** developers | Developers | Developers |

AgentStudio doesn't replace these tools — it **orchestrates** them. App login reuses your existing Claude / Codex subscription, so you keep the plans you already pay for.

## Memory

AgentStudio keeps its **own** memory, shared by every backend and kept separate from the machine's native CLI memory (Codex's cross-session `memories` is turned off for AgentStudio runs). Two tiers, each scoped **global** (all projects) or **project** (stored in `<project>/.agentstudio/`, so it travels with the repo and is versionable):

- **Manual memory** — what you write yourself, plus anything you save with a trigger phrase in chat: `记住 / 别忘了 / remember / don't forget / note that …`.
- **Auto memory** — silently summarized from finished conversations (Codex / Claude-Code style), then injected into the next runs. Editable, with one-click **Tidy** (dedup/compress) and **Clear**.

<p align="center">
  <img src="assets/screenshot-memory.png" width="820" alt="AgentStudio screenshot — two-tier shared memory injected into Claude, Codex and DeepSeek" />
</p>

## Backends &amp; connection

| Backend | Typical role | Connect via |
| --- | --- | --- |
| **Claude** | plan · review (or code) | App login (`claude` CLI / subscription) **or** Anthropic API key |
| **Codex** | code · execute | App login (`codex` CLI / ChatGPT) **or** OpenAI API key |
| **DeepSeek** | plan or write (text / whole-file) | DeepSeek API key |

Any lane can use any backend. App login keeps your normal subscription; API-key mode injects the key into that backend only.

## Quick start

**Prerequisites**

- macOS, Node.js 20+ and npm.
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

## FAQ

### What is AgentStudio in one sentence?
A free, open-source macOS desktop app where two AI agents — Claude (plan & review) and Codex (write code) — build software for you from a plain-language description, no terminal required.

### Is AgentStudio free and open source?
Yes. AgentStudio is released under the [Apache License 2.0](LICENSE). The app itself is free; you only pay for your own AI usage (a Claude / Codex subscription, or pay-as-you-go API keys).

### Do I need to know how to code?
No. You describe what you want in plain English or 中文, pick a folder, and the agents do the building. Developers can still drop into the files at any time.

### Is AgentStudio a no-code / vibe coding tool?
Yes. AgentStudio is a no-code, vibe-coding app builder: you describe an app, website, or script in plain language and two AI agents build it for you. Developers can still edit the files directly.

### Do I need an API key?
Not necessarily. With **App login** you reuse your existing Claude or Codex subscription (via the official CLIs). Prefer pay-as-you-go? Use your own Anthropic, OpenAI, or DeepSeek **API key** instead. DeepSeek is API-key only.

### Which AI models does it support?
Claude (Opus 4.8 / Sonnet 4.6 / Haiku …), Codex (GPT-5.x), and DeepSeek — with real, auto-updating model lists. Any lane can run any model.

### Does AgentStudio work on Windows or Linux?
Not yet — AgentStudio is macOS-only today. The Electron codebase is cross-platform-friendly, so contributions toward other platforms are welcome.

### Is my code and data private?
Yes. AgentStudio is local-first: your prompts and API keys go directly from your Mac to the provider you chose (Anthropic / OpenAI / DeepSeek) or your local CLI login. Nothing is sent to us, and there is no telemetry or tracking.

### How is it different from Claude Code or the Codex CLI?
Those are single-agent command-line tools. AgentStudio gives them a desktop GUI, runs **two** agents that plan, build, and review together, shares one memory across all models, and previews the result live — no terminal.

### What can I build with it?
Websites, landing pages, portfolios, to-do and note apps, dashboards, small browser games, scripts, and quick prototypes — anything you can describe.

## Project structure

```
AgentStudio/
├─ assets/                 # logo + screenshots
├─ LICENSE                 # Apache-2.0
├─ studio/                 # Electron + React desktop app (shipping)
│  ├─ electron-builder.yml # packaging config (macOS dmg)
│  └─ src/
│     ├─ main/             # Electron main: orchestration, CLI drivers, memory, settings, auth
│     ├─ preload/          # contextBridge → window.studio API
│     ├─ renderer/         # React + Tailwind UI
│     └─ shared/           # IPC channel + type contracts
└─ app/                    # native macOS app (SwiftUI) — in development
```

## Tech stack

Electron 42 · React 19 · TypeScript 5 · Tailwind CSS · `electron-vite`. The engine drives the official CLIs — `claude -p` (structured, read-only planning/review) and `codex exec --json` (real file edits, resumable sessions) — and calls DeepSeek over its OpenAI-compatible HTTP API. Code changes are reviewed via snapshot-based content diffs. A native **SwiftUI** macOS app is also in development under `app/`.

## Documentation

Full guides live in the **[Wiki](https://github.com/zoyluoblue/AgentStudio/wiki)** — getting started, concepts, backends &amp; connection, the memory system, settings &amp; proxy, and troubleshooting.

## Contributing

Issues and PRs are welcome. Please run `npm run typecheck` (in `studio/`) before opening a PR, and keep changes focused. For larger features, open an issue first to discuss.

## License

[Apache License 2.0](LICENSE) © ZoyLuo.

## Acknowledgements

Built on [Claude Code](https://claude.com/claude-code), [OpenAI Codex](https://developers.openai.com/codex), and [DeepSeek](https://deepseek.com). UI inspired by the craft of Linear &amp; Raycast.
