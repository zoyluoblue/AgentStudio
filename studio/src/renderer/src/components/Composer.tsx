import { type ReactNode, useState } from "react";

interface Props {
  busy: boolean;
  disabled: boolean;
  placeholder: string;
  onSend: (text: string) => void;
  onStop: () => void;
  /** extra controls rendered above the input (e.g. a solo target toggle) */
  extra?: ReactNode;
}

export function Composer({ busy, disabled, placeholder, onSend, onStop, extra }: Props) {
  const [text, setText] = useState("");
  const [composing, setComposing] = useState(false);

  const submit = () => {
    const t = text.trim();
    if (!t || disabled) return; // sending while busy = 插话
    onSend(t);
    setText("");
  };

  return (
    <div className="shrink-0 border-t border-outline-variant/20 p-gutter bg-surface">
      {extra}
      <div
        className={`flex items-end gap-2 bg-surface-container-low border border-outline-variant/30 rounded-xl py-2 pl-4 pr-2 transition-all focus-within:ring-2 focus-within:ring-primary/30 ${
          disabled ? "opacity-60" : ""
        }`}
      >
        <textarea
          className="flex-1 bg-transparent outline-none resize-none text-body-lg leading-snug max-h-32 py-1 placeholder:text-on-surface-variant/60"
          value={text}
          disabled={disabled}
          placeholder={placeholder}
          rows={1}
          onChange={(e) => setText(e.target.value)}
          onCompositionStart={() => setComposing(true)}
          onCompositionEnd={() => setComposing(false)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !composing && !e.nativeEvent.isComposing) {
              e.preventDefault();
              submit();
            }
          }}
        />
        {busy && (
          <button
            type="button"
            onClick={onStop}
            title="停止"
            className="w-9 h-9 shrink-0 rounded-lg bg-error/10 text-error flex items-center justify-center hover:bg-error/20 transition-colors"
          >
            <span className="material-symbols-outlined text-[18px]" style={{ fontVariationSettings: "'FILL' 1" }}>
              stop
            </span>
          </button>
        )}
        <button
          type="button"
          onClick={submit}
          disabled={disabled || !text.trim()}
          title="发送"
          className="w-9 h-9 shrink-0 rounded-lg bg-primary text-white flex items-center justify-center hover:opacity-90 active:scale-95 transition-all disabled:opacity-40"
        >
          <span className="material-symbols-outlined text-[20px]">arrow_upward</span>
        </button>
      </div>
      {busy && <p className="text-body-sm text-on-surface-variant mt-2 px-1">运行中 · 可随时输入「插话」给当前任务追加指令</p>}
    </div>
  );
}
