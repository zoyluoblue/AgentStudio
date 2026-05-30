import { type ClaudeRunResult, runClaude } from "./claudeRunner.js";
import { coercePlan, type Plan } from "./schemas.js";

export interface PlannerOptions {
  cwd: string;
  model?: string;
  bin?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}

export interface PlanResult {
  ok: boolean;
  plan?: Plan;
  error?: string;
  raw: string;
}

export function buildPlanPrompt(goal: string): string {
  return [
    "You are the technical lead for this repository. Break the GOAL below into an ordered sequence of implementation PHASES.",
    "",
    "Respond with ONLY a single JSON object — no prose, no explanation, no markdown, no code fences. Your ENTIRE response must start with { and end with }.",
    "",
    "The JSON must use exactly this shape:",
    "{",
    '  "summary": "one-line summary of the whole plan",',
    '  "phases": [',
    "    {",
    '      "id": "phase-1",',
    '      "title": "short phase name",',
    '      "goal": "what this phase accomplishes",',
    '      "codePlan": "a detailed, concrete code plan (modules/functions/changes)",',
    '      "uiPlan": "the UI plan, or \\"N/A\\" if no UI",',
    '      "acceptanceCriteria": ["concrete checkable criterion", "another"],',
    '      "filesLikely": ["path/one"],',
    '      "dependsOn": []',
    "    }",
    "  ]",
    "}",
    "",
    "Rules: 2-6 ordered phases, each independently reviewable and building on prior ones. Plan from the goal directly. Output JSON ONLY.",
    "",
    "GOAL:",
    goal,
  ].join("\n");
}

/** Ask Claude (read-only) for a structured multi-phase plan. Retries once if the output isn't valid JSON. */
export async function plan(goal: string, opts: PlannerOptions): Promise<PlanResult> {
  let last: ClaudeRunResult | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    const reinforce =
      attempt === 0 ? "" : "\n\nIMPORTANT: your previous answer was NOT valid JSON. Output ONLY the JSON object — start with { and end with }, with no other text.";
    const r = await runClaude({
      prompt: buildPlanPrompt(goal) + reinforce,
      cwd: opts.cwd,
      systemPrompt:
        "You are a structured-output engine. Respond with exactly one JSON object and nothing else — no prose, no markdown, no code fences. Begin with { and end with }.",
      model: opts.model,
      readOnly: true,
      bin: opts.bin,
      signal: opts.signal,
      timeoutMs: opts.timeoutMs ?? 300_000,
    });
    last = r;
    if (!r.ok) return { ok: false, error: r.error ?? "planner failed", raw: r.raw };
    const p = coercePlan(r.structured);
    if (p) return { ok: true, plan: p, raw: r.raw };
    if (opts.signal?.aborted) break;
  }
  const snippet = (last?.text || last?.raw || "").slice(0, 600);
  return { ok: false, error: `planner returned no valid plan. Claude output: ${snippet}`, raw: last?.raw ?? "" };
}
