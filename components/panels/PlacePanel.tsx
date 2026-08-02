'use client';

import { useState } from 'react';
import { focusPlaces } from '@/lib/map/focusPlaces';
import { formatDistance, type PlaceCandidate } from '@/lib/map/types';
import { placeFromCandidate, useMapStore } from '@/store/useMapStore';

type Status = { kind: 'idle' } | { kind: 'loading' } | { kind: 'error'; message: string };

export function PlacePanel({
  onClose,
  map,
  /** 값이 있으면 고른 장소를 새 단계가 아니라 이 단계의 후보로 더한다. */
  targetStopId,
  onTargetStopChange,
}: {
  onClose: () => void;
  map: kakao.maps.Map | null;
  targetStopId: string | null;
  onTargetStopChange: (stopId: string | null) => void;
}) {
  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<PlaceCandidate[]>([]);
  const [status, setStatus] = useState<Status>({ kind: 'idle' });

  /** 검색 결과에서 고른 것들. 한 번에 여러 곳을 담기 위한 것이다. */
  const [selected, setSelected] = useState<PlaceCandidate[]>([]);

  const stops = useMapStore((s) => s.stops);
  const addStop = useMapStore((s) => s.addStop);
  const addCandidates = useMapStore((s) => s.addCandidates);

  const targetIndex = stops.findIndex((stop) => stop.id === targetStopId);

  const isSelected = (candidate: PlaceCandidate) =>
    selected.some((s) => s.kakaoPlaceId === candidate.kakaoPlaceId && s.name === candidate.name);

  const toggle = (candidate: PlaceCandidate) => {
    setSelected((current) =>
      isSelected(candidate)
        ? current.filter((s) => !(s.kakaoPlaceId === candidate.kakaoPlaceId && s.name === candidate.name))
        : [...current, candidate],
    );
  };

  /**
   * 고른 곳을 담는다. 대상 단계가 지정돼 있으면 그 단계의 후보로 더하고,
   * 아니면 고른 것들을 묶어 새 단계 하나를 만든다.
   */
  const commitSelection = () => {
    if (selected.length === 0) return;
    const places = selected.map(placeFromCandidate);

    if (targetStopId) addCandidates(targetStopId, places);
    else addStop(places);

    focusPlaces(map, places.map((place) => place.location));
    setSelected([]);
    setCandidates([]);
    setQuery('');
    onTargetStopChange(null);
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

      {targetIndex >= 0 && (
        <div className="flex items-center gap-2 border-b border-hairline bg-coral/5 px-4 py-2 text-xs">
          <span className="grid size-5 shrink-0 place-items-center rounded-full bg-coral font-semibold text-white">
            {targetIndex + 1}
          </span>
          <span className="flex-1 text-ink/60">이 단계의 후보로 담습니다</span>
          <button
            type="button"
            onClick={() => onTargetStopChange(null)}
            className="shrink-0 rounded border border-hairline px-2 py-0.5"
          >
            새 단계로
          </button>
        </div>
      )}

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

      {stops.length > 0 && (
        <StopList
          onFocus={(location) => focusPlaces(map, [location])}
          onAddCandidates={onTargetStopChange}
        />
      )}

      {stops.length === 0 && candidates.length === 0 && status.kind === 'idle' && (
        <p className="px-4 py-6 text-sm leading-relaxed text-ink/50">
          장소를 검색하거나, 카카오맵·네이버지도의 공유 텍스트를 그대로 붙여넣으세요.
          <br />
          여러 곳을 고르면 한 단계의 <b>후보</b>로 함께 담깁니다.
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
            {targetIndex >= 0
              ? `${targetIndex + 1}번 후보로 ${selected.length}곳 추가`
              : `새 단계로 ${selected.length}곳 담기`}
          </button>
        </div>
      )}
    </div>
  );
}

/**
 * 담은 단계와 그 후보들.
 *
 * 번호 하나가 코스의 한 단계이고, 그 안에 후보가 여러 개 들어간다.
 * "2번은 점심인데 어디로 갈지는 아직 안 정했다"를 그대로 담기 위한 구조다.
 */
function StopList({
  onFocus,
  onAddCandidates,
}: {
  onFocus: (location: { lat: number; lng: number }) => void;
  onAddCandidates: (stopId: string) => void;
}) {
  const stops = useMapStore((s) => s.stops);
  const moveStop = useMapStore((s) => s.moveStop);
  const removeStop = useMapStore((s) => s.removeStop);
  const removeCandidate = useMapStore((s) => s.removeCandidate);

  return (
    <div className="border-t border-hairline">
      <h2 className="px-4 pt-3 text-xs font-semibold tracking-wide text-ink/40">
        담은 단계 {stops.length}개
      </h2>
      <ol className="divide-y divide-hairline">
        {stops.map((stop, index) => (
          <li key={stop.id} className="px-4 py-3">
            <div className="flex items-center gap-2">
              <span className="grid size-6 shrink-0 place-items-center rounded-full bg-coral text-xs font-semibold text-white">
                {index + 1}
              </span>
              <span className="min-w-0 flex-1 text-sm text-ink/55">
                후보 {stop.candidates.length}곳
              </span>
              <button
                type="button"
                aria-label="위로"
                disabled={index === 0}
                onClick={() => moveStop(index, index - 1)}
                className="size-7 rounded border border-hairline text-xs disabled:opacity-30"
              >
                &#9650;
              </button>
              <button
                type="button"
                aria-label="아래로"
                disabled={index === stops.length - 1}
                onClick={() => moveStop(index, index + 1)}
                className="size-7 rounded border border-hairline text-xs disabled:opacity-30"
              >
                &#9660;
              </button>
              <button
                type="button"
                aria-label="단계 삭제"
                onClick={() => removeStop(stop.id)}
                className="size-7 rounded border border-hairline text-xs"
              >
                &#10005;
              </button>
            </div>

            <ul className="mt-2 space-y-1 pl-8">
              {stop.candidates.map((place) => (
                <li key={place.id} className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => onFocus(place.location)}
                    className="min-w-0 flex-1 truncate text-left text-sm"
                  >
                    {place.name}
                  </button>
                  <button
                    type="button"
                    aria-label={`${place.name} 후보에서 빼기`}
                    onClick={() => removeCandidate(place.id)}
                    className="size-6 shrink-0 rounded border border-hairline text-[11px] text-ink/50"
                  >
                    &#10005;
                  </button>
                </li>
              ))}
            </ul>

            <button
              type="button"
              onClick={() => onAddCandidates(stop.id)}
              className="mt-2 ml-8 h-8 rounded-lg border border-hairline px-3 text-xs"
            >
              + 이 단계에 후보 추가
            </button>
          </li>
        ))}
      </ol>
    </div>
  );
}
