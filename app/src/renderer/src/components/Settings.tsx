import { agent } from "../api";
import type { ConfigView, ExecutorInfo } from "../types";

function capList(c: ExecutorInfo["capabilities"]): string {
  const o: string[] = [];
  if (c.jsonEvents) o.push("events");
  if (c.structuredOutput) o.push("schema");
  if (c.cancel) o.push("cancel");
  if (c.resume) o.push("resume");
  if (c.nativeReview) o.push("review");
  return o.join(" · ");
}

export function Settings({
  config,
  executors,
  onClose,
}: {
  config: ConfigView | null;
  executors: ExecutorInfo[];
  onClose: () => void;
}) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <b>设置</b>
          <button onClick={onClose}>关闭 (Esc)</button>
        </div>

        <div className="section">
          <h3>默认配置（只读 · 改用环境变量或 .agentconnector.json）</h3>
          {config ? (
            <div className="kv col">
              <span>默认执行器 <b>{config.defaultExecutor}</b></span>
              <span>默认沙箱 <b>{config.defaultSandbox}</b></span>
              <span>Task 执行沙箱 <b>{config.runSandbox}</b>（装包/脚手架需 full access；改 AGENTCONNECTOR_RUN_SANDBOX）</span>
              <span>默认隔离 <b>{config.defaultIsolation}</b></span>
              <span>最大并发 <b>{config.maxConcurrent}</b></span>
              <span>默认重试 <b>{config.maxRetries}</b></span>
              <span>diff 上限 <b>{config.maxDiffBytes} 字节</b></span>
              <span>日志级别 <b>{config.logLevel}</b></span>
              <span>状态目录 <b>{config.stateDir}</b></span>
            </div>
          ) : (
            <span className="muted">加载中…</span>
          )}
        </div>

        <div className="section">
          <h3>执行器后端</h3>
          <table className="tbl">
            <thead>
              <tr>
                <th>名称</th>
                <th>可用</th>
                <th>能力</th>
              </tr>
            </thead>
            <tbody>
              {executors.map((x) => (
                <tr key={x.name}>
                  <td>
                    {x.name}
                    {x.experimental ? " · exp" : ""}
                  </td>
                  <td className={x.available ? "add" : "del"}>{x.available ? "✓" : "✗ 未安装"}</td>
                  <td className="muted">{capList(x.capabilities)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {config?.logFile && (
          <div className="section">
            <h3>日志</h3>
            <div className="muted" style={{ wordBreak: "break-all" }}>{config.logFile}</div>
            <div className="actions">
              <button onClick={() => void agent.openLogs()}>打开日志目录</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
