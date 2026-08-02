'use client';

import { useState } from 'react';
import { TRAVEL_MODES, formatDistance, type PlaceCandidate, type TravelMode } from '@/lib/map/types';
import { placeFromCandidate, useMapStore } from '@/store/useMapStore';

type Status = { kind: 'idle' } | { kind: 'loading' } | { kind: 'error'; message: string };

export function PlacePanel({
  onClose,
  map,
}: {
  onClose: () => void;
  map: kakao.maps.Map | null;
}) {
  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<PlaceCandidate[]>([]);
  const [status, setStatus] = useState<Status>({ kind: 'idle' });

  const places = useMapStore((s) => s.places);
  const addPlace = useMapStore((s) => s.addPlace);

  /** 검색해서 담은 장소는 화면 밖일 때가 대부분이다. 담았으면 거기로 데려다 준다. */
  const focus = (location: { lat: number; lng: number }) => {
    map?.setCenter(new kakao.maps.LatLng(location.lat, location.lng));
  };

  const run = async (request: () => Promise<Response>) => {
    setStatus({ kind: 'loading' });
    try {
      const response = await request();
      const body = (await response.json()) as { places?: PlaceCandidate[]; error?: string };
      if (!response.ok) {
        setCandidates(body.places ?? []);
        setStatus({ kind: 'error', message: body.error ?? '요청에 실패했습니다.' });
        return;
      }
      setCandidates(body.places ?? []);
      setStatus(
        body.places?.length
          ? { kind: 'idle' }
          : { kind: 'error', message: '검색 결과가 없습니다.' },
      );
    } catch {
      setStatus({ kind: 'error', message: '네트워크 오류입니다.' });
    }
  };

  /** 지금 보고 있는 지도 중심. 넘기면 가까운 곳부터 나온다. */
  const currentCenter = () => {
    const center = map?.getCenter();
    return center ? { lat: center.getLat(), lng: center.getLng() } : null;
  };

  const search = () => {
    if (!query.trim()) return;
    const center = currentCenter();
    const params = new URLSearchParams({ q: query.trim() });
    if (center) {
      params.set('lat', String(center.lat));
      params.set('lng', String(center.lng));
    }
    void run(() => fetch(`/api/search?${params}`));
  };

  /**
   * 붙여넣기 감지. 여러 줄이거나 URL이 섞여 있으면 타 지도 앱의 공유 텍스트로 본다.
   * 서버는 URL을 버리고 이름·지역만 뽑아 Kakao Local에 정식 재검색을 건다.
   */
  const handlePaste = (text: string) => {
    if (!/\n/.test(text) && !/https?:\/\//i.test(text)) return false;
    setQuery(text.split('\n')[0]?.trim() ?? '');
    void run(() =>
      fetch('/api/parse-share', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, center: currentCenter() }),
      }),
    );
    return true;
  };

  return (
    <div className="absolute inset-x-0 bottom-0 z-30 max-h-[70%] overflow-y-auto rounded-t-2xl border-t border-hairline bg-white shadow-2xl">
      <div className="sticky top-0 flex items-center gap-2 border-b border-hairline bg-white px-3 py-2">
        <input
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          // 한글 조합을 확정하는 Enter까지 검색으로 받으면 미완성 질의가 날아간다.
          onKeyDown={(e) => {
            if (!e.nativeEvent.isComposing && e.key === 'Enter') search();
          }}
          onPaste={(e) => {
            if (handlePaste(e.clipboardData.getData('text'))) e.preventDefault();
          }}
          placeholder="장소 검색 또는 공유 텍스트 붙여넣기"
          className="h-9 min-w-0 flex-1 rounded-lg border border-hairline px-3 text-sm outline-none"
        />
        <button
          type="button"
          onClick={search}
          className="h-9 shrink-0 rounded-lg bg-ink px-3 text-sm text-white"
        >
          검색
        </button>
        <button
          type="button"
          onClick={onClose}
          aria-label="닫기"
          className="h-9 shrink-0 rounded-lg border border-hairline px-3 text-sm"
        >
          닫기
        </button>
      </div>

      {status.kind === 'loading' && <p className="px-4 py-3 text-sm text-ink/50">찾는 중…</p>}
      {status.kind === 'error' && (
        <p className="px-4 py-3 text-sm text-coral">{status.message}</p>
      )}

      {candidates.length > 0 && (
        <ul className="divide-y divide-hairline">
          {candidates.map((candidate) => (
            <li key={`${candidate.kakaoPlaceId}-${candidate.name}`}>
              <button
                type="button"
                onClick={() => {
                  addPlace(placeFromCandidate(candidate));
                  focus(candidate.location);
                  setCandidates([]);
                  setQuery('');
                  // 담자마자 지도에서 확인할 수 있게 패널을 닫는다.
                  onClose();
                }}
                className="w-full px-4 py-3 text-left"
              >
                <span className="flex items-baseline gap-2">
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">
                    {candidate.name}
                  </span>
                  {candidate.distanceM !== undefined && (
                    <span className="shrink-0 text-xs tabular-nums text-ink/45">
                      {formatDistance(candidate.distanceM)}
                    </span>
                  )}
                </span>
                <span className="mt-0.5 block text-xs text-ink/55">
                  {candidate.category && <span className="text-ink/40">{candidate.category} · </span>}
                  {candidate.roadAddress ?? candidate.address ?? '주소 정보 없음'}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {places.length > 0 && <PlaceList onFocus={focus} />}

      {places.length === 0 && candidates.length === 0 && status.kind === 'idle' && (
        <p className="px-4 py-6 text-sm leading-relaxed text-ink/50">
          장소를 검색하거나, 카카오맵·네이버지도의 공유 텍스트를 그대로 붙여넣으세요.
          <br />
          지도에서 직접 찍으려면 <b>📍 장소</b> 모드로 원하는 지점을 탭하세요.
        </p>
      )}
    </div>
  );
}

/** 배열 순서가 곧 핀 번호이자 연결선의 방향이다. */
function PlaceList({ onFocus }: { onFocus: (location: { lat: number; lng: number }) => void }) {
  const places = useMapStore((s) => s.places);
  const movePlace = useMapStore((s) => s.movePlace);
  const removePlace = useMapStore((s) => s.removePlace);
  const updatePlace = useMapStore((s) => s.updatePlace);

  return (
    <div className="border-t border-hairline">
      <h2 className="px-4 pt-3 text-xs font-semibold tracking-wide text-ink/40">
        담은 장소 {places.length}곳
      </h2>
      <ol className="divide-y divide-hairline">
        {places.map((place, index) => (
          <li key={place.id} className="px-4 py-3">
            <div className="flex items-center gap-2">
              <span className="grid size-6 shrink-0 place-items-center rounded-full bg-coral text-xs font-semibold text-white">
                {index + 1}
              </span>
              <button
                type="button"
                onClick={() => onFocus(place.location)}
                className="min-w-0 flex-1 truncate text-left text-sm"
              >
                {place.name}
              </button>
              <button
                type="button"
                aria-label="위로"
                disabled={index === 0}
                onClick={() => movePlace(index, index - 1)}
                className="size-7 rounded border border-hairline text-xs disabled:opacity-30"
              >
                ▲
              </button>
              <button
                type="button"
                aria-label="아래로"
                disabled={index === places.length - 1}
                onClick={() => movePlace(index, index + 1)}
                className="size-7 rounded border border-hairline text-xs disabled:opacity-30"
              >
                ▼
              </button>
              <button
                type="button"
                aria-label="삭제"
                onClick={() => removePlace(place.id)}
                className="size-7 rounded border border-hairline text-xs"
              >
                ✕
              </button>
            </div>

            {index < places.length - 1 && (
              <div className="mt-2 flex items-center gap-1 pl-8">
                <span className="text-xs text-ink/35">다음까지</span>
                {TRAVEL_MODES.map(({ id, label }) => (
                  <button
                    key={id}
                    type="button"
                    aria-pressed={place.modeToNext === id}
                    onClick={() => updatePlace(place.id, { modeToNext: id satisfies TravelMode })}
                    className={`h-7 rounded-full border px-2.5 text-xs ${
                      place.modeToNext === id
                        ? 'border-ink bg-ink text-white'
                        : 'border-hairline text-ink/60'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}
