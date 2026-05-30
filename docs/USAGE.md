# AgentConnector 使用教程

> 一句话心智模型：**你跟 Claude Code 说话；Claude 当「导演」，通过 AgentConnector 的 `agent_*` 工具把编码任务派给 Codex 执行、读回结构化结果与 diff、审查后决定下一步。** 你不直接调用工具，而是和 Claude 对话，由它编排。

---

## 1. 前置条件

- **Node.js ≥ 18**（开发机为 25）。
- **Codex CLI** 已安装并**已登录**：终端跑 `codex login`，确认 `codex exec --json -s read-only --skip-git-repo-check "say hi"` 能出 JSONL。
- **Claude Code**（作为导演 + MCP 宿主）。
- 目标项目最好是 **git 仓库**（diff 捕获 / worktree 隔离都依赖 git；非 git 目录会自动降级为「就地、无 diff」）。

---

## 2. 安装与构建

```bash
cd /path/to/AgentConnector
npm install
npm run build          # 产出 dist/（.mcp.json 指向 dist/index.js，必须先 build）
npm test               # 可选：21 个单元测试
```

> 改了 `src/` 后要 **重新 `npm run build`**，并让 Claude Code 重连 server（见 §9）。

---

## 3. 接入 Claude Code

AgentConnector 是一个 stdio MCP server，由 Claude Code 启动。有三种接法：

### A) 在本仓库内用（开箱即用）
仓库已自带 `.mcp.json`。直接在本目录打开 Claude Code，首次会提示信任该 MCP server，允许即可。

### B) 用它编排「另一个项目」（最常见的真实用法）
在**目标项目**根目录建/改 `.mcp.json`，用**绝对路径**指向本仓库的 `dist/index.js`：

```jsonc
{
  "mcpServers": {
    "agentconnector": {
      "command": "node",
      "args": ["/ABS/PATH/AgentConnector/dist/index.js"],
      "env": {
        "AGENTCONNECTOR_DEFAULT_EXECUTOR": "codex",
        "AGENTCONNECTOR_DEFAULT_SANDBOX": "workspace-write"
      }
    }
  }
}
```
在该项目打开 Claude Code —— server 的工作目录就是该项目，任务默认在该项目里执行。

### C) 全局可用（所有项目）
```bash
cd /path/to/AgentConnector && npm i -g .   # 安装 agentconnector 这个 bin
```
然后用户级 MCP 配置里把 `command` 写成 `"agentconnector"`，或用 Claude Code 的 `claude mcp add` 注册。

> **导演 skill**：本仓库的 `.claude/skills/agent-director/SKILL.md` 是「导演 playbook」，仅在本仓库内自动可用。在别的项目里，工具本身（带自描述）也能用 —— 把这个 skill 复制到目标项目的 `.claude/skills/`，或做成插件，体验最佳。

---

## 4. 第一次使用（最小例子）

在已接入的 Claude Code 里，直接用自然语言让 Claude 当导演：

> 「**用 agent-director，把这个需求交给 Codex：给 `src/math.ts` 加一个 `clamp(n, min, max)` 并配单测。做完给我看 diff。**」

Claude 会自动：
1. `agent_start({ prompt: "...", sandbox: "workspace-write" })` → 拿到 `taskId`（立即返回，不卡住）。
2. 间隔轮询 `agent_status({ taskId })` 直到 `done`。
3. `agent_result({ taskId })` → 把 `finalMessage` + `diff` 呈现给你。
4. 你点头后继续下一段，或让它 `agent_review` 再审一遍。

你全程只跟 Claude 对话，不碰工具。

---

## 5. 工具速查表

所有面向执行器的工具都接受可选 `executor`（默认 `codex`）。结果是带 `ok` 字段的 JSON 文本。

| 工具 | 关键参数 | 作用 |
|---|---|---|
| `agent_start` | `prompt`(必), `cwd?`, `sandbox?`, `isolation?`, `model?`, `addDirs?`, `outputSchema?`, `retries?`, `label?` | 派发任务，**立即**返回 `taskId`（异步；满载则排队） |
| `agent_status` | `taskId?`（省略=全局摘要+统计） | 查状态：`queued/running/done/error/canceled` |
| `agent_result` | `taskId`(必), `includeDiff?`=true, `includeEvents?`=false, `maxDiffBytes?` | 终态后取 `finalMessage` / `structuredOutput` / `diff` |
| `agent_cancel` | `taskId`(必), `signal?` | 终止运行中任务（杀整个进程组）/ 丢弃排队任务 |
| `agent_list` | `state?`, `executor?` | 列任务（含上次会话持久化的） |
| `agent_apply` | `taskId`(必) | 把 **worktree 隔离**任务的改动合并回主工作树 |
| `agent_resume` | `prompt`(必), `taskId?` 或 `sessionId?`, `sandbox?`, `model?`, `cwd?` | 续跑此前的会话（保留上下文，跨重启可用） |
| `agent_review` | `instructions?`, `base?`, `uncommitted?`=true, `cwd?` | 让执行器**只读**审查改动，返回结构化 `{summary,findings[],verdict}` |
| `agent_executors` | — | 列出后端及其可用性 / 能力 |
| `agent_stats` | — | 按状态汇总任务计数 |

