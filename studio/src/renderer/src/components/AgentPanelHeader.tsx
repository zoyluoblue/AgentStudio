import { useEffect, useState } from "react";
import { useLang } from "../i18n";
import type { AgentKind, AuthStatus, Backend, ConnectMethod, Lane, ModelOption } from "../../../shared/ipc";

interface Props {
  kind: AgentKind;
  lane: Lane;
  backend: Backend;
  backendOptions: Backend[];
  onBackend: (b: Backend) => void;
  /** how this backend authenticates (app login vs API key) */
  method: ConnectMethod;
  onMethod: (m: ConnectMethod) => void;
  /** the backend's API key (api-key method) */
  apiKey: string;
  onApiKey: (v: string) => void;
  /** connection status (connected + optional detail like an email) */
  status: AuthStatus;
  connecting: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  /** selectable models for the connected backend */
  modelOptions: ModelOption[];
  model: string;
  onModel: (v: string) => void;
  onRefreshModels: () => void;
}

const BACKEND_META: Record<Backend, { name: string; icon: string; color: string }> = {
  claude: { name: "Claude", icon: "psychology", color: "#5856D6" },
  codex: { name: "Codex", icon: "code", color: "#0050cb" },
  deepseek: { name: "DeepSeek", icon: "neurology", color: "#4D6BFE" },
};

// Shared height keeps every control on one visual line so both lane headers are identical.
const CTRL = "h-8 rounded-lg border border-outline-variant/30 bg-surface-container text-body-sm outline-none";

