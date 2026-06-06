import type { AgentKind, AuthStatus, Mode } from "../../../shared/ipc";

interface ModelOpt {
  v: string;
  label: string;
}
interface AgentCtl {
  kind: AgentKind;
  name: string;
  accent: string;
  status: AuthStatus;
  connecting: boolean;
  onConnect: () => void;
  models: ModelOpt[];
  model: string;
  onModel: (v: string) => void;
}

function AgentControl({ kind, name, accent, status, connecting, onConnect, models, model, onModel }: AgentCtl) {
  return (
    <div className="flex items-center gap-1.5 text-body-sm">
      <span className="material-symbols-outlined text-[15px]" style={{ color: accent, fontVariationSettings: "'FILL' 1" }}>
        {kind === "claude" ? "psychology" : "code"}
      </span>
      <span className="font-semibold" style={{ color: accent }}>
        {name}
      </span>
      {status.connected ? (
        <span className="flex items-center gap-1 text-on-surface-variant">
          <span className="w-1.5 h-1.5 rounded-full bg-[#27C93F]" />
          {(status.detail ?? "").split("@")[0] || "已连接"}
        </span>
      ) : connecting ? (
        <span className="text-on-surface-variant">连接中…</span>
      ) : (
        <button type="button" onClick={onConnect} className="text-primary font-semibold hover:underline">
          连接
        </button>
      )}
      <select
        value={model}
        onChange={(e) => onModel(e.target.value)}
        className="bg-transparent text-on-surface-variant text-[11px] outline-none cursor-pointer hover:text-on-surface max-w-[110px]"
      >
        {models.map((m) => (
          <option key={m.v} value={m.v}>
            {m.label}
          </option>
        ))}
      </select>
    </div>
  );
}

interface Props {
  mode: Mode;
  busy: boolean;
  claude: AgentCtl;
  codex: AgentCtl;
}

export function StatusBar({ mode, busy, claude, codex }: Props) {
  return (
    <div className="shrink-0 bg-primary/5 px-margin_page py-2 flex items-center justify-between border-b border-primary/10">
      <div className="flex items-center gap-2">
        <span className="flex h-2 w-2 relative">
          {busy && <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75" />}
          <span className={`relative inline-flex rounded-full h-2 w-2 ${busy ? "bg-primary" : "bg-[#27C93F]"}`} />
        </span>
        <span className="font-body-sm font-semibold text-primary">
          {mode === "collab" ? "双向模式" : "单点模式"} · {busy ? "进行中…" : "就绪"}
        </span>
      </div>
      <div className="flex items-center gap-5">
        <AgentControl {...claude} />
        <span className="w-px h-4 bg-outline-variant/40" />
        <AgentControl {...codex} />
      </div>
    </div>
  );
}
