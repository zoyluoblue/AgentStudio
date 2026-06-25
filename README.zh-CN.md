<p align="center">
  <img src="assets/logo.svg" width="120" alt="AgentStudio logo —— macOS 上的 AI 编程智能体" />
</p>

<h1 align="center">AgentStudio</h1>

<p align="center">
  <b>Mac 上的 AI 编程智能体 —— 说出想做什么,看两个 AI 替你做出来。</b><br/>
  两个智能体并排协作:一个(Claude)负责规划与审查,一个(Codex)负责写代码。
  用大白话做出应用、网页与脚本 —— 无需开终端。
  Claude · Codex · DeepSeek,App 登录或自带 API Key 皆可。
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
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="https://github.com/zoyluoblue/AgentStudio/wiki">Wiki</a>
</p>

<p align="center">
  <a href="#这是什么">这是什么</a> ·
  <a href="#适用人群">适用人群</a> ·
  <a href="#功能亮点">功能亮点</a> ·
  <a href="#怎么用">怎么用</a> ·
  <a href="#与同类工具有何不同">对比</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#常见问题">常见问题</a>
</p>

<p align="center">
  <img src="assets/screenshot-collab.png" width="860" alt="AgentStudio 截图 —— 两个 AI 编程智能体(Claude 与 Codex)在 macOS 上双栏协作" />
</p>

---

## 这是什么

**AgentStudio 是一个免费、开源的 macOS 应用,既能「用 AI 写代码」,也是无代码 / vibe coding 的 App 构建器** —— 它把两个 AI 编程智能体并排放在一起协作:一栏(默认 **Claude**)负责规划与审查,另一栏(默认 **Codex**)在你的项目里真正新建、修改文件。你只要用中文或英文说出想做什么,AgentStudio 就把它变成能跑的代码 —— **应用、网页、脚本、小游戏** —— 全程无需开终端、配环境、看一堆黑底白字的报错。

简单说,AgentStudio 就是 **Claude Code 与 Codex 的图形界面(GUI)**,把「让 AI 帮我做个东西」变成 **描述 → 自动构建 → 直接预览**。每一栏还能切到 **DeepSeek**;连接方式可选 **App 登录**(沿用你已有的 Claude / Codex 订阅)或你自己的 **API Key**。

- **Master 栏 —— 规划 / 审查。** 规划与审查智能体听懂你的目标,拆成简短计划,并在写完后审查代码、把关质量。
- **Slave 栏 —— 写码 / 执行。** 构建与执行智能体在你的项目里真正新建、修改文件,把想法实现出来。

它既是面向开发者的**多智能体结对编程**闭环,也是面向普通人的**无代码 / vibe coding(描述即生成)**造物工作台 —— 一个窗口,两种用法。

## 适用人群

AgentStudio 既是面向普通人的无代码 / vibe coding App 构建器,也是面向开发者的 AI 结对编程工作台。

- **不写代码的人 / 创作者**:想做个网页、落地页、个人主页、待办应用或小工具,只靠"说出来"就能完成。
- **开发者**:想要**规划 → 构建 → 审查**的双智能体闭环 + 共享记忆,而不是盯着一个终端 CLI 来回操作。
- **Claude Code / Codex 用户**:更想用一个干净的桌面 GUI(带实时预览)来驱动已有订阅。
- **正在比较 AI 编程工具的人**:想在同一个窗口里同时用上 Claude、Codex、DeepSeek,按任务自由搭配。

## 功能亮点

- 🤝 **规划 → 写码 → 审查,全自动。** 双向模式下两个智能体自动协作,不用点任何按钮。
- 💬 **随时插话。** 运行过程中随时打字,追加或纠正指令。
- 👀 **实时预览。** 做出来的网页一写完就在内嵌浏览器里渲染。
- 🧠 **内置记忆,所有模型共享。** 两层记忆(你的手写笔记 + 自动概括的事实)会注入到**所有**后端,让 Claude / Codex / DeepSeek 跨会话保持一致 —— 并且与本机 CLI 自带的记忆**相互隔离**。
- 🔌 **连接方式自选。** 每个后端可用 **App 登录**(OAuth / 订阅) **或 API Key**,一键连接 / 断开。
- 🎛 **模型任选。** 每个后端真实、自动更新的模型列表(Claude 的 Opus 4.8 / Sonnet 4.6 / Haiku…;Codex 的 GPT-5.5 / 5.4…;DeepSeek 在线拉取)。
- 🌓 **精致且双语。** 浅色/深色主题、中英文界面、带全文搜索的历史记录、按栏的代理控制。
- 🔒 **本地优先、隐私安全。** 你的提示词与 API Key 直接从你的 Mac 发往你选择的服务商 —— 不经过我们、无任何追踪。
- 🍎 **原生体验,告别终端。** 选个文件夹、说句话就能开始。

