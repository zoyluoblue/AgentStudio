import { useEffect, useState } from "react";
import { useLang } from "../i18n";
import type { AgentKind, AuthStatus, Backend, Lane } from "../../../shared/ipc";

interface Props {
  kind: AgentKind;
  lane: Lane;
  backend: Backend;
  backendOptions: Backend[];
  onBackend: (b: Backend) => void;
  status: AuthStatus;
  connecting: boolean;
  onConnect: () => void;
  /** suggested model ids (editable — user can also type a custom id) */
  modelOptions: string[];
  model: string;
  onModel: (v: string) => void;
  deepseekKey: string;
  onDeepseekKey: (v: string) => void;
}

const BACKEND_META: Record<Backend, { name: string; icon: string; color: string }> = {
  claude: { name: "Claude", icon: "psychology", color: "#5856D6" },
  codex: { name: "Codex", icon: "code", color: "#0050cb" },
  deepseek: { name: "DeepSeek", icon: "neurology", color: "#4D6BFE" },
};

export function AgentPanelHeader({
  kind,
  lane,
  backend,
  backendOptions,
  onBackend,
  status,
  connecting,
  onConnect,
  modelOptions,
  model,
  onModel,
  deepseekKey,
  onDeepseekKey,
}: Props) {
  const { t } = useLang();
  const meta = BACKEND_META[backend];
  const accent = meta.color;
  const [keyDraft, setKeyDraft] = useState(deepseekKey);
  const [editingKey, setEditingKey] = useState(false);
  useEffect(() => setKeyDraft(deepseekKey), [deepseekKey]);
  const commitKey = () => {
    if (keyDraft.trim() !== deepseekKey) onDeepseekKey(keyDraft.trim());
    setEditingKey(false);
  };

  return (
    <div className="shrink-0 flex flex-wrap items-center gap-x-3 gap-y-2 px-stack_md py-2.5 bg-surface rounded-xl border border-outline-variant/30 mac-shadow">
      {/* identity group (stays together) */}
      <div className="flex items-center gap-2.5 min-w-0">
        <div className="w-8 h-8 rounded-full flex items-center justify-center text-white shrink-0" style={{ background: accent }}>
          <span className="material-symbols-outlined text-[18px]" style={{ fontVariationSettings: "'FILL' 1" }}>
            {meta.icon}
          </span>
        </div>
        <div className="leading-tight">
          <div className="flex items-center gap-1.5">
            <span className="font-headline text-body-lg font-bold whitespace-nowrap" style={{ color: accent }}>
              {meta.name}
            </span>
            <span className="text-[9px] font-bold tracking-wide px-1 py-0.5 rounded" style={{ color: accent, background: `${accent}1f` }}>
              {lane === "master" ? "MASTER" : "SLAVE"}
            </span>
          </div>
          <div className="text-label-caps text-on-surface-variant">{t(lane === "master" ? "planReview" : "codeExec")}</div>
        </div>
      </div>

      {/* controls group (wraps to a new line when the panel is narrow) */}
      <div className="ml-auto flex items-center gap-2 min-w-0">
        <select
          value={backend}
          onChange={(e) => onBackend(e.target.value as Backend)}
          title="LLM"
          className="bg-surface-container border border-outline-variant/30 rounded-lg px-2 py-1 text-body-sm font-medium text-on-surface outline-none cursor-pointer hover:border-outline-variant"
        >
          {backendOptions.map((b) => (
            <option key={b} value={b}>
              {BACKEND_META[b].name}
            </option>
          ))}
        </select>

        {backend === "deepseek" ? (
          deepseekKey && !editingKey ? (
            <button
              type="button"
              onClick={() => setEditingKey(true)}
              className="flex items-center gap-1.5 text-body-sm text-on-surface-variant bg-surface-container px-2.5 py-1 rounded-full hover:text-on-surface"
              title={t("deepseekKeyEdit")}
            >
              <span className="w-1.5 h-1.5 rounded-full bg-[#27C93F] shrink-0" />
              {t("deepseekKeySet")}
            </button>
          ) : (
            <input
              value={keyDraft}
              onChange={(e) => setKeyDraft(e.target.value)}
              onBlur={commitKey}
              onKeyDown={(e) => {
                if (e.key === "Enter") commitKey();
                else if (e.key === "Escape") setEditingKey(false);
              }}
              type="password"
              placeholder={t("deepseekKeyPh")}
              spellCheck={false}
              // biome-ignore lint/a11y/noAutofocus: appears on explicit deepseek select / edit
              autoFocus={editingKey}
              className="w-[150px] bg-surface-container border border-outline-variant/30 rounded-lg px-2 py-1 font-code text-body-sm text-on-surface placeholder:text-on-surface-variant/50 outline-none focus:ring-2 focus:ring-primary/30"
            />
          )
        ) : status.connected ? (
          <span className="flex items-center gap-1.5 text-body-sm text-on-surface-variant bg-surface-container px-2.5 py-1 rounded-full max-w-[150px]">
            <span className="w-1.5 h-1.5 rounded-full bg-[#27C93F] shrink-0" />
            <span className="truncate">{status.detail ?? t("connected")}</span>
          </span>
        ) : connecting ? (
          <span className="text-body-sm text-on-surface-variant">{t("connecting")}</span>
        ) : (
          <button
            type="button"
            onClick={onConnect}
            className="px-3.5 py-1 rounded-full text-body-sm font-semibold text-white hover:opacity-90 active:scale-95 transition-all"
            style={{ background: accent }}
          >
            {t("connect")}
          </button>
        )}

        <input
          value={model}
          onChange={(e) => onModel(e.target.value)}
          list={`models-${kind}`}
          title="Model"
          placeholder={t("modelDefault")}
          spellCheck={false}
          className="w-[130px] bg-surface-container border border-outline-variant/30 rounded-lg px-2 py-1 text-body-sm text-on-surface-variant outline-none hover:text-on-surface focus:ring-2 focus:ring-primary/30"
        />
        <datalist id={`models-${kind}`}>
          {modelOptions.map((m) => (
            <option key={m} value={m} />
          ))}
        </datalist>
      </div>
    </div>
  );
}
