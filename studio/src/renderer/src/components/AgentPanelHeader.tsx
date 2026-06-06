import type { AgentKind, AuthStatus } from "../../../shared/ipc";

interface ModelOpt {
  v: string;
  label: string;
}
interface Props {
  kind: AgentKind;
  name: string;
  role: string;
  status: AuthStatus;
  connecting: boolean;
  onConnect: () => void;
  models: ModelOpt[];
  model: string;
  onModel: (v: string) => void;
}

export function AgentPanelHeader({ kind, name, role, status, connecting, onConnect, models, model, onModel }: Props) {
  const accent = kind === "claude" ? "#5856D6" : "#0050cb";
  return (
    <div className="h-14 shrink-0 flex items-center gap-3 px-stack_md border-b border-outline-variant/20 bg-surface">
      <div className="w-8 h-8 rounded-full flex items-center justify-center text-white" style={{ background: accent }}>
        <span className="material-symbols-outlined text-[18px]" style={{ fontVariationSettings: "'FILL' 1" }}>
          {kind === "claude" ? "psychology" : "code"}
        </span>
      </div>
      <div className="leading-tight min-w-0">
        <div className="font-headline text-body-lg font-bold truncate" style={{ color: accent }}>
          {name}
        </div>
        <div className="text-label-caps text-on-surface-variant">{role}</div>
      </div>
      <div className="ml-auto flex items-center gap-2">
        {status.connected ? (
          <span className="flex items-center gap-1.5 text-body-sm text-on-surface-variant bg-surface-container px-2.5 py-1 rounded-full max-w-[160px]">
            <span className="w-1.5 h-1.5 rounded-full bg-[#27C93F] shrink-0" />
            <span className="truncate">{status.detail ?? "已连接"}</span>
          </span>
        ) : connecting ? (
          <span className="text-body-sm text-on-surface-variant">连接中…</span>
        ) : (
          <button
            type="button"
            onClick={onConnect}
            className="px-3.5 py-1 rounded-full text-body-sm font-semibold text-white hover:opacity-90 active:scale-95 transition-all"
            style={{ background: accent }}
          >
            连接
          </button>
        )}
        <select
          value={model}
          onChange={(e) => onModel(e.target.value)}
          title="模型"
          className="bg-surface-container border border-outline-variant/30 rounded-lg px-2 py-1 text-body-sm text-on-surface-variant outline-none cursor-pointer hover:text-on-surface max-w-[130px]"
        >
          {models.map((m) => (
            <option key={m.v} value={m.v}>
              {m.label}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}
