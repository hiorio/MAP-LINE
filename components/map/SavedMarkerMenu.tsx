'use client';

import type { Point } from '@/lib/geo/rdp';
import type { SavedPlace } from '@/lib/map/savedPlaces';
import type { Stop } from '@/lib/map/types';

/**
 * 보관함 마커를 탭했을 때 나오는 선택지.
 *
 * 이전에는 "핀 모드에서 마커를 탭하면 담긴다"였는데, 모드 안에 숨어 있어 아무도
 * 발견하지 못했다. 마커를 눌렀을 때 무엇을 할 수 있는지 그 자리에서 보여 준다.
 */
interface Props {
  point: Point;
  place: SavedPlace;
  stops: readonly Stop[];
  onAddAsStop: () => void;
  onAddToStop: (stopId: string) => void;
  onRemove: () => void;
  onClose: () => void;
}

export function SavedMarkerMenu({
  point,
  place,
  stops,
  onAddAsStop,
  onAddToStop,
  onRemove,
  onClose,
}: Props) {
  return (
    <>
      <button
        type="button"
        aria-label="닫기"
        onClick={onClose}
        className="absolute inset-0 z-30 cursor-default"
      />

      <div
        className="absolute z-40 w-60 -translate-x-1/2 overflow-hidden rounded-xl border border-hairline bg-white shadow-2xl"
        style={anchorStyle(point)}
      >
        <div className="border-b border-hairline px-3 py-2">
          <p className="truncate text-sm font-medium">{place.name}</p>
          <p className="mt-0.5 text-[11px] text-ink/45">보관함에 저장된 장소</p>
        </div>

        <button
          type="button"
          onClick={onAddAsStop}
          className="w-full border-b border-hairline px-3 py-2.5 text-left text-sm font-medium"
        >
          📍 새 단계로 담기
        </button>

        {stops.length > 0 && (
          <ul className="max-h-40 divide-y divide-hairline overflow-y-auto border-b border-hairline">
            {stops.map((stop, index) => (
              <li key={stop.id}>
                <button
                  type="button"
                  onClick={() => onAddToStop(stop.id)}
                  className="flex w-full items-center gap-2 px-3 py-2 text-left"
                >
                  <span className="grid size-5 shrink-0 place-items-center rounded-full bg-coral text-[11px] font-semibold text-white">
                    {index + 1}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm text-ink/70">
                    번 후보로 추가
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}

        <button
          type="button"
          onClick={onRemove}
          className="w-full px-3 py-2.5 text-left text-sm text-ink/55"
        >
          ☆ 보관함에서 빼기
        </button>
      </div>
    </>
  );
}

/** 누른 지점 위에 띄우되, 화면 위쪽이면 아래로 뒤집는다. */
function anchorStyle(point: Point): React.CSSProperties {
  const flipDown = point.y < 240;
  return flipDown
    ? { left: point.x, top: point.y + 16 }
    : { left: point.x, top: point.y - 16, transform: 'translate(-50%, -100%)' };
}
