# AgentConnector

> 让 **Claude Code** 与 **Codex** 自动联动的编排器：Claude 负责顶层架构与详细规划，Codex 负责执行编码任务，两者自动同步进度，无需人工来回搬运。

## 这是什么

AgentConnector 解决一个具体的协作痛点。

在「**Claude Code 做顶层架构 + 详细编码规划，Codex 执行具体编码任务**」的双 Agent 工作流里，两个 Agent 之间没有打通，每推进一步都要人工搬运：

- Claude 规划完 → 人工把任务粘贴给 Codex 执行
- Codex 执行完 → 人工再回头告诉 Claude「好了，审查一下并给出下一段任务」

AgentConnector 的目标是把这个 **规划 → 执行 → 审查 → 再规划** 的循环**自动化**：让 Claude 当「导演」，Codex 当「执行手」，进度在两者之间自动同步流转。

## 解决的问题

| 痛点 | 现状 | AgentConnector 之后 |
|------|------|---------------------|
| 任务交接 | 人工复制 Claude 的规划喂给 Codex | 自动派发 |
| 进度回传 | 人工告诉 Claude「Codex 跑完了」 | 自动回传执行结果 |
| 审查衔接 | 人工触发 Claude 审查并要下一段 | 自动进入审查 → 下一轮 |
| 上下文 | 两边各看各的，靠人脑同步 | 结构化结果在循环内流转 |

## 架构

**「Agent 路由器」MCP server（Node/TS）。** 对上给 Claude（导演）一套**执行器无关**的工具，对下经可插拔 `Executor` 适配器路由到后端。Claude 在自己的会话里**异步**调度执行器、读取结构化结果与 diff、审查后产出下一段规划——整个循环在一个进程内闭环。

- **执行器无关工具面**：加新后端 = 新增一个适配器 spec + 注册一行，工具面与 director skill 零改动。
- **异步 fire-and-poll**：`agent_start` 立即返回 `taskId`，不阻塞导演回合，可并发、可取消。
- **后端**：Codex（`codex exec`，已验证）；Gemini / Grok（适配器已就位，本机 CLI 未安装 → 标记 experimental 并优雅降级）。

详见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 与 [`docs/CONFIG.md`](docs/CONFIG.md)。

## 现状

✅ **全部 4 个 Phase 已完成。** Claude Code 当导演，通过自建 MCP server 异步调度 Codex 执行编码任务，端到端闭环跑通：派发 → 轮询 → 取结构化结果+diff → 审查 → 再派发，全程无人工搬运。已含 git-worktree 隔离、状态持久化与崩溃恢复、会话续跑、并发排队/重试、多后端路由、可观测性与 npm 打包。

测试：**21 个单元测试** + **3 个真实 Codex 端到端冒烟**（`npm run smoke` / `smoke:p2` / `smoke:p3`）全绿。

### 快速开始

```bash
npm install
npm run build           # 产出 dist/
npm test                # 单元测试（argv 构造 + JSONL 解析）
node scripts/smoke.mjs  # 端到端冒烟（会真实跑一次 Codex）
```

仓库已带 `.mcp.json`：在本目录打开 Claude Code 即会自动启动 `agentconnector` server；随后调用 **`agent-director`** skill，把多步需求交给导演循环。

工具一览：`agent_start` · `agent_status` · `agent_result` · `agent_cancel` · `agent_list` · `agent_apply` · `agent_resume` · `agent_review` · `agent_executors` · `agent_stats`（详见 [`docs/CONFIG.md`](docs/CONFIG.md)）。

📖 **完整使用教程**：[`docs/USAGE.md`](docs/USAGE.md)。

## 环境 / 技术栈

- **Codex CLI** 0.130.0
- **Claude Code** 2.1.154
- **Node.js** 25 + **TypeScript**（已选定的实现语言）
- **MCP SDK** `@modelcontextprotocol/sdk` 1.29

## 路线图

- **Phase 0** ✅ 架构与环境探明、实现语言选定（Node/TS）
- **Phase 1** ✅ 垂直切片 MVP：MCP server + 执行器无关工具 + `Executor` 抽象 + `CodexExecutor` + director skill + `.mcp.json`，端到端导演循环跑通
- **Phase 2** ✅ 执行模型硬化：git-worktree 隔离 + `agent_apply`、状态持久化 + 崩溃恢复、`agent_resume` 跨会话续跑、并发排队、自动重试
- **Phase 3** ✅ 多后端：通用 `CliExecutor` 基座 + Codex/Gemini/Grok 适配器 + 可用性检测（工具面 & skill 不变）
- **Phase 4** ✅ 打磨与发布：配置文件、分级/JSON 日志、指标、文档、e2e 冒烟、npm 打包（LICENSE + files allowlist）
