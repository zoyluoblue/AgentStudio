import { useEffect, useState } from "react";
import { useLang } from "../i18n";
import type { AppSettings, ProxyMode, ProxyScope, ThemeMode } from "../../../shared/ipc";

interface Props {
  settings: AppSettings | null;
  onChange: (patch: Partial<AppSettings>) => void;
}

function Section({ title, sub, children }: { title: string; sub: string; children: React.ReactNode }) {
  return (
    <section className="bg-surface rounded-xl border border-outline-variant/30 p-5 mac-shadow">
      <h3 className="font-headline text-headline text-on-surface">{title}</h3>
      <p className="text-body-sm text-on-surface-variant mt-0.5 mb-4">{sub}</p>
      {children}
    </section>
  );
}

function Choice({
  active,
  icon,
  label,
  hint,
  onClick,
}: {
  active: boolean;
  icon: string;
  label: string;
  hint?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex-1 min-w-[120px] text-left rounded-lg border p-3 transition-all ${
        active ? "border-primary bg-primary/5 ring-1 ring-primary/30" : "border-outline-variant/40 hover:border-outline-variant"
      }`}
    >
      <div className="flex items-center gap-2">
        <span className={`material-symbols-outlined text-[18px] ${active ? "text-primary" : "text-on-surface-variant"}`}>{icon}</span>
        <span className={`text-body-lg font-medium ${active ? "text-primary" : "text-on-surface"}`}>{label}</span>
      </div>
      {hint && <p className="text-body-sm text-on-surface-variant mt-1 leading-snug">{hint}</p>}
    </button>
  );
}

export function SettingsView({ settings, onChange }: Props) {
  const { t } = useLang();
  const [url, setUrl] = useState(settings?.proxyUrl ?? "");
  useEffect(() => setUrl(settings?.proxyUrl ?? ""), [settings?.proxyUrl]);

  const theme = settings?.theme ?? "system";
  const proxyMode = settings?.proxyMode ?? "system";
  const proxyScope = settings?.proxyScope ?? "both";
  const autoMemory = settings?.autoMemory ?? true;
  const setTheme = (m: ThemeMode) => onChange({ theme: m });
  const setProxyMode = (m: ProxyMode) => onChange({ proxyMode: m });
  const setProxyScope = (s: ProxyScope) => onChange({ proxyScope: s });
  const [proxyFlash, setProxyFlash] = useState(false);
  const proxyDirty = url.trim() !== (settings?.proxyUrl ?? "");
  // Custom proxy now takes effect only on explicit save (no more apply-on-blur).
  const saveUrl = () => {
    if (!proxyDirty) return;
    onChange({ proxyUrl: url.trim() });
    setProxyFlash(true);
    setTimeout(() => setProxyFlash(false), 1800);
  };

  return (
    <div className="flex-1 min-h-0 overflow-y-auto bg-surface-container-lowest">
      <div className="max-w-[680px] mx-auto px-6 py-6">
        <div className="mb-5">
          <h2 className="font-display text-display text-on-surface">{t("settingsTitle")}</h2>
          <p className="text-body-sm text-on-surface-variant mt-1">{t("settingsSub")}</p>
        </div>

        <div className="space-y-4">
          {/* Appearance */}
          <Section title={t("secAppearance")} sub={t("secAppearanceSub")}>
            <div className="flex flex-wrap gap-2">
              <Choice active={theme === "system"} icon="brightness_auto" label={t("themeSystem")} onClick={() => setTheme("system")} />
              <Choice active={theme === "light"} icon="light_mode" label={t("themeLight")} onClick={() => setTheme("light")} />
              <Choice active={theme === "dark"} icon="dark_mode" label={t("themeDark")} onClick={() => setTheme("dark")} />
            </div>
          </Section>

          {/* Proxy */}
          <Section title={t("secProxy")} sub={t("secProxySub")}>
            <div className="flex flex-wrap gap-2">
              <Choice
                active={proxyMode === "system"}
                icon="dns"
                label={t("proxySystem")}
                hint={t("proxySystemHint")}
                onClick={() => setProxyMode("system")}
              />
              <Choice
                active={proxyMode === "custom"}
                icon="tune"
                label={t("proxyCustom")}
                hint={t("proxyCustomHint")}
                onClick={() => setProxyMode("custom")}
              />
              <Choice
                active={proxyMode === "none"}
                icon="block"
                label={t("proxyNone")}
                hint={t("proxyNoneHint")}
                onClick={() => setProxyMode("none")}
              />
            </div>
            {proxyMode !== "none" && (
              <div className="mt-4">
                <span className="block text-label-caps font-bold text-on-surface-variant/70 mb-1.5">{t("proxyScopeLabel")}</span>
                <div className="flex flex-wrap gap-1.5">
                  {(["master", "slave", "both"] as ProxyScope[]).map((s) => (
                    <button
                      type="button"
                      key={s}
                      onClick={() => setProxyScope(s)}
                      className={`px-3 py-1 rounded-full text-body-sm font-medium transition-colors ${
                        proxyScope === s ? "bg-primary text-white" : "bg-surface-container text-on-surface-variant hover:text-on-surface"
                      }`}
                    >
                      {t(s === "master" ? "scopeMaster" : s === "slave" ? "scopeSlave" : "scopeBoth")}
                    </button>
                  ))}
                </div>
              </div>
            )}
            {proxyMode === "custom" && (
              <div className="mt-4">
                <label htmlFor="proxy-url" className="block text-label-caps font-bold text-on-surface-variant/70 mb-1.5">
                  {t("proxyUrlLabel")}
                </label>
                <div className="flex items-center gap-2">
                  <input
                    id="proxy-url"
                    value={url}
                    onChange={(e) => setUrl(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && saveUrl()}
                    placeholder="http://127.0.0.1:7890"
                    spellCheck={false}
                    className="flex-1 min-w-0 bg-surface-container rounded-lg px-3 py-2 font-code text-body-lg text-on-surface placeholder:text-on-surface-variant/50 outline-none focus:ring-2 focus:ring-primary/30"
                  />
                  <button
                    type="button"
                    onClick={saveUrl}
                    disabled={!proxyDirty}
                    className="shrink-0 px-4 py-2 rounded-lg text-body-sm font-semibold text-white bg-primary hover:opacity-90 active:scale-95 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {proxyDirty ? t("save") : t("saved")}
                  </button>
                </div>
                {proxyFlash && <p className="text-body-sm text-[#27C93F] mt-1.5">{`✓ ${t("applied")}`}</p>}
              </div>
            )}
            <p className="text-body-sm text-on-surface-variant/70 mt-3 flex items-center gap-1.5">
              <span className="material-symbols-outlined text-[15px]">info</span>
              {t("proxyApplyNote")}
            </p>
          </Section>

          {/* Memory */}
          <Section title={t("secMemory")} sub={t("secMemorySub")}>
            <div className="flex flex-wrap gap-2">
              <Choice
                active={autoMemory}
                icon="auto_awesome"
                label={t("autoMemOn")}
                hint={t("autoMemOnHint")}
                onClick={() => onChange({ autoMemory: true })}
              />
              <Choice
                active={!autoMemory}
                icon="block"
                label={t("autoMemOff")}
                hint={t("autoMemOffHint")}
                onClick={() => onChange({ autoMemory: false })}
              />
            </div>
            <p className="text-body-sm text-on-surface-variant/70 mt-3 flex items-center gap-1.5">
              <span className="material-symbols-outlined text-[15px]">info</span>
              {t("autoMemTriggers")}
            </p>
          </Section>
        </div>
      </div>
    </div>
  );
}
