'use client';

import { useEffect, useState } from 'react';
import { STROKE_COLORS, STROKE_WIDTHS } from '@/lib/map/types';
import { useMapStore, type EditorMode } from '@/store/useMapStore';

const MODES: { id: EditorMode; label: string; icon: string }[] = [
  { id: 'pan', label: '이동', icon: '✋' },
  { id: 'place', label: '핀', icon: '📍' },
  { id: 'draw', label: '그리기', icon: '✏️' },
  { id: 'label', label: '라벨', icon: 'T' },
  { id: 'erase', label: '지우개', icon: '🧽' },
];

export function EditorToolbar() {
  const mode = useMapStore((s) => s.mode);
  const setMode = useMapStore((s) => s.setMode);
  const undo = useMapStore((s) => s.undo);
  const canUndo = useMapStore((s) => s.history.length > 0);

  return (
    <div className="z-30 shrink-0 border-t border-hairline bg-white">
      {mode === 'draw' && <StrokeOptions />}

      <div className="flex h-14 items-center gap-1 overflow-x-auto px-2">
        {MODES.map(({ id, label, icon }) => (
          <button
            key={id}
            type="button"
            onClick={() => setMode(id)}
            aria-pressed={mode === id}
            className={`h-9 shrink-0 rounded-lg border px-3 text-sm ${
              mode === id
                ? 'border-ink bg-ink text-white'
                : 'border-hairline bg-white text-ink'
            }`}
          >
            {icon} {label}
          </button>
        ))}

        <span className="mx-1 h-6 w-px shrink-0 bg-hairline" />

        <button
          type="button"
          onClick={undo}
          disabled={!canUndo}
          className="h-9 shrink-0 rounded-lg border border-hairline px-3 text-sm disabled:opacity-40"
        >
          ↩︎ 되돌리기
        </button>

        <ClearButton />
      </div>
    </div>
  );
}

function StrokeOptions() {
  const color = useMapStore((s) => s.color);
  const width = useMapStore((s) => s.width);
  const setColor = useMapStore((s) => s.setColor);
  const setWidth = useMapStore((s) => s.setWidth);

  return (
    <div className="flex h-12 items-center gap-2 border-b border-hairline px-3">
      {STROKE_COLORS.map((value) => (
        <button
          key={value}
          type="button"
          aria-label={`색상 ${value}`}
          aria-pressed={color === value}
          onClick={() => setColor(value)}
          style={{ background: value }}
          className={`size-7 rounded-full border-2 ${
            color === value ? 'border-ink' : 'border-transparent'
          }`}
        />
      ))}
      <span className="mx-1 h-6 w-px bg-hairline" />
      {STROKE_WIDTHS.map((value, index) => (
        <button
          key={value}
          type="button"
          aria-pressed={width === value}
          onClick={() => setWidth(value)}
          className={`h-8 rounded-lg border px-3 text-sm ${
            width === value ? 'border-ink bg-ink text-white' : 'border-hairline'
          }`}
        >
          {index === 0 ? '얇게' : '굵게'}
        </button>
      ))}
    </div>
  );
}

/**
 * confirm()은 인앱 브라우저나 대화상자 차단 상태에서 false를 반환한다.
 * 그러면 버튼이 조용히 아무 일도 안 하므로 두 번 누르기로 확인을 대신한다.
 */
function ClearButton() {
  const clearAll = useMapStore((s) => s.clearAll);
  const isEmpty = useMapStore((s) => s.places.length + s.strokes.length + s.labels.length === 0);
  const [armed, setArmed] = useArmedToggle();

  return (
    <button
      type="button"
      disabled={isEmpty}
      onClick={() => {
        if (!armed) {
          setArmed(true);
          return;
        }
        setArmed(false);
        clearAll();
      }}
      className={`h-9 shrink-0 rounded-lg border px-3 text-sm disabled:opacity-40 ${
        armed ? 'border-coral bg-coral text-white' : 'border-hairline'
      }`}
    >
      {armed ? '한 번 더 누르면 삭제' : '🗑 전체 지우기'}
    </button>
  );
}

function useArmedToggle(timeoutMs = 3000) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const timer = setTimeout(() => setArmed(false), timeoutMs);
    return () => clearTimeout(timer);
  }, [armed, timeoutMs]);
  return [armed, setArmed] as const;
}
