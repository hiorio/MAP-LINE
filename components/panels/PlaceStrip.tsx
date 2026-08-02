'use client';

import type { ReactNode } from 'react';
import type { LatLng, Stop } from '@/lib/map/types';

/**
 * 담은 단계를 항상 보이게 두는 가로 목록.
 *
 * 편집기와 뷰어가 같은 컴포넌트를 쓴다. 만든 사람이 본 순서·이름이 공유받은 사람에게도
 * 똑같이 보여야 한다.
 *
 * 후보가 여러 개인 단계는 "첫 후보 외 N곳"으로 줄여 보여 준다. 전부 늘어놓으면
 * 한 줄에 담기지 않고, 자세한 목록은 패널에서 본다.
 */
export function PlaceStrip({
  stops,
  onFocus,
  trailing,
}: {
  stops: readonly Stop[];
  onFocus: (location: LatLng) => void;
  /** 편집기에서 목록 열기 같은 추가 동작을 오른쪽에 붙일 때 */
  trailing?: ReactNode;
}) {
  if (stops.length === 0) return null;

  return (
    <div className="z-30 flex shrink-0 items-center gap-2 border-t border-hairline bg-white px-3 py-2">
      <ol className="flex min-w-0 flex-1 gap-2 overflow-x-auto">
        {stops.map((stop, index) => {
          const first = stop.candidates[0];
          if (!first) return null;
          const extra = stop.candidates.length - 1;

          return (
            <li key={stop.id}>
              <button
                type="button"
                onClick={() => onFocus(first.location)}
                title={stop.candidates.map((place) => place.name).join(', ')}
                className="flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-hairline px-3 text-sm"
              >
                <span className="grid size-5 shrink-0 place-items-center rounded-full bg-coral text-[11px] font-semibold text-white">
                  {index + 1}
                </span>
                <span className="max-w-36 truncate">{first.name}</span>
                {extra > 0 && (
                  <span className="shrink-0 text-xs text-ink/45">외 {extra}곳</span>
                )}
              </button>
            </li>
          );
        })}
      </ol>
      {trailing}
    </div>
  );
}