**默认值**：`executor=codex`、`sandbox=workspace-write`、`isolation=inplace`、`maxConcurrent=4`、`retries=0`。

---

## 6. 常见用法配方

下面给「你对 Claude 说的话」+「Claude 背后大致的工具调用」。

### 6.1 基本委派（会改代码）
> 「把 X 实现了，写在 `workspace-write` 沙箱。」
`agent_start({prompt:"实现 X，含验收标准…", sandbox:"workspace-write"})` → 轮询 → `agent_result`。

### 6.2 只读分析（不改代码）
> 「让 Codex 只读分析一下 `src/` 的循环依赖，别改文件。」
`agent_start({prompt:"…只读分析…", sandbox:"read-only"})`。

### 6.3 worktree 隔离 + 合并（并行安全）
> 「这三个互不相干的小改动并行交给 Codex，各自隔离，做完我逐个审查再合并。」
对每个任务 `agent_start({..., isolation:"worktree"})`（在独立 git worktree 里跑，互不干扰）→ 审查每个 `agent_result.diff` → 满意的 `agent_apply({taskId})` 合并回主树。

### 6.4 独立审查
> 「先让 Codex 审一遍当前未提交的改动。」
`agent_review({uncommitted:true})` → 轮询 → `agent_result.structuredOutput`（`findings[]` + `verdict`）。
或对某个基线分支：`agent_review({base:"main"})`。

### 6.5 续跑（保留上下文）
> 「接着刚才那个任务，让它把边界情况也补上。」
`agent_resume({taskId:"tsk_xxx", prompt:"补充以下边界情况…"})`。
也可用历史 `sessionId` 续跑（跨会话/重启）：`agent_resume({sessionId:"019e…", prompt:"…"})`。

### 6.6 取消 / 查看 / 指标
- 取消：`agent_cancel({taskId})`（会杀掉 Codex 及其子进程整组）。
- 全局概览：`agent_status()`（不带 taskId）→ `{total, queued, byState, tasks[]}`。
- 计数：`agent_stats()`。

### 6.7 跨会话（持久化）
任务快照写在 `<项目>/.agentconnector/tasks/`（已 gitignore）。重启 Claude Code / server 后：
- `agent_list()` 仍能看到历史任务；上次「运行中」的会被标记为 `error: interrupted by server restart`。
- 凭历史 `sessionId` 仍可 `agent_resume` 继续。

---

## 7. 配置

优先级：**环境变量 > 配置文件 > 内置默认**。配置文件：`$AGENTCONNECTOR_CONFIG` 或 `<cwd>/.agentconnector.json`。

常用项（完整见 [`CONFIG.md`](CONFIG.md)）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `AGENTCONNECTOR_DEFAULT_SANDBOX` | `workspace-write` | 默认沙箱（`read-only`/`workspace-write`/`danger-full-access`） |
| `AGENTCONNECTOR_ISOLATION` | `inplace` | 默认隔离（`inplace`/`worktree`） |
| `AGENTCONNECTOR_MAX_CONCURRENT` | `4` | 并发上限，超出排队 |
| `AGENTCONNECTOR_MAX_RETRIES` | `0` | 失败自动重试次数（指数退避） |
| `AGENTCONNECTOR_STATE_DIR` | `<cwd>/.agentconnector` | 持久化目录 |
| `AGENTCONNECTOR_LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error` |
| `AGENTCONNECTOR_LOG_JSON` | 关 | `1` → 结构化 JSON 日志（stderr） |
| `AGENTCONNECTOR_CODEX_BIN` | `codex` | Codex CLI 路径 |

配置文件示例 `<项目>/.agentconnector.json`：
```json
{ "defaultSandbox": "read-only", "maxConcurrent": 2, "logLevel": "debug" }
```

---

## 8. 不经 Claude，直接验证 / 调试 server