export function AgentPanelHeader({
  kind,
  lane,
  backend,
  backendOptions,
  onBackend,
  method,
  onMethod,
  apiKey,
  onApiKey,
  status,
  connecting,
  onConnect,
  onDisconnect,
  modelOptions,
  model,
  onModel,
  onRefreshModels,
}: Props) {
  const { t } = useLang();
  const meta = BACKEND_META[backend];
  const accent = meta.color;
  const isKey = method === "key";
  const canSwitchMethod = backend !== "deepseek"; // DeepSeek has no app login

  const [keyDraft, setKeyDraft] = useState(apiKey);
  const [editingKey, setEditingKey] = useState(false);
  useEffect(() => setKeyDraft(apiKey), [apiKey]);
  const commitKey = () => {
    if (keyDraft.trim() !== apiKey) onApiKey(keyDraft.trim());
    setEditingKey(false);
  };

  // if the current model isn't one of the known options, surface it as an extra entry so it still shows
  const hasCustomModel = !!model && !modelOptions.some((m) => m.id === model);

  return (
    <div className="shrink-0 flex flex-col gap-2 px-stack_md py-2.5 bg-surface rounded-xl border border-outline-variant/30 mac-shadow">
      {/* Row 1 — identity + backend + connection method */}
      <div className="flex items-center gap-2.5 min-w-0">
        <div className="w-8 h-8 rounded-full flex items-center justify-center text-white shrink-0" style={{ background: accent }}>
          <span className="material-symbols-outlined text-[18px]" style={{ fontVariationSettings: "'FILL' 1" }}>
            {meta.icon}
          </span>
        </div>
        <div className="leading-tight min-w-0">
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

        <div className="ml-auto flex items-center gap-2 shrink-0">
          <select
            value={backend}
            onChange={(e) => onBackend(e.target.value as Backend)}
            title="LLM"
            className={`${CTRL} px-2 font-medium text-on-surface cursor-pointer hover:border-outline-variant`}
          >
            {backendOptions.map((b) => (
              <option key={b} value={b}>
                {BACKEND_META[b].name}
              </option>
            ))}
          </select>

          {canSwitchMethod && (
            <div className="flex items-center h-8 rounded-lg bg-surface-container p-0.5" role="radiogroup" aria-label="connection method">
              {(["app", "key"] as ConnectMethod[]).map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => onMethod(m)}
                  aria-pressed={method === m}
                  style={method === m ? { background: `${accent}24`, color: accent } : undefined}
                  className={`h-7 px-2 rounded-md text-body-sm font-medium transition-colors ${
                    method === m ? "" : "text-on-surface-variant hover:text-on-surface"
                  }`}
                >
                  {t(m === "app" ? "methodApp" : "methodKey")}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Row 2 — connection control + model picker */}
      <div className="flex items-center gap-2 min-w-0">
        {/* connection control (left, shrinkable) */}
        <div className="flex items-center gap-2 min-w-0">
          {isKey ? (
            status.connected && !editingKey ? (
              <>
                <button
                  type="button"
                  onClick={() => setEditingKey(true)}
                  title={t("apiKeyEdit")}
                  className={`${CTRL} flex items-center gap-1.5 px-2.5 text-on-surface-variant hover:text-on-surface max-w-[180px]`}
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-[#27C93F] shrink-0" />
                  <span className="truncate">{t("apiKeySet")}</span>
                </button>
                <DisconnectBtn label={t("disconnect")} onClick={onDisconnect} />
              </>
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
                placeholder={`${meta.name} API Key`}
                spellCheck={false}
                // biome-ignore lint/a11y/noAutofocus: appears on explicit key-method select / edit
                autoFocus={editingKey}
                className={`${CTRL} w-[200px] px-2 font-code text-on-surface placeholder:text-on-surface-variant/50 focus:ring-2 focus:ring-primary/30`}
              />
            )
          ) : status.connected ? (
            <>
              <span className={`${CTRL} flex items-center gap-1.5 px-2.5 text-on-surface-variant max-w-[180px]`}>
                <span className="w-1.5 h-1.5 rounded-full bg-[#27C93F] shrink-0" />
                <span className="truncate">{status.detail ?? t("connected")}</span>
              </span>
              <DisconnectBtn label={t("disconnect")} onClick={onDisconnect} />
            </>
          ) : connecting ? (
            <span className="flex items-center gap-1.5 px-1 text-body-sm text-on-surface-variant">
              <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse shrink-0" />
              {t("connecting")}
            </span>
          ) : (
            <button
              type="button"
              onClick={onConnect}
              className="h-8 px-3.5 rounded-lg text-body-sm font-semibold text-white hover:opacity-90 active:scale-95 transition-all"
              style={{ background: accent }}
            >
              {t("connect")}
            </button>
          )}
        </div>

        {/* model picker (right) */}
        <div className="ml-auto flex items-center gap-1.5 shrink-0">
          {modelOptions.length ? (
            <select
              value={model}
              onChange={(e) => onModel(e.target.value)}
              disabled={!status.connected}
              title="Model"
              className={`${CTRL} w-[150px] px-2 text-on-surface-variant hover:text-on-surface cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed`}
            >
              <option value="">{t("modelDefault")}</option>
              {hasCustomModel && <option value={model}>{model}</option>}
              {modelOptions.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.label}
                </option>
              ))}
            </select>
          ) : (
            <input
              value={model}
              onChange={(e) => onModel(e.target.value)}
              disabled={!status.connected}
              title="Model"
              placeholder={t("modelDefault")}
              spellCheck={false}
              className={`${CTRL} w-[150px] px-2 text-on-surface-variant hover:text-on-surface focus:ring-2 focus:ring-primary/30 disabled:opacity-50`}
            />
          )}
          <button
            type="button"
            onClick={onRefreshModels}
            disabled={!status.connected}
            title={t("modelRefresh")}
            className={`${CTRL} w-8 flex items-center justify-center text-on-surface-variant hover:text-on-surface disabled:opacity-40 disabled:cursor-not-allowed`}
          >
            <span className="material-symbols-outlined text-[16px]">refresh</span>
          </button>
        </div>
      </div>
    </div>
  );
}

function DisconnectBtn({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="h-8 px-2.5 rounded-lg text-body-sm text-on-surface-variant hover:text-red-500 hover:bg-red-500/10 transition-colors shrink-0"
    >
      {label}
    </button>
  );
}
