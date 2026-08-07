'use client';

import { useState } from 'react';
import { focusPlaces } from '@/lib/map/focusPlaces';
import { drawableRoute, legEndpoints } from '@/lib/map/legs';
import { isSamePlace } from '@/lib/map/savedPlaces';
import {
  formatDistance,
  formatDuration,
  type LatLng,
  type PlaceCandidate,
  type TravelMode,
} from '@/lib/map/types';
import { createPlace, placeFromCandidate, useMapStore } from '@/store/useMapStore';
import { useSavedPlacesStore } from '@/store/useSavedPlacesStore';

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
  const savedPlaces = useSavedPlacesStore((s) => s.places);

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
            <li key={`${candidate.kakaoPlaceId}-${candidate.name}`} className="flex items-start">
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
              <SaveToggle candidate={candidate} />
            </li>
          ))}
        </ul>
      )}

      {savedPlaces.length > 0 && <SavedList onFocus={(location) => focusPlaces(map, [location])} />}

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
  const setPrimary = useMapStore((s) => s.setPrimary);

  return (
    <div className="border-t border-hairline">
      <h2 className="px-4 pt-3 text-xs font-semibold tracking-wide text-ink/40">
        담은 단계 {stops.length}개
      </h2>
      <AutoLineToggles />
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
                  {/*
                    후보가 하나뿐이면 고를 것이 없다. 버튼을 두면 의미 없는 선택처럼 보인다.
                    이름 뒤에 조사를 붙이면 받침에 따라 을/를이 틀리므로 조사를 쓰지 않는다.
                  */}
                  {stop.candidates.length > 1 && (
                    <button
                      type="button"
                      aria-label={`${place.name} 대표로 지정`}
                      aria-pressed={stop.primaryId === place.id}
                      title="실제 경로를 그릴 기준"
                      onClick={() => setPrimary(stop.id, place.id)}
                      className={`size-6 shrink-0 rounded-full border text-[11px] ${
                        stop.primaryId === place.id
                          ? 'border-coral bg-coral text-white'
                          : 'border-hairline text-ink/35'
                      }`}
                    >
                      &#9679;
                    </button>
                  )}
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

            {/* 이 단계에서 다음 단계로 어떻게 가는가. 마지막 단계 뒤에는 갈 곳이 없다. */}
            {index < stops.length - 1 && <LegEditor index={index} />}
          </li>
        ))}
      </ol>
    </div>
  );
}

const MODE_LABELS: { mode: TravelMode; label: string }[] = [
  { mode: 'straight', label: '직선' },
  { mode: 'walk', label: '도보' },
  { mode: 'transit', label: '대중교통' },
  { mode: 'bicycle', label: '자전거' },
  { mode: 'car', label: '자동차' },
];

/**
 * 다음 단계로 가는 방법.
 *
 * 직선이 기본이다. 실제 경로는 출발·도착이 확정돼야 뽑을 수 있는데, 후보가 여럿인
 * 단계는 아직 안 정했다는 뜻이라 기준이 없다. 그럴 때는 무엇이 모자란지 그 자리에서
 * 알려 준다. 조용히 직선으로 되돌아가면 왜 안 그려지는지 알 수 없다.
 */