## 怎么用

在窗口顶部切换模式:

**单点模式** —— 左右两栏是两条独立对话,分别使唤某一个 AI。

**双向模式** —— 你只给一个目标,两个智能体自己跑完整个闭环:

```
你:「做一个深色主题的待办清单网页」
      │
      ▼
  Claude(规划)─▶ Codex(写文件)─▶ Claude(审查 diff)
                       ▲                       │
                       └──── 修订(最多 3 轮)◀──┘
                                               │
                                               ▼
                                            ✅ 完成
```

全程无需点击,且任何时刻都能打字插话来纠偏。

## 与同类工具有何不同

| | AgentStudio | 终端 CLI(Claude Code / Codex) | AI IDE 插件(Copilot / Cursor) |
| --- | --- | --- | --- |
| 交互方式 | 干净的桌面 GUI,无需终端 | 命令行 | 在代码编辑器里 |
| 智能体 | **两个**分工智能体,共同规划、构建、审查 | 每次一个智能体 | 一个助手 |
| 模型 | Claude **+** Codex **+** DeepSeek,按栏混搭 | 每个工具一家厂商 | 多为单一厂商 |
| 记忆 | 跨所有模型共享,全局 + 按项目 | 各工具独立 | 限于编辑器 |
| 面向 | 普通人**与**开发者 | 开发者 | 开发者 |

AgentStudio 不是要取代这些工具,而是去**编排**它们。App 登录会复用你已有的 Claude / Codex 订阅,你已经付费的额度照用。

## 记忆

AgentStudio 维护**自己的**一套记忆,被每个后端共享,并与本机 CLI 原生记忆隔离(AgentStudio 运行时关闭了 Codex 的跨会话 `memories`)。两层记忆,各自可作用于 **全局**(所有项目)或 **项目**(存在 `<项目>/.agentstudio/`,跟着仓库走、可版本化):

- **手写记忆** —— 你自己写的,外加在对话框用触发词存下的:`记住 / 别忘了 / remember / don't forget / note that …`。
- **自动记忆** —— 对话结束后无声概括(对齐 Codex / Claude Code 的做法),再注入到后续运行。可编辑,并支持一键**整理**(去重压缩)与**清空**。

<p align="center">
  <img src="assets/screenshot-memory.png" width="820" alt="AgentStudio 截图 —— 两层共享记忆,注入到 Claude、Codex 与 DeepSeek" />
</p>

## 后端与连接

| 后端 | 典型角色 | 连接方式 |
| --- | --- | --- |
| **Claude** | 规划 · 审查(也可写码) | App 登录(`claude` CLI / 订阅) **或** Anthropic API Key |
| **Codex** | 写码 · 执行 | App 登录(`codex` CLI / ChatGPT) **或** OpenAI API Key |
| **DeepSeek** | 规划或写码(文本 / 整文件) | DeepSeek API Key |

任意一栏可用任意后端。App 登录沿用你的订阅;API Key 模式只把 key 注入到对应后端。

## 快速开始

**前置条件**

