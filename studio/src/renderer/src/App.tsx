import { useEffect, useState } from "react";
import type { AgentKind, AuthState, BusyState, ChatMessage, Mode, ProjectInfo } from "../../shared/ipc";
import { Composer } from "./components/Composer";
import { Conversation } from "./components/Conversation";
import { LivePreview } from "./components/LivePreview";
import { Sidebar } from "./components/Sidebar";
import { StatusBar } from "./components/StatusBar";
import { Terminal } from "./components/Terminal";
import { TopBar } from "./components/TopBar";

const DISCONNECTED: AuthState = { claude: { connected: false }, codex: { connected: false } };

const CLAUDE_MODELS = [
  { v: "", label: "默认" },
  { v: "claude-opus-4-8", label: "Opus 4.8" },
  { v: "claude-opus-4-8[1m]", label: "Opus 4.8 (1M)" },
  { v: "claude-sonnet-4-6", label: "Sonnet 4.6" },
  { v: "claude-haiku-4-5", label: "Haiku 4.5" },
  { v: "claude-opus-4-7", label: "Opus 4.7 (旧)" },
  { v: "claude-opus-4-7[1m]", label: "Opus 4.7 (1M, 旧)" },
  { v: "claude-opus-4-6", label: "Opus 4.6 (旧)" },
];
const CODEX_MODELS = [
  { v: "", label: "默认" },
  { v: "gpt-5.5", label: "GPT-5.5" },
  { v: "gpt-5.4", label: "GPT-5.4" },
  { v: "gpt-5.4-mini", label: "GPT-5.4-Mini" },
  { v: "gpt-5.3-codex-spark", label: "GPT-5.3-Codex-Spark" },
];

export function App() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [busy, setBusy] = useState<BusyState>({ claude: false, codex: false });
  const [project, setProject] = useState<ProjectInfo>({ cwd: null, name: null });
  const [auth, setAuth] = useState<AuthState>(DISCONNECTED);
  const [mode, setMode] = useState<Mode>("solo");
  const [connecting, setConnecting] = useState<Record<AgentKind, boolean>>({ claude: false, codex: false });
  const [models, setModels] = useState<Record<AgentKind, string>>({ claude: "", codex: "" });
  const [soloTarget, setSoloTarget] = useState<AgentKind>("claude");

  useEffect(() => {
    const offEvent = window.studio.onEvent((m) => {
      setMessages((prev) => {
        const i = prev.findIndex((x) => x.id === m.id);
        if (i === -1) return [...prev, m];
        const next = prev.slice();
        next[i] = m;
        return next;
      });
    });
    const offBusy = window.studio.onBusy(setBusy);
    const offProject = window.studio.onProject((p) => {
      setProject(p);
      setMessages([]);
    });
    const offAuth = window.studio.onAuth(setAuth);
    const offMode = window.studio.onMode(setMode);
    void window.studio.getProject().then(setProject);
    void window.studio.getAuth().then(setAuth);
    void window.studio.getMode().then(setMode);
    return () => {
      offEvent();
      offBusy();
      offProject();
      offAuth();
      offMode();
    };
  }, []);

  const collab = mode === "collab";
  const anyBusy = busy.claude || busy.codex;

  const connect = async (kind: AgentKind) => {
    setConnecting((c) => ({ ...c, [kind]: true }));
    try {
      const st = await window.studio.connect(kind);
      setAuth((a) => ({ ...a, [kind]: st }));
    } finally {
      setConnecting((c) => ({ ...c, [kind]: false }));
    }
  };
  const changeMode = (m: Mode) => {
    setMode(m);
    window.studio.setMode(m);
  };
  const changeModel = (agent: AgentKind, v: string) => {
    setModels((mm) => ({ ...mm, [agent]: v }));
    window.studio.setModel(agent, v);
  };
  const pick = () => void window.studio.pickProject();

  const target: AgentKind = collab ? "claude" : soloTarget;
  const disabled =
    !project.cwd || (collab ? !auth.claude.connected || !auth.codex.connected : !auth[soloTarget].connected);
  const composerBusy = collab ? anyBusy : busy[soloTarget];
  const placeholder = !project.cwd
    ? "先选项目文件夹…"
    : disabled
      ? collab
        ? "请先连接 Claude 和 Codex…"
        : `请先连接 ${soloTarget === "claude" ? "Claude" : "Codex"}…`
      : collab
        ? "描述你想做的，回车后 Claude 与 Codex 自动协作…"
        : soloTarget === "claude"
          ? "和 Claude 聊聊你想做什么…（Enter 发送）"
          : "让 Codex 帮你写代码、改文件…（Enter 发送）";

  const agentCtl = (kind: AgentKind) => ({
    kind,
    name: kind === "claude" ? "Claude" : "Codex",
    accent: kind === "claude" ? "#5856D6" : "#0050cb",
    status: auth[kind],
    connecting: connecting[kind],
    onConnect: () => void connect(kind),
    models: kind === "claude" ? CLAUDE_MODELS : CODEX_MODELS,
    model: models[kind],
    onModel: (v: string) => changeModel(kind, v),
  });

  const soloToggle = collab ? null : (
    <div className="flex items-center gap-1.5 mb-2">
      <span className="text-body-sm text-on-surface-variant mr-1">发送给</span>
      {(["claude", "codex"] as AgentKind[]).map((k) => (
        <button
          type="button"
          key={k}
          onClick={() => setSoloTarget(k)}
          className={`px-2.5 py-0.5 rounded-full text-body-sm font-medium transition-colors ${
            soloTarget === k ? "bg-primary text-white" : "bg-surface-container text-on-surface-variant hover:text-on-surface"
          }`}
        >
          {k === "claude" ? "Claude" : "Codex"}
        </button>
      ))}
    </div>
  );

  return (
    <div className="h-screen flex bg-background text-on-surface overflow-hidden">
      <Sidebar onNewProject={pick} />
      <main className="flex-1 min-w-0 flex flex-col">
        <TopBar project={project} mode={mode} onMode={changeMode} onPick={pick} onExecute={() => {}} />
        <StatusBar mode={mode} busy={anyBusy} claude={agentCtl("claude")} codex={agentCtl("codex")} />
        <div className="flex-1 min-h-0 flex p-gutter gap-gutter bg-surface-container-lowest">
          <section className="w-1/2 min-w-0 flex flex-col bg-surface rounded-xl border border-outline-variant/30 overflow-hidden mac-shadow">
            <Conversation
              messages={messages}
              hasProject={!!project.cwd}
              emptyTitle={collab ? "描述你想做的东西" : "说说你想做什么"}
              emptySub={
                collab
                  ? "回车后 Claude 规划 → Codex 自动执行 → Claude 审查，全程自动。"
                  : "Claude 负责规划/审查，Codex 负责写码。切到「双向」可让两者自动协作完成。"
              }
            />
            <Composer
              busy={composerBusy}
              disabled={disabled}
              placeholder={placeholder}
              onSend={(t) => void window.studio.send(t, target)}
              onStop={() => window.studio.abort(target)}
              extra={soloToggle}
            />
          </section>
          <section className="w-1/2 min-w-0 flex flex-col gap-gutter">
            <LivePreview />
            <Terminal />
          </section>
        </div>
      </main>
    </div>
  );
}
