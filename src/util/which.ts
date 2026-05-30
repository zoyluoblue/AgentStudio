import { spawnSync } from "node:child_process";

const cache = new Map<string, boolean>();

/** Whether `bin` is resolvable on PATH (cached). Used for executor availability. */
export function binExists(bin: string): boolean {
  const cached = cache.get(bin);
  if (cached !== undefined) return cached;
  let ok = false;
  try {
    const r = spawnSync("which", [bin], { stdio: "ignore" });
    ok = r.status === 0;
  } catch {
    ok = false;
  }
  cache.set(bin, ok);
  return ok;
}

/** Test seam: clear the availability cache. */
export function clearBinCache(): void {
  cache.clear();
}
