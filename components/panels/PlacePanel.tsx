'use client';

import { useState } from 'react';
import { TRAVEL_MODES, type PlaceCandidate, type TravelMode } from '@/lib/map/types';
import { placeFromCandidate, useMapStore } from '@/store/useMapStore';

type Status = { kind: 'idle' } | { kind: 'loading' } | { kind: 'error'; message: string };

export function PlacePanel({ onClose }: { onClose: () => void }) {
  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<PlaceCandidate[]>([]);
  const [status, setStatus] = useState<Status>({ kind: 'idle' });

  const places = useMapStore((s) => s.places);
  const addPlace = useMapStore((s) => s.addPlace);

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

  const search = () => {
    if (!query.trim()) return;
    void run(() => fetch(`/api/search?q=${encodeURIComponent(query.trim())}`));
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
        body: JSON.stringify({ text }),
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
          onKeyDown={(e) => e.key === 'Enter' && search()}
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
                  setCandidates([]);
                  setQuery('');
                }}
                className="w-full px-4 py-3 text-left"
              >
                <span className="text-sm font-medium">{candidate.name}</span>
                {candidate.category && (
                  <span className="ml-2 text-xs text-ink/40">{candidate.category}</span>
                )}
                <span className="mt-0.5 block text-xs text-ink/55">
                  {candidate.roadAddress ?? candidate.address ?? '주소 정보 없음'}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {places.length > 0 && <PlaceList />}

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
function PlaceList() {
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
              <span className="min-w-0 flex-1 truncate text-sm">{place.name}</span>
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
