import { useEffect, useState } from "react";
import { useLang } from "../i18n";
import type { MemoryKind, MemoryScope, ProjectInfo } from "../../../shared/ipc";

interface Props {
  project: ProjectInfo;
}

export function MemoryView({ project }: Props) {
  const { t } = useLang();
  const hasProject = !!project.cwd;
  const [scope, setScope] = useState<MemoryScope>("global");
  const [kind, setKind] = useState<MemoryKind>("curated");
  const [text, setText] = useState("");
  const [saved, setSaved] = useState("");
  const [flash, setFlash] = useState(false);
  const [busy, setBusy] = useState(false);

  // No project open → project memory isn't addressable; fall back to global.
  useEffect(() => {
    if (!hasProject && scope === "project") setScope("global");
  }, [hasProject, scope]);

  // Load the selected (scope, kind).
  useEffect(() => {
    let alive = true;
    void window.studio.getMemory(scope, kind).then((c) => {
      if (!alive) return;
      setText(c);
      setSaved(c);
    });
    return () => {
      alive = false;
    };
  }, [scope, kind]);

  const dirty = text !== saved;
  const learned = kind === "learned";
  const flashOk = () => {
    setFlash(true);
    setTimeout(() => setFlash(false), 1800);
  };
  const save = async () => {
    await window.studio.setMemory(scope, text, kind);
    setSaved(text);
    flashOk();
  };
  const clear = async () => {
    if (!window.confirm(t("memClearConfirm"))) return;
    await window.studio.setMemory(scope, "", kind);
    setText("");
    setSaved("");
  };
  const consolidate = async () => {
    setBusy(true);
    try {
      const r = await window.studio.consolidateMemory(scope);
      setText(r);
      setSaved(r);
      flashOk();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex-1 min-h-0 overflow-y-auto bg-surface-container-lowest">
      <div className="max-w-[820px] mx-auto px-6 py-6 h-full flex flex-col">
        <div className="mb-5 shrink-0">
          <h2 className="font-display text-display text-on-surface">{t("memoryTitle")}</h2>
          <p className="text-body-sm text-on-surface-variant mt-1">{t("memorySub")}</p>
        </div>

        {/* scope tabs + kind toggle */}
        <div className="flex items-center gap-3 mb-3 shrink-0 flex-wrap">
          <div className="flex gap-1.5">
            {(["global", "project"] as MemoryScope[]).map((s) => {
              const disabled = s === "project" && !hasProject;
              return (
                <button
                  type="button"
                  key={s}
                  disabled={disabled}
                  onClick={() => setScope(s)}
                  className={`px-3.5 py-1.5 rounded-lg text-body-sm font-medium transition-colors ${
                    scope === s
                      ? "bg-primary text-white"
                      : disabled
                        ? "text-on-surface-variant/40 cursor-not-allowed"
                        : "bg-surface-container text-on-surface-variant hover:text-on-surface"
                  }`}
                >
                  {s === "global" ? t("memGlobal") : t("memProject")}
                </button>
              );
            })}
          </div>
          <div className="flex items-center h-8 rounded-lg bg-surface-container p-0.5">
            {(["curated", "learned"] as MemoryKind[]).map((k) => (
              <button
                key={k}
                type="button"
                onClick={() => setKind(k)}
                className={`h-7 px-2.5 rounded-md text-body-sm font-medium transition-colors ${
                  kind === k ? "bg-surface text-on-surface mac-shadow" : "text-on-surface-variant hover:text-on-surface"
                }`}
              >
                {k === "curated" ? t("memKindCurated") : t("memKindLearned")}
              </button>
            ))}
          </div>
          {scope === "project" && project.name && (
            <span className="text-body-sm text-on-surface-variant/70 truncate">· {project.name}</span>
          )}
        </div>

        <div className="flex-1 min-h-0 flex flex-col bg-surface rounded-xl border border-outline-variant/30 p-4 mac-shadow">
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={learned ? t("memLearnedEmpty") : t("memPlaceholder")}
            spellCheck={false}
            className="flex-1 min-h-[300px] w-full resize-none bg-transparent font-code text-body-sm leading-relaxed text-on-surface placeholder:text-on-surface-variant/40 outline-none"
          />
          <div className="flex items-center justify-between pt-3 mt-3 border-t border-outline-variant/20 shrink-0">
            <span className="text-body-sm text-on-surface-variant/70">{`${t("memChars")}: ${text.length}`}</span>
            <div className="flex items-center gap-2">
              {flash && <span className="text-body-sm text-[#27C93F] mr-1">{`✓ ${t("applied")}`}</span>}
              {learned && (
                <>
                  <button
                    type="button"
                    onClick={consolidate}
                    disabled={busy || !text.trim()}
                    className="px-3 py-1.5 rounded-lg text-body-sm font-medium text-on-surface-variant bg-surface-container hover:text-on-surface disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {busy ? t("memConsolidating") : t("memConsolidate")}
                  </button>
                  <button
                    type="button"
                    onClick={clear}
                    disabled={!text.trim()}
                    className="px-3 py-1.5 rounded-lg text-body-sm font-medium text-on-surface-variant hover:text-red-500 hover:bg-red-500/10 disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {t("memClear")}
                  </button>
                </>
              )}
              <button
                type="button"
                onClick={save}
                disabled={!dirty}
                className="px-4 py-1.5 rounded-lg text-body-sm font-semibold text-white bg-primary hover:opacity-90 active:scale-95 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {dirty ? t("save") : t("saved")}
              </button>
            </div>
          </div>
        </div>

        <p className="text-body-sm text-on-surface-variant/60 mt-3 flex items-center gap-1.5 shrink-0">
          <span className="material-symbols-outlined text-[15px]">info</span>
          {learned ? t("memHintLearned") : t("memHint")}
        </p>
      </div>
    </div>
  );
}
