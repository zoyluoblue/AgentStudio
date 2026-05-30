import { useEffect, useMemo, useState } from "react";
import { agent } from "./api";
import { NewRun } from "./components/NewRun";
import { NewTask } from "./components/NewTask";
import { RunDetail } from "./components/RunDetail";
import { RunList } from "./components/RunList";
import { Settings } from "./components/Settings";
import { StatusBar } from "./components/StatusBar";
import { TaskDetail } from "./components/TaskDetail";
import { TaskList } from "./components/TaskList";
import type { ConfigView, ExecutorInfo, ProjectInfo, ResumeInput, Run, RunStartInput, StartInput, TaskView } from "./types";

type Theme = "dark" | "light";
type Mode = "runs" | "tasks";
const FILTERS = ["all", "running", "queued", "done", "error", "canceled"] as const;

export default function App() {
  const [mode, setMode] = useState<Mode>("runs");
  const [tasks, setTasks] = useState<Record<string, TaskView>>({});
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [runs, setRuns] = useState<Record<string, Run>>({});
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [project, setProject] = useState<ProjectInfo | null>(null);
  const [executors, setExecutors] = useState<ExecutorInfo[]>([]);
  const [defaultExecutor, setDefaultExecutor] = useState("codex");
  const [config, setConfig] = useState<ConfigView | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [filter, setFilter] = useState<string>("all");
  const [theme, setTheme] = useState<Theme>(() => (localStorage.getItem("theme") as Theme) || "dark");

  async function refreshAll() {
    const list = await agent.list();
    setTasks(Object.fromEntries(list.map((t) => [t.taskId, t])));
  }
  async function refreshTask(id: string) {
    const v = await agent.getTask(id);
    if (v) setTasks((prev) => ({ ...prev, [id]: v }));
  }
  async function refreshRuns() {
    const list = await agent.runList();
    setRuns(Object.fromEntries(list.map((r) => [r.runId, r])));
  }
  async function refreshRun(id: string) {
    const r = await agent.runGet(id);
    if (r) setRuns((prev) => ({ ...prev, [id]: r }));
  }

  useEffect(() => {
    void (async () => {
      setProject(await agent.getProject());
      const ex = await agent.executors();
      setExecutors(ex.executors);
      setDefaultExecutor(ex.default);
      setConfig(await agent.getConfig());
      await refreshAll();
      await refreshRuns();
    })();
    const offTask = agent.onUpdate((id) => void refreshTask(id));
    const offRun = agent.onRunUpdate((id) => void refreshRun(id));
    return () => {
      offTask();
      offRun();
    };
  }, []);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("theme", theme);
  }, [theme]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setSettingsOpen(false);
      if ((e.metaKey || e.ctrlKey) && e.key === ",") {
        e.preventDefault();
        setSettingsOpen((s) => !s);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const taskList = useMemo(() => Object.values(tasks).sort((a, b) => b.startedAt - a.startedAt), [tasks]);
  const filteredTasks = useMemo(() => (filter === "all" ? taskList : taskList.filter((t) => t.state === filter)), [taskList, filter]);
  const selectedTask = selectedId ? tasks[selectedId] : undefined;
  const runListArr = useMemo(() => Object.values(runs).sort((a, b) => b.createdAt - a.createdAt), [runs]);
  const selectedRun = selectedRunId ? runs[selectedRunId] : undefined;
  const isRepo = project?.isRepo ?? false;

  // task handlers
  async function dispatch(input: StartInput) {
    const r = await agent.start(input);
    if (r.ok && r.taskId) {
      await refreshAll();
      setSelectedId(r.taskId);
    }
    return r;
  }
  async function review() {
    const r = await agent.review({ uncommitted: true });
    if (r.ok && r.taskId) {
      await refreshAll();
      setSelectedId(r.taskId);
    }
    return r;
  }
  const cancel = async (id: string) => {
    await agent.cancel(id);
    await refreshTask(id);
  };
  const resume = async (id: string, prompt: string) => {
    const input: ResumeInput = { taskId: id, prompt };
    const r = await agent.resume(input);
    if (r.ok && r.taskId) {
      await refreshAll();
      setSelectedId(r.taskId);
    }
    return r;
  };
  const apply = async (id: string) => {
    const r = await agent.apply(id);
    await refreshTask(id);
    return r;
  };

  // run handlers
  async function startRun(input: RunStartInput) {
    const r = await agent.runStart(input);
    await refreshRuns();
    setSelectedRunId(r.runId);
    return r;
  }
  const withRun = (fn: (id: string) => void | Promise<void>) => () => {
    if (selectedRunId) void Promise.resolve(fn(selectedRunId)).then(() => refreshRun(selectedRunId));
  };

  async function pickProject() {
    const p = await agent.pickProject();
    if (p) {
      setProject(p);
      await refreshAll();
    }
  }

  return (
    <div className="app">
      <div className="header">
        <span className="brand">⬢ AgentConnector</span>
        <div className="modeswitch">
          <button className={mode === "runs" ? "on" : ""} onClick={() => setMode("runs")}>
            编排 Run
          </button>
          <button className={mode === "tasks" ? "on" : ""} onClick={() => setMode("tasks")}>
            快速任务
          </button>
        </div>
        <span className="project" onClick={() => void pickProject()} title="点击切换项目目录">
          {project ? shortPath(project.cwd) : "…"}
          {project?.isRepo ? ` (${project.branch ?? "detached"}${project.dirty ? ` ✎${project.dirty}` : ""})` : " · 非git"}
        </span>
        <span className="spacer" />
        <button className="iconbtn" title="切换深/浅色" onClick={() => setTheme((t) => (t === "dark" ? "light" : "dark"))}>
          {theme === "dark" ? "☀︎" : "☾"}
        </button>
        <button className="iconbtn" title="设置 (⌘,)" onClick={() => setSettingsOpen(true)}>
          ⚙
        </button>
      </div>

      {mode === "runs" ? (
        <>
          <div className="tasks">
            <RunList runs={runListArr} selectedId={selectedRunId} onSelect={setSelectedRunId} />
          </div>
          <div className="detail">
            {selectedRun ? (
              <RunDetail
                run={selectedRun}
                onApprovePlan={withRun((id) => agent.runApprovePlan(id))}
                onApprovePhase={withRun((id) => agent.runApprovePhase(id))}
                onPause={withRun((id) => agent.runPause(id))}
                onResume={withRun((id) => agent.runResume(id))}
                onAbort={withRun((id) => agent.runAbort(id))}
                onIntervene={(text) => {
                  if (selectedRunId) void agent.runIntervene(selectedRunId, text).then(() => refreshRun(selectedRunId));
                }}
              />
            ) : (
              <div className="empty">选择左侧的 Run 查看详情，或在右侧新建一个目标。</div>
            )}
          </div>
          <div className="compose">
            <NewRun isRepo={isRepo} onStart={startRun} />
          </div>
        </>
      ) : (
        <>
          <div className="tasks">
            <div className="filterbar">
              <select value={filter} onChange={(e) => setFilter(e.target.value)}>
                {FILTERS.map((f) => (
                  <option key={f} value={f}>
                    {f === "all" ? `全部 (${taskList.length})` : `${f} (${taskList.filter((t) => t.state === f).length})`}
                  </option>
                ))}
              </select>
            </div>
            <TaskList tasks={filteredTasks} selectedId={selectedId} onSelect={setSelectedId} />
          </div>
          <div className="detail">
            {selectedTask ? (
              <TaskDetail task={selectedTask} onCancel={cancel} onResume={resume} onApply={apply} />
            ) : (
              <div className="empty">选择左侧的任务查看详情，或在右侧新建一个任务。</div>
            )}
          </div>
          <div className="compose">
            <NewTask executors={executors} defaultExecutor={defaultExecutor} isRepo={isRepo} onDispatch={dispatch} onReview={review} />
          </div>
        </>
      )}

      <StatusBar tasks={taskList} project={project} defaultExecutor={defaultExecutor} />

      {settingsOpen && <Settings config={config} executors={executors} onClose={() => setSettingsOpen(false)} />}
    </div>
  );
}

function shortPath(p: string): string {
  const parts = p.split("/").filter(Boolean);
  return parts.length <= 2 ? p : ".../" + parts.slice(-2).join("/");
}
