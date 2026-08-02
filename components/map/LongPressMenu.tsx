'use client';

import { useEffect, useState } from 'react';
import type { Point } from '@/lib/geo/rdp';
import { formatDistance, type LatLng, type PlaceCandidate } from '@/lib/map/types';

/**
 * 지도를 꾹 눌렀을 때 나오는 선택지.
 *
 * 화면에 보이는 가게를 눌렀는데 좌표만 찍히면 이름을 직접 쳐야 한다. 그래서 먼저
 * 그 자리 주변의 장소를 찾아 보여 주고, 마땅한 게 없으면 그 지점에 직접 핀을 꽂거나
 * 메모를 남길 수 있게 한다.
 */
interface Props {
  point: Point;
  coord: LatLng;
  onPickPlace: (candidate: PlaceCandidate) => void;
  onDropPin: () => void;
  onAddLabel: () => void;
  onClose: () => void;
}

type Status = 'loading' | 'ready' | 'failed';

export function LongPressMenu({
  point,
  coord,
  onPickPlace,
  onDropPin,
  onAddLabel,
  onClose,
}: Props) {
  const [places, setPlaces] = useState<PlaceCandidate[]>([]);
  const [address, setAddress] = useState<string | undefined>();
  const [status, setStatus] = useState<Status>('loading');

  useEffect(() => {
    let cancelled = false;
    const params = new URLSearchParams({ lat: String(coord.lat), lng: String(coord.lng) });

    void fetch(`/api/nearby?${params}`)
      .then((response) => response.json())
      .then((body: { places?: PlaceCandidate[]; address?: string }) => {
        if (cancelled) return;
        setPlaces(body.places ?? []);
        setAddress(body.address);
        setStatus('ready');
      })
      .catch(() => {
        // 주변을 못 찾아도 직접 핀은 꽂을 수 있어야 한다.
        if (!cancelled) setStatus('failed');
      });

    return () => {
      cancelled = true;
    };
  }, [coord.lat, coord.lng]);

  return (
    <>
      {/* 바깥을 누르면 닫는다. 지도가 뒤에서 움직이지 않도록 덮어 둔다. */}
      <button
        type="button"
        aria-label="닫기"
        onClick={onClose}
        className="absolute inset-0 z-30 cursor-default"
      />

      {/* 누른 자리를 가리키는 점 */}
      <span
        aria-hidden
        className="pointer-events-none absolute z-40 size-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white bg-ink shadow"
        style={{ left: point.x, top: point.y }}
      />

      <div
        className="absolute z-40 w-64 -translate-x-1/2 overflow-hidden rounded-xl border border-hairline bg-white shadow-2xl"
        style={anchorStyle(point)}
      >
        {address && (
          <p className="truncate border-b border-hairline px-3 py-2 text-[11px] text-ink/45">
            {address}
          </p>
        )}

        {status === 'loading' && (
          <p className="px-3 py-3 text-sm text-ink/50">주변을 찾는 중…</p>
        )}

        {status === 'ready' && places.length > 0 && (
          <ul className="max-h-56 divide-y divide-hairline overflow-y-auto">
            {places.map((place) => (
              <li key={`${place.kakaoPlaceId}-${place.name}`}>
                <button
                  type="button"
                  onClick={() => onPickPlace(place)}
                  className="flex w-full items-baseline gap-2 px-3 py-2.5 text-left"
                >
                  <span className="min-w-0 flex-1 truncate text-sm">{place.name}</span>
                  {place.distanceM !== undefined && (
                    <span className="shrink-0 text-[11px] tabular-nums text-ink/40">
                      {formatDistance(place.distanceM)}
                    </span>
                  )}
                </button>
              </li>
            ))}
          </ul>
        )}

        {status === 'ready' && places.length === 0 && (
          <p className="px-3 py-3 text-sm text-ink/50">주변에 등록된 장소가 없습니다.</p>
        )}

        {status === 'failed' && (
          <p className="px-3 py-3 text-sm text-ink/50">주변을 찾지 못했습니다.</p>
        )}

        <div className="flex border-t border-hairline">
          <button
            type="button"
            onClick={onDropPin}
            className="flex-1 border-r border-hairline px-3 py-2.5 text-sm font-medium"
          >
            📍 여기에 핀
          </button>
          <button type="button" onClick={onAddLabel} className="flex-1 px-3 py-2.5 text-sm font-medium">
            T 메모
          </button>
        </div>
      </div>
    </>
  );
}

/** 누른 지점 위에 띄우되, 화면 위쪽이면 아래로 뒤집는다. */
function anchorStyle(point: Point): React.CSSProperties {
  const flipDown = point.y < 260;
  return flipDown
    ? { left: point.x, top: point.y + 16 }
    : { left: point.x, top: point.y - 16, transform: 'translate(-50%, -100%)' };
}
