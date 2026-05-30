import { type ClaudeRunResult, runClaude } from "./claudeRunner.js";
import { coerceVerdict, type PlanPhase, type Verdict } from "./schemas.js";

export interface ReviewerOptions {
  cwd: string;
  model?: string;
  bin?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}

export interface ReviewResult {
  ok: boolean;
  verdict?: Verdict;
  error?: string;
  raw: string;
}

export function buildReviewPrompt(phase: PlanPhase, diff: string): string {
  return [
    "You are a strict code reviewer. Review the DIFF for the phase below against its ACCEPTANCE CRITERIA.",
    "",
    "Respond with ONLY a single JSON object — no prose, no markdown, no code fences. Your ENTIRE response must start with { and end with }.",
    "",
    "The JSON must use exactly this shape:",
    "{",
    '  "pass": true,',
    '  "score": 0,',
    '  "summary": "short overall summary",',
    '  "findings": [{ "severity": "info|minor|major|critical", "file": "path", "note": "what is wrong" }],',
    '  "requiredChanges": ["concrete change the implementer must make"]',
    "}",
    "",
    "Set pass=true ONLY if ALL acceptance criteria are clearly met and the change is correct; otherwise pass=false with concrete requiredChanges. Judge from the diff and criteria below. Output JSON ONLY.",
    "",
    `PHASE: ${phase.title}`,
    `GOAL: ${phase.goal}`,
    "ACCEPTANCE CRITERIA:",
    ...phase.acceptanceCriteria.map((c, i) => `  ${i + 1}. ${c}`),
    "",
    "DIFF:",
    diff && diff.trim() ? diff : "(no diff captured — the executor may have made no changes)",
  ].join("\n");
}

/** Ask Claude (read-only) to review a phase's diff. Retries once if the output isn't valid JSON. */
export async function review(phase: PlanPhase, diff: string, opts: ReviewerOptions): Promise<ReviewResult> {
  let last: ClaudeRunResult | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    const reinforce =
      attempt === 0 ? "" : "\n\nIMPORTANT: your previous answer was NOT valid JSON. Output ONLY the JSON object — start with { and end with }, with no other text.";
    const r = await runClaude({
      prompt: buildReviewPrompt(phase, diff) + reinforce,
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
    if (!r.ok) return { ok: false, error: r.error ?? "reviewer failed", raw: r.raw };
    const v = coerceVerdict(r.structured);
    if (v) return { ok: true, verdict: v, raw: r.raw };
    if (opts.signal?.aborted) break;
  }
  const snippet = (last?.text || last?.raw || "").slice(0, 600);
  return { ok: false, error: `reviewer returned no valid verdict. Claude output: ${snippet}`, raw: last?.raw ?? "" };
}
