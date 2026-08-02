'use client';

import { useState } from 'react';
import { focusPlaces } from '@/lib/map/focusPlaces';
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

  /** 검색 결과에서 고른 것들. 한 번에 여러 곳을 담기 위한 것이다. */
  const [selected, setSelected] = useState<PlaceCandidate[]>([]);

  const places = useMapStore((s) => s.places);
  const addPlace = useMapStore((s) => s.addPlace);

  const isSelected = (candidate: PlaceCandidate) =>
    selected.some((s) => s.kakaoPlaceId === candidate.kakaoPlaceId && s.name === candidate.name);

  const toggle = (candidate: PlaceCandidate) => {
    setSelected((current) =>
      isSelected(candidate)
        ? current.filter((s) => !(s.kakaoPlaceId === candidate.kakaoPlaceId && s.name === candidate.name))
        : [...current, candidate],
    );
  };

  /** 고른 곳을 순서대로 담고, 전부 보이는 화면으로 옮긴 뒤 패널을 닫는다. */
  const commitSelection = () => {
    if (selected.length === 0) return;
    for (const candidate of selected) addPlace(placeFromCandidate(candidate));
    focusPlaces(map, selected.map((candidate) => candidate.location));
    setSelected([]);
    setCandidates([]);
    setQuery('');
    onClose();
  };

  const run = async (request: () => Promise<Response>) => {
    setStatus({ kind: 'loading' });
    setSelected([]);
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
                onClick={() => toggle(candidate)}
                aria-pressed={isSelected(candidate)}
                className={`flex w-full items-start gap-3 px-4 py-3 text-left ${
                  isSelected(candidate) ? 'bg-coral/5' : ''
                }`}
              >
                <span
                  aria-hidden
                  className={`mt-0.5 grid size-5 shrink-0 place-items-center rounded-md border text-[11px] font-semibold ${
                    isSelected(candidate)
                      ? 'border-coral bg-coral text-white'
                      : 'border-hairline text-transparent'
                  }`}
                >
                  ✓
                </span>
                <span className="min-w-0 flex-1">
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
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {places.length > 0 && <PlaceList onFocus={(location) => focusPlaces(map, [location])} />}

      {places.length === 0 && candidates.length === 0 && status.kind === 'idle' && (
        <p className="px-4 py-6 text-sm leading-relaxed text-ink/50">
          장소를 검색하거나, 카카오맵·네이버지도의 공유 텍스트를 그대로 붙여넣으세요.
          <br />
          지도에서 직접 찍으려면 <b>📍 핀</b> 모드로 원하는 지점을 탭하세요.
        </p>
      )}

      {/* 고른 게 있을 때만 나타난다. 목록을 스크롤해도 계속 보이도록 아래에 붙는다. */}
      {selected.length > 0 && (
        <div className="sticky bottom-0 border-t border-hairline bg-white p-3">
          <button
            type="button"
            onClick={commitSelection}
            className="flex h-11 w-full items-center justify-center rounded-xl bg-ink text-sm font-medium text-white"
          >
            {selected.length}곳 담기
          </button>
        </div>
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
