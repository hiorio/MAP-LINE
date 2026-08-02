'use client';

import type { ReactNode } from 'react';
import type { Place } from '@/lib/map/types';

/**
 * 담은 장소를 항상 보이게 두는 가로 목록.
 *
 * 편집기와 뷰어가 같은 컴포넌트를 쓴다. 만든 사람이 본 순서·이름이 공유받은 사람에게도
 * 똑같이 보여야 한다.
 *
 * 지도 위에 겹치지 않고 아래에 붙는다. 지도를 가리면 정작 확인하려던 것이 안 보인다.
 */
export function PlaceStrip({
  places,
  onFocus,
  trailing,
}: {
  places: readonly Place[];
  onFocus: (place: Place) => void;
  /** 편집기에서 목록 열기 같은 추가 동작을 오른쪽에 붙일 때 */
  trailing?: ReactNode;
}) {
  if (places.length === 0) return null;

  return (
    <div className="z-30 flex shrink-0 items-center gap-2 border-t border-hairline bg-white px-3 py-2">
      <ol className="flex min-w-0 flex-1 gap-2 overflow-x-auto">
        {places.map((place, index) => (
          <li key={place.id}>
            <button
              type="button"
              onClick={() => onFocus(place)}
              title={place.name}
              className="flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-hairline px-3 text-sm"
            >
              <span className="grid size-5 shrink-0 place-items-center rounded-full bg-coral text-[11px] font-semibold text-white">
                {index + 1}
              </span>
              <span className="max-w-40 truncate">{place.name}</span>
            </button>
          </li>
        ))}
      </ol>
      {trailing}
    </div>
  );
}