- macOS、Node.js 20+ 与 npm。
- 使用 **App 登录** 的后端:需先安装并登录 [`claude`](https://claude.com/claude-code) 和 / 或 [`codex`](https://developers.openai.com/codex/cli) 命令行。
- 使用 **API Key** 的后端:准备好 Anthropic / OpenAI / DeepSeek 的密钥(在应用内填写)。

**源码运行**

```bash
git clone https://github.com/zoyluoblue/AgentStudio.git
cd AgentStudio/studio
npm install
npm run dev        # 开发模式启动
```

**打包成可双击的应用(.dmg)**

```bash
npm run dist       # 产物在 studio/release/
```

随后:选项目文件夹 → 在每栏连接一个后端 → 选模式 → 描述你想做的东西。

## 常见问题

### 一句话介绍 AgentStudio?
一个免费、开源的 macOS 桌面应用:两个 AI 智能体 —— Claude(规划与审查)与 Codex(写代码)—— 根据你的大白话描述替你把软件做出来,全程无需终端。

### AgentStudio 免费、开源吗?
是。AgentStudio 以 [Apache License 2.0](LICENSE) 开源。应用本身免费,你只为自己的 AI 用量付费(Claude / Codex 订阅,或按量计费的 API Key)。

### 不懂代码能用吗?
能。你用中文或英文说出想做什么、选个文件夹,智能体负责动手。开发者也可以随时直接介入文件。

### AgentStudio 是无代码 / vibe coding 工具吗?
是。AgentStudio 就是一个无代码、vibe coding 的 App 构建器:你用大白话描述应用、网页或脚本,两个 AI 智能体替你做出来。开发者也可以随时直接改文件。

### 必须有 API Key 吗?
不一定。用 **App 登录** 可复用你已有的 Claude 或 Codex 订阅(通过官方 CLI);想按量计费,也可填自己的 Anthropic / OpenAI / DeepSeek **API Key**。DeepSeek 仅支持 API Key。

### 支持哪些 AI 模型?
Claude(Opus 4.8 / Sonnet 4.6 / Haiku…)、Codex(GPT-5.x)与 DeepSeek,模型列表真实且自动更新。任意一栏可运行任意模型。

### 支持 Windows / Linux 吗?
暂不支持 —— 目前仅限 macOS。底层 Electron 代码对跨平台友好,欢迎贡献其他平台支持。

### 我的代码和数据安全吗?
安全。AgentStudio 本地优先:你的提示词与 API Key 直接从你的 Mac 发往你选择的服务商(Anthropic / OpenAI / DeepSeek)或本机 CLI 登录态,不经过我们,也没有任何遥测或追踪。

### 它和 Claude Code / Codex CLI 有什么区别?
那些是单智能体的命令行工具。AgentStudio 给它们套上桌面 GUI,让**两个**智能体共同规划、构建、审查,跨所有模型共享同一套记忆,并实时预览成果 —— 无需终端。

### 能用它做什么?
网页、落地页、个人主页、待办与笔记应用、仪表盘、浏览器小游戏、脚本、快速原型 —— 凡是你能描述的都行。

## 目录结构

```
AgentStudio/
├─ assets/                 # logo + 截图
├─ LICENSE                 # Apache-2.0
├─ studio/                 # Electron + React 桌面应用(发布主体)
│  ├─ electron-builder.yml # 打包配置(macOS dmg)
│  └─ src/
│     ├─ main/             # Electron 主进程:编排、CLI 驱动、记忆、设置、鉴权
│     ├─ preload/          # contextBridge → window.studio API
│     ├─ renderer/         # React + Tailwind 界面
│     └─ shared/           # IPC 通道与类型约定
└─ app/                    # 原生 macOS 应用(SwiftUI)—— 开发中
```

## 技术栈

Electron 42 · React 19 · TypeScript 5 · Tailwind CSS · `electron-vite`。引擎驱动官方 CLI —— `claude -p`(结构化、只读的规划/审查)与 `codex exec --json`(真实文件改动、可续接会话)—— 并通过 OpenAI 兼容的 HTTP 接口调用 DeepSeek。代码改动通过快照式内容 diff 交给审查方。另有一个原生 **SwiftUI** macOS 应用正在 `app/` 下开发。

## 文档

完整文档见 **[Wiki](https://github.com/zoyluoblue/AgentStudio/wiki)** —— 快速上手、核心概念、后端与连接、记忆系统、设置与代理、故障排查。

## 参与贡献

欢迎 Issue 与 PR。提 PR 前请在 `studio/` 下运行 `npm run typecheck`,并尽量让改动聚焦。较大的功能请先开 Issue 讨论。

## 许可证

[Apache License 2.0](LICENSE) © ZoyLuo。

## 致谢

基于 [Claude Code](https://claude.com/claude-code)、[OpenAI Codex](https://developers.openai.com/codex) 与 [DeepSeek](https://deepseek.com) 构建。界面取经于 Linear 与 Raycast 的设计质感。
