const NAV: { icon: string; label: string; active?: boolean }[] = [
  { icon: "folder_open", label: "Explorer", active: true },
  { icon: "search", label: "搜索" },
  { icon: "history", label: "历史" },
  { icon: "extension", label: "扩展" },
  { icon: "settings", label: "设置" },
];

export function Sidebar({ onNewProject }: { onNewProject: () => void }) {
  return (
    <aside className="w-sidebar_width shrink-0 bg-surface-container/70 backdrop-blur-xl border-r border-outline-variant/30 flex flex-col py-margin_page">
      <div className="px-margin_page mb-stack_lg flex items-center gap-3">
        <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center shadow-sm">
          <span className="material-symbols-outlined text-white text-[20px]">hub</span>
        </div>
        <div>
          <h1 className="font-headline text-headline font-bold text-primary leading-tight">AgentConnector</h1>
          <p className="font-label-caps text-label-caps text-on-surface-variant">Professional Suite</p>
        </div>
      </div>
      <nav className="flex-1 px-3 space-y-1">
        <button
          type="button"
          onClick={onNewProject}
          className="w-full mb-stack_md flex items-center gap-stack_sm px-stack_md py-stack_sm bg-primary text-white font-semibold rounded-lg shadow-sm hover:opacity-90 transition-all active:scale-95"
        >
          <span className="material-symbols-outlined text-[18px]">add</span>
          <span>新建项目</span>
        </button>
        {NAV.map((n) => (
          <button
            type="button"
            key={n.label}
            className={`w-full flex items-center gap-stack_sm px-stack_md py-stack_sm rounded-lg transition-colors ${
              n.active
                ? "bg-primary-container/10 text-primary font-semibold"
                : "text-on-surface-variant hover:text-on-surface hover:bg-surface-variant/50"
            }`}
          >
            <span className="material-symbols-outlined">{n.icon}</span>
            <span className="font-body-lg">{n.label}</span>
          </button>
        ))}
      </nav>
      <div className="mt-auto px-3 space-y-1">
        {[
          ["help_outline", "帮助"],
          ["chat_bubble_outline", "反馈"],
        ].map(([icon, label]) => (
          <button
            type="button"
            key={label}
            className="w-full flex items-center gap-stack_sm px-stack_md py-stack_sm rounded-lg text-on-surface-variant hover:text-on-surface hover:bg-surface-variant/50 transition-colors"
          >
            <span className="material-symbols-outlined">{icon}</span>
            <span className="font-body-lg">{label}</span>
          </button>
        ))}
      </div>
    </aside>
  );
}
