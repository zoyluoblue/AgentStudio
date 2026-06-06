import type { Mode, ProjectInfo } from "../../../shared/ipc";

interface Props {
  project: ProjectInfo;
  mode: Mode;
  onMode: (m: Mode) => void;
  onPick: () => void;
  onExecute: () => void;
}

export function TopBar({ project, mode, onMode, onPick, onExecute }: Props) {
  return (
    <header className="h-16 shrink-0 bg-surface/80 backdrop-blur-md border-b border-outline-variant/20 shadow-sm flex justify-between items-center px-margin_page">
      <div className="flex items-center gap-stack_lg">
        <div className="flex gap-1.5">
          <div className="w-3 h-3 rounded-full bg-error/80" />
          <div className="w-3 h-3 rounded-full bg-[#FFBD2E]" />
          <div className="w-3 h-3 rounded-full bg-[#27C93F]" />
        </div>
        <button type="button" onClick={onPick} className="relative w-64 text-left group">
          <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-on-surface-variant text-[18px] group-hover:text-primary transition-colors">
            folder
          </span>
          <span className="block w-full bg-surface-container-low rounded-lg pl-10 pr-3 py-1.5 text-body-sm text-on-surface-variant truncate group-hover:ring-1 group-hover:ring-primary/30 transition-all">
            {project.name ?? "选择项目…"}
          </span>
        </button>
        <nav className="flex items-center gap-6 h-full">
          <button
            type="button"
            onClick={() => onMode("solo")}
            className={
              mode === "solo"
                ? "text-primary font-bold border-b-2 border-primary pb-1 text-body-lg"
                : "text-on-surface-variant font-medium hover:text-primary transition-colors text-body-lg"
            }
          >
            单点模式
          </button>
          <button
            type="button"
            onClick={() => onMode("collab")}
            className={
              mode === "collab"
                ? "text-primary font-bold border-b-2 border-primary pb-1 text-body-lg"
                : "text-on-surface-variant font-medium hover:text-primary transition-colors text-body-lg"
            }
          >
            双向模式
          </button>
        </nav>
      </div>
      <div className="flex items-center gap-stack_md">
        <button
          type="button"
          onClick={onExecute}
          className="bg-primary text-white px-4 py-1.5 rounded-lg text-body-lg font-semibold hover:opacity-80 active:scale-95 transition-all"
        >
          Execute
        </button>
        <button type="button" className="text-on-surface-variant font-medium hover:text-primary transition-colors text-body-sm">
          CN/EN
        </button>
        <button type="button" className="w-9 h-9 flex items-center justify-center rounded-full hover:bg-surface-variant/50 transition-colors">
          <span className="material-symbols-outlined text-on-surface-variant">notifications</span>
        </button>
        <div className="w-8 h-8 rounded-full bg-gradient-to-br from-primary to-secondary flex items-center justify-center text-white text-body-sm font-bold">
          Z
        </div>
      </div>
    </header>
  );
}
