import { useState } from "react";
import type { GateMode, Run, RunStartInput } from "../types";

const GATES: { v: GateMode; label: string }[] = [
  { v: "auto", label: "全自动（Claude 审查即闸门）" },
  { v: "manual_plan", label: "计划需我确认" },
  { v: "manual_phase", label: "每阶段需我确认" },
  { v: "manual_both", label: "计划 + 每阶段都确认" },
];

export function NewRun({ isRepo, onStart }: { isRepo: boolean; onStart: (input: RunStartInput) => Promise<Run> }) {
  const [goal, setGoal] = useState("");
  const [gateMode, setGateMode] = useState<GateMode>("auto");
  const [maxReviseIters, setMaxReviseIters] = useState(3);
  const [busy, setBusy] = useState(false);

  async function start() {
    if (!goal.trim()) return;
    setBusy(true);
    try {
      await onStart({ goal, gateMode, maxReviseIters });
      setGoal("");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="section">
        <h3>新建编排 Run</h3>
        <textarea
          rows={8}
          placeholder="描述高层目标。Claude 会拆成阶段（含代码/UI规划+验收标准），Codex 逐阶段执行，Claude 审查，循环至完成…"
          value={goal}
          onChange={(e) => setGoal(e.target.value)}
        />
      </div>

      <label className="field">闸门</label>
      <select value={gateMode} onChange={(e) => setGateMode(e.target.value as GateMode)}>
        {GATES.map((g) => (
          <option key={g.v} value={g.v}>
            {g.label}
          </option>
        ))}
      </select>

      <label className="field">每阶段最大修订次数</label>
      <input type="number" min={0} max={6} value={maxReviseIters} onChange={(e) => setMaxReviseIters(Number(e.target.value) || 0)} />

      <div className="actions">
        <button className="primary" disabled={busy || !goal.trim()} onClick={start}>
          {busy ? "启动中…" : "▶ 启动 Run"}
        </button>
      </div>
      {!isRepo && <div className="muted" style={{ marginTop: 8 }}>非 git 目录也可：改动用文件快照对比。</div>}
    </div>
  );
}