function LegEditor({ index }: { index: number }) {
  const stops = useMapStore((s) => s.stops);
  const leg = useMapStore((s) => s.legs[index]);
  const setLegMode = useMapStore((s) => s.setLegMode);

  const mode = leg?.mode ?? 'straight';
  const ready = legEndpoints(stops, index) !== null;
  const route = drawableRoute(stops, index, leg);

  return (
    <div className="mt-3 ml-8 border-l-2 border-dashed border-hairline pl-3">
      <div className="flex flex-wrap items-center gap-1">
        <span className="mr-1 text-[11px] text-ink/40">{index + 2}번까지</span>
        {MODE_LABELS.map(({ mode: value, label }) => (
          <button
            key={value}
            type="button"
            aria-pressed={mode === value}
            onClick={() => setLegMode(index, value)}
            className={`h-7 rounded-lg border px-2 text-[11px] ${
              mode === value ? 'border-ink bg-ink text-white' : 'border-hairline text-ink/70'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {mode !== 'straight' && !ready && (
        <p className="mt-1.5 text-[11px] text-coral">
          양쪽 단계에서 대표 후보(&#9679;)를 정해야 실제 경로를 그립니다
        </p>
      )}

      {mode !== 'straight' && ready && !route && (
        <p className="mt-1.5 text-[11px] text-ink/40">경로를 가져오는 중…</p>
      )}

      {route && (
        <div className="mt-1.5 text-[11px] text-ink/55">
          <span className="tabular-nums">
            {formatDistance(route.distanceM)} · {formatDuration(route.durationS)}
          </span>
          {route.legs?.map((transit, i) => (
            <span key={i} className="ml-1.5 rounded bg-ink/5 px-1.5 py-0.5">
              {transit.guidance}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

/**
 * 검색 결과를 보관함에 넣고 빼는 별.
 *
 * 코스에 담는 것(체크)과 보관함에 저장하는 것(별)은 다른 동작이다.
 * 체크는 이 지도의 단계가 되고, 별은 다음에 다른 지도를 만들 때도 남는다.
 */
function SaveToggle({ candidate }: { candidate: PlaceCandidate }) {
  const places = useSavedPlacesStore((s) => s.places);
  const toggle = useSavedPlacesStore((s) => s.toggle);

  const input = toSavedInput(candidate);
  const saved = places.some((place) => isSamePlace(input, place));

  return (
    <button
      type="button"
      onClick={() => toggle(input)}
      aria-pressed={saved}
      aria-label={saved ? `${candidate.name} 보관함에서 빼기` : `${candidate.name} 보관함에 저장`}
      title={saved ? '보관함에서 빼기' : '보관함에 저장'}
      className={`mr-3 mt-3 size-8 shrink-0 rounded-lg border text-sm ${
        saved ? 'border-ink bg-ink text-white' : 'border-hairline text-ink/35'
      }`}
    >
      {saved ? '★' : '☆'}
    </button>
  );
}

function toSavedInput(candidate: PlaceCandidate) {
  return {
    name: candidate.name,
    ...(candidate.roadAddress ?? candidate.address
      ? { address: candidate.roadAddress ?? candidate.address }
      : {}),
    ...(candidate.kakaoPlaceId ? { kakaoPlaceId: candidate.kakaoPlaceId } : {}),
    location: candidate.location,
  };
}

/**
 * 보관함. 지도가 바뀌어도 남는 개인 목록이라 공유되는 문서에는 들어가지 않는다.
 */
function SavedList({ onFocus }: { onFocus: (location: LatLng) => void }) {
  const places = useSavedPlacesStore((s) => s.places);
  const remove = useSavedPlacesStore((s) => s.remove);
  const visible = useSavedPlacesStore((s) => s.visible);
  const setVisible = useSavedPlacesStore((s) => s.setVisible);
  const addStop = useMapStore((s) => s.addStop);

  return (
    <div className="border-t border-hairline">
      <div className="flex items-center gap-2 px-4 pt-3">
        <h2 className="flex-1 text-xs font-semibold tracking-wide text-ink/40">
          보관함 {places.length}곳
        </h2>
        <button
          type="button"
          onClick={() => setVisible(!visible)}
          aria-pressed={visible}
          className={`h-7 rounded-full border px-2.5 text-xs ${
            visible ? 'border-ink bg-ink text-white' : 'border-hairline text-ink/60'
          }`}
        >
          지도에 표시
        </button>
      </div>
      <p className="px-4 pt-1 text-[11px] leading-relaxed text-ink/35">
        이 브라우저에만 저장됩니다. 공유 링크에는 담지 않은 장소가 보이지 않습니다.
      </p>
      <ul className="mt-2 divide-y divide-hairline">
        {places.map((place) => (
          <li key={place.id} className="flex items-center gap-2 px-4 py-2.5">
            <button
              type="button"
              onClick={() => onFocus(place.location)}
              className="min-w-0 flex-1 truncate text-left text-sm"
            >
              {place.name}
              {place.address && (
                <span className="mt-0.5 block truncate text-xs text-ink/45">{place.address}</span>
              )}
            </button>
            <button
              type="button"
              onClick={() =>
                addStop([
                  createPlace(place.location, place.name, {
                    ...(place.address ? { address: place.address } : {}),
                    ...(place.kakaoPlaceId ? { kakaoPlaceId: place.kakaoPlaceId } : {}),
                  }),
                ])
              }
              className="h-8 shrink-0 rounded-lg border border-hairline px-2.5 text-xs"
            >
              단계로 담기
            </button>
            <button
              type="button"
              aria-label={`${place.name} 보관함에서 빼기`}
              onClick={() => remove(place.id)}
              className="size-8 shrink-0 rounded-lg border border-hairline text-xs text-ink/50"
            >
              &#10005;
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

/**
 * 자동으로 그려지는 선을 끄고 켠다.
 *
 * 동선을 손으로 직접 그리는 사람에게는 자동 선이 방해가 된다. 설정은 문서에 담기므로
 * 끈 상태 그대로 공유된다.
 */
function AutoLineToggles() {
  const showLinks = useMapStore((s) => s.showCandidateLinks);
  const showArrows = useMapStore((s) => s.showStopArrows);
  const setShowLinks = useMapStore((s) => s.setShowCandidateLinks);
  const setShowArrows = useMapStore((s) => s.setShowStopArrows);

  return (
    <div className="flex flex-wrap items-center gap-1.5 px-4 pt-2">
      <span className="mr-1 text-[11px] text-ink/35">자동 선</span>
      <ToggleChip pressed={showLinks} onClick={() => setShowLinks(!showLinks)}>
        후보 연결선
      </ToggleChip>
      <ToggleChip pressed={showArrows} onClick={() => setShowArrows(!showArrows)}>
        이동 동선
      </ToggleChip>
    </div>
  );
}

function ToggleChip({
  pressed,
  onClick,
  children,
}: {
  pressed: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={pressed}
      className={`h-7 rounded-full border px-2.5 text-xs ${
        pressed ? 'border-ink bg-ink text-white' : 'border-hairline text-ink/45 line-through'
      }`}
    >
      {children}
    </button>
  );
}