```bash
npm run smoke      # 端到端：Codex 生命周期（真实跑一次 Codex）
npm run smoke:p2   # worktree+apply + resume
npm run smoke:p3   # 多后端可用性（无模型调用，快）
npm run probe      # 重新抓 Codex --json 事件格式（只读、ephemeral）
```
也可用 MCP Inspector 连 `node dist/index.js` 手动调 `tools/list` 和各工具。

---

## 9. 排错 FAQ

- **Claude Code 里看不到这些工具** → 确认已 `npm run build`（`dist/` 存在）、`.mcp.json` 路径正确、并在 Claude Code 里信任了该 server（`/mcp` 可查看/重连；改完代码需重连或重启）。
- **`executor 'codex' is not available`** → `codex` 不在 PATH 或未登录。跑 `codex login`，或用 `AGENTCONNECTOR_CODEX_BIN` 指定绝对路径。
- **`executor 'gemini'/'grok' is not available`** → 预期行为：这两个后端是 experimental，本机没装对应 CLI，会优雅报错。用 `codex`。
- **任务卡在 `running`** → 用 `agent_status` 看 `recentEvents` / `agent_result` 看 `stderrTail`；必要时 `agent_cancel`。我们已强制 `approval_policy=never`，正常不会卡审批。
- **diff 为空但确实改了** → 新建文件在 `diff.files` 里是未跟踪 `??`，`patch` 可能为空；直接读文件即可。worktree 任务记得用 `agent_apply` 合并。
- **想看详细日志** → `AGENTCONNECTOR_LOG_LEVEL=debug`（日志只走 stderr，不污染 MCP 通道）。
- **沙箱/安全** → 默认 `workspace-write`（只能改工作区）；分析类任务用 `read-only`；`danger-full-access` 谨慎。我们永远显式传 `-s`，不继承你 `~/.codex/config.toml` 的全局设置。

---

## 10. 一个完整实战示例（对话脚本）

```
你：用 agent-director。需求：给 utils 加一个 debounce(fn, ms)，配 3 个单测，TypeScript。
    workspace-write，做完给我看 diff。

Claude（导演）：
  → agent_start({ prompt:"实现 debounce(fn,ms) 于 src/utils/debounce.ts，
       附 test/debounce.test.ts（3 个用例：基本去抖/连续调用只跑最后一次/可取消），
       用 vitest 风格。验收：npm test 通过。", sandbox:"workspace-write" })
  ← { taskId:"tsk_ab12cd34", state:"running" }
  （间隔轮询）→ agent_status({taskId}) … running → done
  → agent_result({taskId})
  ← finalMessage + diff（新增 2 个文件）
  Claude 把变更文件清单 + patch 摘要贴给你，并说「建议跑一次测试确认」。

你：让 Codex 自己审一遍，再把测试跑了。

Claude：
  → agent_review({uncommitted:true})  → 轮询 → 取 structuredOutput（verdict: approve_with_nits，1 条 minor）
  把审查结论转述给你；如需修，→ 再 agent_start 一个「按审查意见修订」的小任务。
```

到此你已掌握：接入 → 委派 → 轮询 → 审查 → 续跑 → 合并 的完整闭环。

---

## 11. 桌面 App（GUI · 你当导演）

除了「Claude 当导演」的 MCP 路线，还有一个 **Electron 桌面控制台**（`app/`），让你用按钮直接派发/监控/审查/合并 —— 同一个引擎，人当导演。

```bash
cd app
npm install
npm run dev          # 开发模式：弹出窗口 + 热更新
```

三栏界面：左=任务列表（带状态/筛选），中=任务详情（实时活动流 + diff2html 差异 + 取消/续跑/合并按钮），右=新建任务（执行器/沙箱/隔离/重试 + 派发 + 审查）。顶栏切项目、深/浅色、设置（⌘,）；任务完成有系统通知。

**打包成可直接安装的 .app（自用）**：
```bash
npm run dist         # electron-vite build + electron-builder(--dir) + 自动 ad-hoc 签名
# 产物：app/release/mac-arm64/AgentConnector.app —— 拖进「应用程序」即可
```
- Apple Silicon 上自建 app 必须有签名才能启动；`postdist` 已自动做 **ad-hoc 签名**。首次打开右键「打开」一次即可。
- 想做 `.dmg` 或分发给别人不弹警告：`npm run dist:dmg` 并配置 Developer ID 签名 + 公证（见 `app/electron-builder.yml`）。
- 日常自用其实直接 `npm run dev` 最省事，无需打包。
