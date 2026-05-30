import { randomUUID } from "node:crypto";

/** Short, human-greppable task id, e.g. "tsk_1a2b3c4d". */
export function newTaskId(): string {
  return "tsk_" + randomUUID().slice(0, 8);
}
