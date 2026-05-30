// The preload-exposed bridge to the engine (typed via global.d.ts).
export const agent = window.agent;

export function fmtDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  const rem = s % 60;
  return `${m}m${rem.toString().padStart(2, "0")}s`;
}

export const STATE_LABEL: Record<string, string> = {
  queued: "排队",
  running: "运行中",
  done: "完成",
  error: "失败",
  canceled: "已取消",
};

export const RUN_STATUS_LABEL: Record<string, string> = {
  planning: "规划中",
  awaiting_plan_approval: "待批准计划",
  running: "执行中",
  awaiting_phase_approval: "待批准阶段",
  paused: "已暂停",
  needs_human: "待人工",
  done: "完成",
  failed: "失败",
  aborted: "已中止",
};

export const PHASE_STATUS_LABEL: Record<string, string> = {
  pending: "待执行",
  executing: "执行中",
  reviewing: "审查中",
  revising: "修订中",
  passed: "通过",
  failed: "失败",
  needs_human: "待人工",
};

// map run/phase status -> a dot color class (reuses task dot styles)
export const RUN_DOT: Record<string, string> = {
  planning: "running",
  running: "running",
  awaiting_plan_approval: "queued",
  awaiting_phase_approval: "queued",
  paused: "canceled",
  needs_human: "error",
  done: "done",
  failed: "error",
  aborted: "canceled",
};
