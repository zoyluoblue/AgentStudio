import { createElement, useEffect, useState } from "react";

export function LivePreview() {
  const [url, setUrl] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  const refresh = () => {
    void window.studio.getPreview().then((r) => {
      setUrl(r.url);
      setTick((t) => t + 1);
    });
  };

  useEffect(() => {
    refresh();
    const off = window.studio.onPreviewRefresh((u) => {
      setUrl(u);
      setTick((t) => t + 1);
    });
    return off;
  }, []);

  return (
    <div className="flex-1 min-h-0 flex flex-col overflow-hidden">
      <div className="h-10 shrink-0 border-b border-outline-variant/20 flex items-center justify-between px-4 bg-surface-container-low">
        <div className="flex items-center gap-2">
          <span className="material-symbols-outlined text-[16px] text-on-surface-variant">language</span>
          <span className="text-body-sm font-medium">Live Preview</span>
        </div>
        <div className="flex items-center gap-3">
          <button type="button" onClick={refresh} title="刷新" className="flex">
            <span className="material-symbols-outlined text-[16px] text-on-surface-variant hover:text-primary">refresh</span>
          </button>
        </div>
      </div>
      {url ? (
        createElement("webview", { key: `${url}#${tick}`, src: url, className: "flex-1 w-full bg-white border-none" })
      ) : (
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8 bg-slate-50">
          <span className="material-symbols-outlined text-[40px] text-on-surface-variant/40 mb-3">desktop_windows</span>
          <p className="text-body-lg font-semibold text-on-surface-variant">暂无可预览的页面</p>
          <p className="text-body-sm text-on-surface-variant/70 mt-1 max-w-[260px]">
            当项目里出现 index.html（例如 Codex 生成网页后），这里会自动显示运行效果。
          </p>
        </div>
      )}
    </div>
  );
}
