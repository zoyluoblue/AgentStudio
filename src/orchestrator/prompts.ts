import type { PhaseRun, Run } from "./runTypes.js";

function completedContext(run: Run, uptoIdx: number): string {
  const done = run.phases.slice(0, uptoIdx).filter((p) => p.status === "passed");
  if (done.length === 0) return "";
  return "Already completed phases: " + done.map((p) => p.phase.title).join("; ");
}

export function buildExecutePrompt(run: Run, pr: PhaseRun, idx: number): string {
  const p = pr.phase;
  return [
    `Overall goal: ${run.goal}`,
    run.plan?.summary ? `Plan summary: ${run.plan.summary}` : "",
    completedContext(run, idx),
    "",
    "Implement THIS phase only (do not do later phases):",
    `Phase: ${p.title}`,
    `Goal: ${p.goal}`,
    `Code plan:\n${p.codePlan}`,
    p.uiPlan && p.uiPlan !== "N/A" ? `UI plan:\n${p.uiPlan}` : "",
    "Acceptance criteria (all must be met):",
    ...p.acceptanceCriteria.map((c, i) => `  ${i + 1}. ${c}`),
    p.filesLikely && p.filesLikely.length ? `Files likely involved: ${p.filesLikely.join(", ")}` : "",
    run.intervene ? `Extra instructions from the human: ${run.intervene}` : "",
    "",
    "Environment: the shell is NON-interactive but HAS network access. Use non-interactive flags (e.g. `create-next-app --yes`, `npm install`, `pip install`) and never wait for interactive prompts. Actually create the files/install the deps — do not just describe them.",
    "Make the changes now, focused on this phase.",
  ]
    .filter(Boolean)
    .join("\n");
}

export function buildRevisePrompt(run: Run, pr: PhaseRun): string {
  const v = pr.lastVerdict;
  return [
    `Revise phase "${pr.phase.title}". A review found it does not yet meet the acceptance criteria.`,
    "Required changes:",
    ...(v?.requiredChanges ?? []).map((c, i) => `  ${i + 1}. ${c}`),
    v?.findings && v.findings.length
      ? "Findings:\n" + v.findings.map((f) => `  - [${f.severity}] ${f.file ? `${f.file}: ` : ""}${f.note}`).join("\n")
      : "",
    "Acceptance criteria:",
    ...pr.phase.acceptanceCriteria.map((c, i) => `  ${i + 1}. ${c}`),
    run.intervene ? `Extra instructions from the human: ${run.intervene}` : "",
    "",
    "Apply the required changes now.",
  ]
    .filter(Boolean)
    .join("\n");
}
