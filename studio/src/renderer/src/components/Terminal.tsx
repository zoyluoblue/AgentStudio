import { useEffect, useRef, useState } from "react";

const TABS = ["Terminal", "Output", "Debug Console"];

function lineClass(l: string): string {
  if (/error|fail|✖|✗|401/i.test(l)) return "text-red-400";
  if (/warn|deprecat/i.test(l)) return "text-yellow-400";
  if (/done|success|✅|ready|connected/i.test(l)) return "text-green-400";
  return "text-white/70";
}
function fmt(l: string): string {
  const m = l.match(/T(\d{2}:\d{2}:\d{2})/);
  const rest = l.replace(/^\S+\s/, "");
  return `${m ? m[1] : ""}  ${rest}`;
}

export function Terminal() {
  const [lines, setLines] = useState<string[]>([]);
  const [tab, setTab] = useState(0);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const off = window.studio.onLog((line) => setLines((p) => [...p, line].slice(-300)));
    return off;
  }, []);
  useEffect(() => {
    endRef.current?.scrollIntoView();
  }, [lines]);

  return (
    <div className="h-48 shrink-0 bg-[#1e1e1e] rounded-xl border border-white/5 flex flex-col overflow-hidden shadow-2xl">
      <div className="h-8 shrink-0 border-b border-white/10 flex items-center px-4 gap-4">
        {TABS.map((t, i) => (
          <button
            type="button"
            key={t}
            onClick={() => setTab(i)}
            className={`text-[11px] font-bold h-full px-2 ${i === tab ? "text-white border-b-2 border-primary" : "text-white/40 hover:text-white/70"}`}
          >
            {t}
          </button>
        ))}
      </div>
      <div className="flex-1 p-3 font-code text-[12px] overflow-y-auto scrollbar-hide">
        {lines.length === 0 ? (
          <div className="text-white/40">
            <span className="text-blue-400">➜</span> agent-connector ready — 等待日志…
          </div>
        ) : (
          lines.map((l, i) => (
            <div key={`${i}-${l.slice(0, 12)}`} className={lineClass(l)}>
              {fmt(l)}
            </div>
          ))
        )}
        <div ref={endRef} />
      </div>
    </div>
  );
}
