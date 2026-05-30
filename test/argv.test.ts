import { describe, it, expect } from "vitest";
import { buildExecArgv, buildResumeArgv } from "../src/executor/codex/argv";
import type { StartArgs } from "../src/executor/types";

function base(overrides: Partial<StartArgs> = {}): StartArgs {
  return { prompt: "do the thing\nwith newlines", cwd: "/repo", sandbox: "workspace-write", ...overrides };
}

describe("buildExecArgv", () => {
  it("always sets sandbox and forces approval_policy=never", () => {
    const { argv } = buildExecArgv(base(), { tmpDir: "/tmp/x" });
    expect(argv).toContain("-s");
    expect(argv[argv.indexOf("-s") + 1]).toBe("workspace-write");
    expect(argv).toContain("-c");
    expect(argv).toContain('approval_policy="never"');
  });

  it("delivers the prompt via stdin (trailing '-'), never as an argv element", () => {
    const args = base();
    const { argv } = buildExecArgv(args, { tmpDir: "/tmp/x" });
    expect(argv[argv.length - 1]).toBe("-");
    expect(argv).not.toContain(args.prompt);
    expect(argv.some((a) => a.includes("do the thing"))).toBe(false);
  });

  it("includes -C cwd and -o output file", () => {
    const { argv, outputFile } = buildExecArgv(base({ cwd: "/repo" }), { tmpDir: "/tmp/x" });
    expect(argv[argv.indexOf("-C") + 1]).toBe("/repo");
    expect(argv).toContain("-o");
    expect(outputFile).toBe("/tmp/x/last-message.txt");
  });

  it("adds --output-schema only when a schema is provided", () => {
    const without = buildExecArgv(base(), { tmpDir: "/tmp/x" });
    expect(without.argv).not.toContain("--output-schema");
    expect(without.schemaFile).toBeUndefined();

    const withSchema = buildExecArgv(base({ outputSchema: { type: "object" } }), { tmpDir: "/tmp/x" });
    expect(withSchema.argv).toContain("--output-schema");
    expect(withSchema.schemaFile).toBe("/tmp/x/schema.json");
  });

  it("repeats --add-dir per entry and adds -m when model is set", () => {
    const { argv } = buildExecArgv(base({ addDirs: ["/a", "/b"], model: "gpt-x" }), { tmpDir: "/tmp/x" });
    expect(argv.filter((a) => a === "--add-dir").length).toBe(2);
    expect(argv[argv.indexOf("-m") + 1]).toBe("gpt-x");
  });

  it("never interpolates a dangerous prompt into argv (no shell, prompt via stdin)", () => {
    const { argv } = buildExecArgv(base({ prompt: "rm -rf / ; echo $(whoami)" }), { tmpDir: "/tmp/x" });
    expect(argv.join(" ")).not.toContain("whoami");
  });

  it("enables network for workspace-write (installs) but not for read-only", () => {
    const ws = buildExecArgv(base({ sandbox: "workspace-write" }), { tmpDir: "/tmp/x" });
    expect(ws.argv.join(" ")).toContain("sandbox_workspace_write.network_access=true");
    const ro = buildExecArgv(base({ sandbox: "read-only" }), { tmpDir: "/tmp/x" });
    expect(ro.argv.join(" ")).not.toContain("network_access");
  });
});

describe("buildResumeArgv", () => {
  it("builds `exec resume <id>` with sandbox via -c, and no -s/-C/--output-schema (unsupported by resume)", () => {
    const { argv } = buildResumeArgv(base({ outputSchema: { type: "object" } }), { tmpDir: "/tmp/x" }, "sess-123");
    expect(argv.slice(0, 3)).toEqual(["exec", "resume", "sess-123"]);
    expect(argv).toContain("--json");
    expect(argv).toContain('sandbox_mode="workspace-write"');
    expect(argv).not.toContain("-s");
    expect(argv).not.toContain("-C");
    expect(argv).not.toContain("--output-schema");
    expect(argv[argv.length - 1]).toBe("-");
  });

  it("includes -o output file and forces approval_policy=never", () => {
    const { argv, outputFile } = buildResumeArgv(base(), { tmpDir: "/tmp/x" }, "sess-1");
    expect(argv).toContain("-o");
    expect(outputFile).toBe("/tmp/x/last-message.txt");
    expect(argv).toContain('approval_policy="never"');
  });
});
