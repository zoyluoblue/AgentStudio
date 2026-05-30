import { useState } from "react";
import { agent, fmtDuration, PHASE_STATUS_LABEL, RUN_STATUS_LABEL } from "../api";
import type { PhaseRun, Run, TaskView } from "../types";
import { DiffView } from "./DiffView";

export function RunDetail({
  run,
  onApprovePlan,
  onApprovePhase,
  onPause,
  onResume,
  onAbort,
  onIntervene,
}: {
  run: Run;
  onApprovePlan: () => void;
  onApprovePhase: () => void;
  onPause: () => void;
  onResume: () => void;
  onAbort: () => void;
  onIntervene: (text: string) => void;
}) {
  const [interveneText, setInterveneText] = useState("");
  const active = run.status === "running" || run.status === "planning";
  const terminal = run.status === "done" || run.status === "failed" || run.status === "aborted";
  const passed = run.phases.filter((p) => p.status === "passed").length;

  return (
    <div>
      <div className="section">
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <b style={{ fontSize: 15 }}>{run.goal}</b>
          <span className="pill">{RUN_STATUS_LABEL[run.status] ?? run.status}</span>
        </div>
        {run.plan?.summary && <div className="muted" style={{ marginTop: 6 }}>{run.plan.summary}</div>}
        <div className="kv" style={{ marginTop: 6 }}>
          <span>阶段 <b>{passed}/{run.phases.length}</b></span>
          <span>用时 <b>{fmtDuration((run.finishedAt ?? Date.now()) - run.createdAt)}</b></span>
          <span>闸门 <b>{run.options.gateMode}</b></span>
        </div>
        {run.planError && <div style={{ color: "var(--red)", marginTop: 6 }}>规划失败：{run.planError}</div>}
        {run.error && !run.planError && <div style={{ color: "var(--red)", marginTop: 6 }}>{run.error}</div>}
      </div>

      <div className="actions" style={{ marginBottom: 14 }}>
        {run.status === "awaiting_plan_approval" && (
          <button className="primary" onClick={onApprovePlan}>
            批准计划，开始
          </button>
        )}
        {run.status === "awaiting_phase_approval" && (
          <button className="primary" onClick={onApprovePhase}>
            批准，继续下一阶段
          </button>
        )}
        {active && <button onClick={onPause}>暂停</button>}
        {(run.status === "paused" || run.status === "needs_human") && (
          <button className="primary" onClick={onResume}>
            继续
          </button>
        )}
        {!terminal && (
          <button className="danger" onClick={onAbort}>
            中止
          </button>
        )}
      </div>

      {!terminal && (
        <div className="section">
          <textarea
            rows={2}
            placeholder="给执行器追加指令（介入），下次执行/修订时带上…"
            value={interveneText}
            onChange={(e) => setInterveneText(e.target.value)}
          />
          <div className="actions">
            <button
              disabled={!interveneText.trim()}
              onClick={() => {
                onIntervene(interveneText);
                setInterveneText("");
              }}
            >
              注入指令
            </button>
          </div>
        </div>
      )}

      <div className="section">
        <h3>阶段（{passed}/{run.phases.length} 完成）</h3>
        {run.phases.length === 0 && (
          <div className="muted">{run.status === "planning" ? "Claude 正在规划…" : "（暂无阶段）"}</div>
        )}
        {run.phases.map((pr, i) => (
          <PhaseCard key={pr.phase.id} pr={pr} current={i === run.currentPhase && !terminal} />
        ))}
      </div>
    </div>
  );
}

function phaseDot(status: string): string {
  if (status === "passed") return "done";
  if (status === "needs_human" || status === "failed") return "error";
  if (status === "pending") return "queued";
  return "running";
}

function PhaseCard({ pr, current }: { pr: PhaseRun; current: boolean }) {
  const [open, setOpen] = useState(current);
  const [task, setTask] = useState<TaskView | null | undefined>(undefined);
  const v = pr.lastVerdict;

  async function loadDiff() {
    if (!pr.executeTaskId) return;
    setTask(await agent.getTask(pr.executeTaskId));
  }

  return (
    <div className="phasecard">
      <div className="phasehead" onClick={() => setOpen((o) => !o)}>
        <span className={`dot ${phaseDot(pr.status)}`} />
        <b style={{ flex: 1 }}>{pr.phase.title}</b>
        <span className="pill">{PHASE_STATUS_LABEL[pr.status] ?? pr.status}</span>
        {pr.iteration > 0 && <span className="muted">修订 {pr.iteration}</span>}
        {current && <span className="pill" style={{ borderColor: "var(--accent)", color: "var(--accent)" }}>当前</span>}
      </div>
      {open && (
        <div className="phasebody">
          <div className="muted">{pr.phase.goal}</div>
          <h4>代码规划</h4>
          <div className="console" style={{ maxHeight: 180 }}>{pr.phase.codePlan}</div>
          {pr.phase.uiPlan && pr.phase.uiPlan !== "N/A" && (
            <>
              <h4>UI 规划</h4>
              <div className="console" style={{ maxHeight: 180 }}>{pr.phase.uiPlan}</div>
            </>
          )}
          <h4>验收标准</h4>
          <ul className="crit">
            {pr.phase.acceptanceCriteria.map((c, i) => (
              <li key={i}>{c}</li>
            ))}
          </ul>
          {v && (
            <>
              <h4>审查结论：{v.pass ? "✓ 通过" : "✗ 未通过"}（{v.score}）</h4>
              <div className="muted">{v.summary}</div>
              {v.requiredChanges.length > 0 && (
                <ul className="crit">
                  {v.requiredChanges.map((c, i) => (
                    <li key={i} className="del">需改：{c}</li>
                  ))}
                </ul>
              )}
              {v.findings.length > 0 && (
                <ul className="crit">
                  {v.findings.map((f, i) => (
                    <li key={i}>
                      [{f.severity}] {f.file ? `${f.file}: ` : ""}
                      {f.note}
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}
          {pr.executeTaskId && (
            <div className="actions">
              <button onClick={loadDiff}>{task === undefined ? "查看本阶段改动" : "刷新改动"}</button>
            </div>
          )}
          {task?.diff && <DiffView patch={task.diff.patch} files={task.diff.files} format="line-by-line" />}
        </div>
      )}
    </div>
  );
}
