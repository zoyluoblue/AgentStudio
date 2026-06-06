import { useEffect, useMemo, useState } from "react";
import { useLang } from "./i18n";
import type { ActivityState, AgentKind, AuthState, BusyState, ChatMessage, Mode, ProjectInfo } from "../../shared/ipc";
import { AgentPanel } from "./components/AgentPanel";
import { Sidebar } from "./components/Sidebar";
import { TopBar } from "./components/TopBar";

const DISCONNECTED: AuthState = { claude: { connected: false }, codex: { connected: false } };
const NO_ACTIVITY: ActivityState = { claude: "", codex: "" };

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
  const { t } = useLang();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [busy, setBusy] = useState<BusyState>({ claude: false, codex: false });
  const [activity, setActivity] = useState<ActivityState>(NO_ACTIVITY);
  const [project, setProject] = useState<ProjectInfo>({ cwd: null, name: null });
  const [auth, setAuth] = useState<AuthState>(DISCONNECTED);
  const [mode, setMode] = useState<Mode>("solo");
  const [connecting, setConnecting] = useState<Record<AgentKind, boolean>>({ claude: false, codex: false });
  const [models, setModels] = useState<Record<AgentKind, string>>({ claude: "", codex: "" });

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
    const offActivity = window.studio.onActivity(setActivity);
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
      offActivity();
      offProject();
      offAuth();
      offMode();
    };
  }, []);

  const collab = mode === "collab";
  const anyBusy = busy.claude || busy.codex;
  const claudeMsgs = useMemo(() => messages.filter((m) => m.lane === "claude"), [messages]);
  const codexMsgs = useMemo(() => messages.filter((m) => m.lane === "codex"), [messages]);

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

  const headerProps = (kind: AgentKind) => ({
    kind,
    name: kind === "claude" ? "Claude" : "Codex",
    role: t(kind === "claude" ? "planReview" : "codeExec"),
    status: auth[kind],
    connecting: connecting[kind],
    activity: activity[kind],
    onConnect: () => void connect(kind),
    models: kind === "claude" ? CLAUDE_MODELS : CODEX_MODELS,
    model: models[kind],
    onModel: (v: string) => changeModel(kind, v),
  });

  const claudeDisabled = !project.cwd || !auth.claude.connected || (collab && !auth.codex.connected);
  const claudeComposer = {
    busy: collab ? anyBusy : busy.claude,
    disabled: claudeDisabled,
    placeholder: !project.cwd
      ? t("phPickFolder")
      : claudeDisabled
        ? collab
          ? t("phConnectBoth")
          : t("phConnectClaude")
        : collab
          ? t("phCollab")
          : t("phClaude"),
    onSend: (x: string) => void window.studio.send(x, "claude"),
    onStop: () => window.studio.abort("claude"),
  };

  const codexComposer = collab
    ? undefined
    : {
        busy: busy.codex,
        disabled: !project.cwd || !auth.codex.connected,
        placeholder: !project.cwd ? t("phPickFolder") : !auth.codex.connected ? t("phConnectCodex") : t("phCodex"),
        onSend: (x: string) => void window.studio.send(x, "codex"),
        onStop: () => window.studio.abort("codex"),
      };

  return (
    <div className="h-screen flex bg-background text-on-surface overflow-hidden">
      <Sidebar onNewProject={pick} />
      <main className="flex-1 min-w-0 flex flex-col">
        <TopBar project={project} mode={mode} onMode={changeMode} onPick={pick} />
        <div className="flex-1 min-h-0 flex p-gutter gap-gutter bg-surface-container-lowest">
          <AgentPanel
            header={headerProps("claude")}
            messages={claudeMsgs}
            hasProject={!!project.cwd}
            emptyTitle={collab ? t("claudeTitleCollab") : t("claudeTitleSolo")}
            emptySub={collab ? t("claudeSubCollab") : t("claudeSubSolo")}
            composer={claudeComposer}
          />
          <AgentPanel
            header={headerProps("codex")}
            messages={codexMsgs}
            hasProject={!!project.cwd}
            emptyTitle={collab ? t("codexTitleCollab") : t("codexTitle")}
            emptySub={collab ? t("codexSubCollab") : t("codexSub")}
            composer={codexComposer}
          />
        </div>
      </main>
    </div>
  );
}
