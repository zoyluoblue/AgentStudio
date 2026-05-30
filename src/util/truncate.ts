export interface TruncateResult {
  text: string;
  truncated: boolean;
  totalBytes: number;
}

/**
 * Keep the head and tail of a large string, eliding the middle. Byte counts
 * are exact (UTF-8); the slice boundaries are by code unit, which is fine for
 * diffs/logs where we only need an approximate budget.
 */
export function truncateHeadTail(input: string, maxBytes: number): TruncateResult {
  const totalBytes = Buffer.byteLength(input, "utf8");
  if (totalBytes <= maxBytes) {
    return { text: input, truncated: false, totalBytes };
  }
  const half = Math.max(1, Math.floor(maxBytes / 2));
  const head = input.slice(0, half);
  const tail = input.slice(Math.max(half, input.length - half));
  const omitted = totalBytes - Buffer.byteLength(head, "utf8") - Buffer.byteLength(tail, "utf8");
  return {
    text: `${head}\n\n... [truncated ${omitted} bytes] ...\n\n${tail}`,
    truncated: true,
    totalBytes,
  };
}

/** Append to a bounded array, dropping oldest entries past `max`. */
export function pushBounded<T>(buf: T[], item: T, max: number): void {
  buf.push(item);
  while (buf.length > max) buf.shift();
}
