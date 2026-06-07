import { useEffect, useMemo, useRef, useState } from "react";
import { useLang } from "./i18n";
import type { ActivityState, AgentKind, AppSettings, AuthState, Backend, BusyState, ChatMessage, Lane, Mode, ProjectInfo } from "../../shared/ipc";
import { AgentPanel } from "./components/AgentPanel";
import { HistoryView } from "./components/HistoryView";
import { SettingsView } from "./components/SettingsView";
import { Sidebar, type View } from "./components/Sidebar";
import { TopBar } from "./components/TopBar";

const DISCONNECTED: AuthState = { claude: { connected: false }, codex: { connected: false } };
const NO_ACTIVITY: ActivityState = { claude: "", codex: "" };

const MASTER_BACKENDS: Backend[] = ["claude", "codex", "deepseek"];
const SLAVE_BACKENDS: Backend[] = ["claude", "codex", "deepseek"];
const NO_MODELS: Record<AgentKind, string[]> = { claude: [], codex: [] };

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
  const [modelOpts, setModelOpts] = useState<Record<AgentKind, string[]>>(NO_MODELS);
  const initialHash = useMemo(() => new URLSearchParams(window.location.hash.slice(1)), []);
  const [view, setView] = useState<View>(() => {
    const h = initialHash.get("view");
    return h === "history" || h === "settings" ? h : "chat";
  });
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [focusId, setFocusId] = useState<string | undefined>();
  const focusTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const focusMessage = (id: string) => {
    if (focusTimer.current) clearTimeout(focusTimer.current);
    setFocusId(id);
    focusTimer.current = setTimeout(() => setFocusId(undefined), 2600);
  };

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
    const offSession = window.studio.onSessionLoad((p) => {
      setProject(p.project);
      setMode(p.mode);
      setMessages(p.messages);
      setView("chat");
      if (p.focusMessageId) focusMessage(p.focusMessageId);
    });
    void window.studio.getProject().then(setProject);
    void window.studio.getAuth().then(setAuth);
    void window.studio.getMode().then(setMode);
    void window.studio.getSettings().then(setSettings);
    return () => {
      offEvent();
      offBusy();
      offActivity();
      offProject();
      offAuth();
      offMode();
      offSession();
    };
  }, []);

  // Apply the chosen theme to <html>; follow the OS when in "system" mode.
  useEffect(() => {
    if (!settings) return;
    localStorage.setItem("ac-theme", settings.theme);
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const dark = settings.theme === "dark" || (settings.theme === "system" && mq.matches);
      document.documentElement.className = dark ? "dark" : "light";
    };
    apply();
    if (settings.theme !== "system") return;
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [settings]);
  const changeSettings = async (patch: Partial<AppSettings>) => {
    setSettings(await window.studio.setSettings(patch));
  };

  const collab = mode === "collab";
  const anyBusy = busy.claude || busy.codex;
  const claudeMsgs = useMemo(() => messages.filter((m) => m.lane === "claude"), [messages]);
  const codexMsgs = useMemo(() => messages.filter((m) => m.lane === "codex"), [messages]);

  const dsKey = settings?.deepseekApiKey ?? "";
  const backendOf = (kind: AgentKind): Backend =>
    (kind === "claude" ? settings?.masterBackend : settings?.slaveBackend) ?? (kind === "claude" ? "claude" : "codex");
  const laneReady = (kind: AgentKind): boolean => {
    const b = backendOf(kind);
    return b === "deepseek" ? !!dsKey : auth[b].connected;
  };

  // Fetch each lane's model suggestions (DeepSeek live, Claude aliases) when its backend / key changes.
  const masterB = settings?.masterBackend;
  const slaveB = settings?.slaveBackend;
  // biome-ignore lint/correctness/useExhaustiveDependencies: backendOf is derived from these very deps
  useEffect(() => {
    if (!settings) return;
    let alive = true;
    const load = (kind: AgentKind) =>
      void window.studio.listModels(backendOf(kind)).then((list) => alive && setModelOpts((o) => ({ ...o, [kind]: list })));
    load("claude");
    load("codex");
    return () => {
      alive = false;
    };
  }, [masterB, slaveB, dsKey]);

  const connect = async (backend: AgentKind) => {
    setConnecting((c) => ({ ...c, [backend]: true }));
    try {
      const st = await window.studio.connect(backend);
      setAuth((a) => ({ ...a, [backend]: st }));
    } finally {
      setConnecting((c) => ({ ...c, [backend]: false }));
    }
  };
  const changeMode = (m: Mode) => {
    setMode(m);
    window.studio.setMode(m);
  };
  const changeModel = (kind: AgentKind, v: string) => {
    setModels((mm) => ({ ...mm, [kind]: v }));
    window.studio.setModel(kind, v);
  };
  const changeBackend = (kind: AgentKind, b: Backend) => {
    void changeSettings(kind === "claude" ? { masterBackend: b } : { slaveBackend: b });
    changeModel(kind, ""); // reset model when the backend changes
  };
  const pick = () => {
    setView("chat");
    void window.studio.pickProject();
  };

  const headerProps = (kind: AgentKind) => {
    const lane: Lane = kind === "claude" ? "master" : "slave";
    const backend = backendOf(kind);
    return {
      kind,
      lane,
      backend,
      backendOptions: kind === "claude" ? MASTER_BACKENDS : SLAVE_BACKENDS,
      onBackend: (b: Backend) => changeBackend(kind, b),
      status: backend === "deepseek" ? { connected: !!dsKey } : auth[backend],
      connecting: backend === "deepseek" ? false : connecting[backend],
      onConnect: () => {
        if (backend !== "deepseek") void connect(backend);
      },
      modelOptions: modelOpts[kind],
      model: models[kind],
      onModel: (v: string) => changeModel(kind, v),
      deepseekKey: dsKey,
      onDeepseekKey: (v: string) => void changeSettings({ deepseekApiKey: v }),
    };
  };

  const masterReady = !!project.cwd && laneReady("claude") && (!collab || laneReady("codex"));
  const claudeComposer = {
    busy: collab ? anyBusy : busy.claude,
    disabled: !masterReady,
    placeholder: !project.cwd
      ? t("phPickFolder")
      : !masterReady
        ? collab
          ? t("phConnectBoth")
          : t("phConnectMaster")
        : collab
          ? t("phCollab")
          : t("phMaster"),
    onSend: (x: string) => void window.studio.send(x, "claude"),
    onStop: () => window.studio.abort("claude"),
  };

  const slaveReady = !!project.cwd && laneReady("codex");
  const codexComposer = collab
    ? undefined
    : {
        busy: busy.codex,
        disabled: !slaveReady,
        placeholder: !project.cwd ? t("phPickFolder") : !slaveReady ? t("phConnectSlave") : t("phSlave"),
        onSend: (x: string) => void window.studio.send(x, "codex"),
        onStop: () => window.studio.abort("codex"),
      };

  return (
    <div className="h-screen flex bg-background text-on-surface overflow-hidden">
      <Sidebar onNewProject={pick} view={view} onView={setView} />
      <main className="flex-1 min-w-0 flex flex-col">
        <TopBar project={project} mode={mode} onMode={changeMode} onPick={pick} />
        {view === "settings" ? (
          <SettingsView settings={settings} onChange={changeSettings} />
        ) : view === "history" ? (
          <HistoryView />
        ) : (
          <div className="flex-1 min-h-0 flex p-gutter gap-gutter bg-surface-container-lowest">
            <AgentPanel
              header={headerProps("claude")}
              messages={claudeMsgs}
              hasProject={!!project.cwd}
              emptyTitle={collab ? t("claudeTitleCollab") : t("claudeTitleSolo")}
              emptySub={collab ? t("claudeSubCollab") : t("claudeSubSolo")}
              composer={claudeComposer}
              focusId={focusId}
              activity={activity.claude}
            />
            <AgentPanel
              header={headerProps("codex")}
              messages={codexMsgs}
              hasProject={!!project.cwd}
              emptyTitle={collab ? t("codexTitleCollab") : t("codexTitle")}
              emptySub={collab ? t("codexSubCollab") : t("codexSub")}
              composer={codexComposer}
              focusId={focusId}
              activity={activity.codex}
            />
          </div>
        )}
      </main>
    </div>
  );
}
