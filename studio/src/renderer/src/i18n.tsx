import { type ReactNode, createContext, useContext, useState } from "react";

export type Lang = "zh" | "en";

const STR = {
  newProject: { zh: "新建项目", en: "New Project" },
  search: { zh: "搜索", en: "Search" },
  history: { zh: "历史", en: "History" },
  extensions: { zh: "扩展", en: "Extensions" },
  settings: { zh: "设置", en: "Settings" },
  help: { zh: "帮助", en: "Help" },
  feedback: { zh: "反馈", en: "Feedback" },
  selectProject: { zh: "选择项目…", en: "Select project…" },
  soloMode: { zh: "单点模式", en: "Single Mode" },
  dualMode: { zh: "双向模式", en: "Dual Mode" },
  planReview: { zh: "规划 · 审查", en: "Plan · Review" },
  codeExec: { zh: "写码 · 执行", en: "Code · Execute" },
  connect: { zh: "连接", en: "Connect" },
  connecting: { zh: "连接中…", en: "Connecting…" },
  connected: { zh: "已连接", en: "Connected" },
  disconnect: { zh: "断开", en: "Disconnect" },
  methodApp: { zh: "App 登录", en: "App login" },
  methodKey: { zh: "API Key", en: "API Key" },
  modelDefault: { zh: "默认", en: "Default" },
  modelRefresh: { zh: "刷新模型列表", en: "Refresh models" },
  you: { zh: "你", en: "You" },
  system: { zh: "系统", en: "System" },
  thinking: { zh: "思考中", en: "Thinking" },
  executing: { zh: "执行中…", en: "Executing…" },
  tabChat: { zh: "对话", en: "Chat" },
  tabPreview: { zh: "预览", en: "Preview" },
  livePreview: { zh: "Live Preview", en: "Live Preview" },
  noPreview: { zh: "暂无可预览的页面", en: "Nothing to preview yet" },
  noPreviewSub: {
    zh: "当项目里出现 index.html（例如 Codex 生成网页后），这里会自动显示运行效果。",
    en: "When an index.html appears (e.g. after Codex builds a page), it renders here.",
  },
  interjectHint: { zh: "运行中 · 可随时输入「插话」给当前任务追加指令", en: "Running · type anytime to add a follow-up instruction" },
  selectFolderTitle: { zh: "先选一个项目文件夹", en: "Pick a project folder first" },
  selectFolderSub: { zh: "点顶部「选择项目」。选好后即可开始。", en: "Click “Select project” at the top to begin." },
  claudeTitleSolo: { zh: "说说你想做什么", en: "Tell Claude what you want" },
  claudeTitleCollab: { zh: "描述你想做的东西", en: "Describe what you want to build" },
  claudeSubSolo: {
    zh: "Claude 负责规划/审查，Codex 负责写码。切到「双向」可让两者自动协作。",
    en: "Claude plans/reviews; Codex writes code. Switch to Dual Mode for auto collaboration.",
  },
  claudeSubCollab: {
    zh: "回车后 Claude 规划 → Codex 自动执行 → Claude 审查，全程自动。",
    en: "On Enter: Claude plans → Codex executes → Claude reviews — fully automatic.",
  },
  codexTitle: { zh: "直接和 Codex 对话", en: "Chat directly with Codex" },
  codexSub: { zh: "让 Codex 帮你写代码、改文件。", en: "Ask Codex to write code or edit files." },
  codexTitleCollab: { zh: "Codex 执行区", en: "Codex execution" },
  codexSubCollab: { zh: "Claude 规划后，Codex 会在这里自动执行。", en: "After Claude plans, Codex executes here automatically." },
  phPickFolder: { zh: "先选项目文件夹…", en: "Select a project folder first…" },
  phConnectMaster: { zh: "请先连接左栏（Master）…", en: "Connect the Master lane first…" },
  phConnectSlave: { zh: "请先连接右栏（Slave）…", en: "Connect the Slave lane first…" },
  phConnectBoth: { zh: "请先连接左右两栏…", en: "Connect both lanes first…" },
  phCollab: { zh: "描述你想做的，回车后左右两栏自动协作…", en: "Describe your goal; press Enter for auto collaboration…" },
  phMaster: { zh: "和左栏聊聊你想做什么…（Enter 发送）", en: "Tell the Master lane what you want… (Enter to send)" },
  phSlave: { zh: "让右栏帮你写代码、改文件…（Enter 发送）", en: "Ask the Slave lane to code or edit files… (Enter to send)" },
  // ---- history & search ----
  explorer: { zh: "工作区", en: "Workspace" },
  historyTitle: { zh: "历史对话", en: "History" },
  historySub: { zh: "你的对话会自动保存，可随时回看或继续。", en: "Conversations are auto-saved — revisit or continue anytime." },
  searchTitle: { zh: "搜索", en: "Search" },
  searchPlaceholder: { zh: "搜索所有对话内容…", en: "Search across all conversations…" },
  searchHintEmpty: { zh: "输入关键词，搜索所有对话里的消息。", en: "Type a keyword to search every conversation." },
  scopeCurrent: { zh: "当前对话", en: "Current" },
  scopeAll: { zh: "全部历史", en: "All history" },
  noHistory: { zh: "还没有历史对话", en: "No conversations yet" },
  noHistorySub: { zh: "开始一段对话后，会自动保存在这里。", en: "Start chatting and it will be saved here." },
  noResults: { zh: "没有匹配的结果", en: "No matches found" },
  selectSessionHint: { zh: "从左侧选择一段对话查看", en: "Pick a conversation on the left to view" },
  resume: { zh: "继续对话", en: "Continue" },
  rename: { zh: "重命名", en: "Rename" },
  remove: { zh: "删除", en: "Delete" },
  confirmDelete: { zh: "确定删除这段对话？此操作不可撤销。", en: "Delete this conversation? This cannot be undone." },
  soloBadge: { zh: "单点", en: "Solo" },
  dualBadge: { zh: "双向", en: "Dual" },
  msgsUnit: { zh: "条消息", en: "messages" },
  grpToday: { zh: "今天", en: "Today" },
  grpYesterday: { zh: "昨天", en: "Yesterday" },
  grpWeek: { zh: "本周", en: "This week" },
  grpEarlier: { zh: "更早", en: "Earlier" },
  resultsUnit: { zh: "条结果", en: "results" },
  roleYou: { zh: "你", en: "You" },
  // ---- settings ----
  settingsTitle: { zh: "设置", en: "Settings" },
  settingsSub: { zh: "偏好会自动保存在本机。", en: "Preferences are saved locally on this machine." },
  secAppearance: { zh: "外观", en: "Appearance" },
  secAppearanceSub: { zh: "界面配色。", en: "Interface color scheme." },
  themeSystem: { zh: "跟随系统", en: "System" },
  themeLight: { zh: "浅色", en: "Light" },
  themeDark: { zh: "深色", en: "Dark" },
  secProxy: { zh: "代理", en: "Proxy" },
  secProxySub: {
    zh: "设置后，Claude 与 Codex 的所有请求都会走此代理。",
    en: "Once set, all Claude and Codex requests go through this proxy.",
  },
  proxySystem: { zh: "跟随系统", en: "System" },
  proxySystemHint: { zh: "使用系统/终端已设置的代理环境变量。", en: "Use the proxy env vars already set by the OS/shell." },
  proxyCustom: { zh: "自定义", en: "Custom" },
  proxyCustomHint: { zh: "手动指定代理地址（HTTP/HTTPS）。", en: "Specify a proxy address (HTTP/HTTPS)." },
  proxyNone: { zh: "不使用", en: "None" },
  proxyNoneHint: { zh: "直连，不走任何代理。", en: "Direct connection, no proxy." },
  proxyUrlLabel: { zh: "代理地址", en: "Proxy URL" },
  proxyApplyNote: { zh: "更改下一次请求即生效，无需重启。", en: "Applies on the next request — no restart needed." },
  proxyScopeLabel: { zh: "作用范围", en: "Scope" },
  scopeMaster: { zh: "仅 Master（左栏）", en: "Master only (left)" },
  scopeSlave: { zh: "仅 Slave（右栏）", en: "Slave only (right)" },
  scopeBoth: { zh: "全部", en: "Both" },
  // ---- backend / api key ----
  apiKeySet: { zh: "Key 已配置", en: "Key set" },
  apiKeyEdit: { zh: "点击修改 API Key", en: "Click to edit API key" },
  // ---- history search ----
  historySearchPh: { zh: "搜索历史对话内容…", en: "Search conversation content…" },
} as const;

type Key = keyof typeof STR;

interface Ctx {
  lang: Lang;
  t: (k: Key) => string;
  toggle: () => void;
}
const LangContext = createContext<Ctx>({ lang: "zh", t: (k) => STR[k].zh, toggle: () => {} });

export function LangProvider({ children }: { children: ReactNode }) {
  const [lang, setLang] = useState<Lang>("zh");
  const t = (k: Key) => STR[k][lang];
  return (
    <LangContext.Provider value={{ lang, t, toggle: () => setLang((l) => (l === "zh" ? "en" : "zh")) }}>
      {children}
    </LangContext.Provider>
  );
}

export const useLang = () => useContext(LangContext);
