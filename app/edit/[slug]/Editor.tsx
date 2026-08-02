'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { KakaoMap } from '@/components/map/KakaoMap';
import { MapOverlay } from '@/components/map/MapOverlay';
import { PlacePanel } from '@/components/panels/PlacePanel';
import { EditorToolbar } from '@/components/toolbar/EditorToolbar';
import { loadDraft, saveDraft } from '@/lib/map/draftStorage';
import { DEFAULT_CENTER, DEFAULT_LEVEL, type LatLng } from '@/lib/map/types';
import { useMapStore } from '@/store/useMapStore';

/* §6.1 저장 전략. 획 하나마다 저장하면 요청이 폭증한다. */
const DEBOUNCE_MS = 2_000;
const MAX_WAIT_MS = 10_000;

export function Editor({ slug }: { slug: string }) {
  const [map, setMap] = useState<kakao.maps.Map | null>(null);
  const [initial, setInitial] = useState<{ center: LatLng; level: number } | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);

  const hydrate = useMapStore((s) => s.hydrate);

  // 초안을 먼저 읽어야 지도 초기 중심을 저장된 값으로 띄울 수 있다.
  useEffect(() => {
    const draft = loadDraft(slug);
    hydrate(draft ?? {});
    setInitial({
      center: draft?.center ?? DEFAULT_CENTER,
      level: draft?.zoomLevel ?? DEFAULT_LEVEL,
    });
  }, [slug, hydrate]);

  useAutosave(slug, map);

  return (
    <div className="flex h-dvh flex-col overflow-hidden">
      <EditorTopBar />
      <div className="relative flex-1">
        {initial && (
          <>
            <KakaoMap center={initial.center} level={initial.level} onReady={setMap} />
            <MapOverlay map={map} />
          </>
        )}
        {searchOpen && <PlacePanel onClose={() => setSearchOpen(false)} />}
      </div>
      <EditorToolbar onOpenSearch={() => setSearchOpen(true)} />
    </div>
  );
}

function EditorTopBar() {
  const title = useMapStore((s) => s.title);
  const setTitle = useMapStore((s) => s.setTitle);
  const saveState = useMapStore((s) => s.saveState);

  return (
    <header className="z-30 flex h-12 shrink-0 items-center gap-2 border-b border-hairline bg-white px-3">
      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="제목 없는 지도"
        className="min-w-0 flex-1 bg-transparent text-sm font-medium outline-none placeholder:text-ink/35"
      />
      <span className="shrink-0 text-xs tabular-nums text-ink/45">
        {saveState === 'saving' ? '저장 중…' : saveState === 'dirty' ? '변경됨' : '저장됨'}
      </span>
      <button
        type="button"
        disabled
        title="공유 링크는 서버 저장(T12)과 뷰어(T13)가 붙은 뒤 활성화됩니다"
        className="h-8 shrink-0 rounded-lg border border-hairline px-3 text-sm disabled:opacity-40"
      >
        공유
      </button>
    </header>
  );
}

/**
 * debounce 2초 + 최대 10초 강제 flush, 이탈 시 마지막 flush.
 * 지금은 localStorage에 쓰지만 호출 구조는 서버 스냅샷 PATCH와 동일하다.
 */
function useAutosave(slug: string, map: kakao.maps.Map | null) {
  const places = useMapStore((s) => s.places);
  const strokes = useMapStore((s) => s.strokes);
  const labels = useMapStore((s) => s.labels);
  const title = useMapStore((s) => s.title);
  const firstDirtyRef = useRef<number | null>(null);

  const flush = useCallback(() => {
    const state = useMapStore.getState();
    if (state.saveState === 'idle') return;

    const center = map?.getCenter();
    state.setSaveState('saving');
    saveDraft(slug, {
      title: state.title,
      center: center ? { lat: center.getLat(), lng: center.getLng() } : DEFAULT_CENTER,
      zoomLevel: map?.getLevel() ?? DEFAULT_LEVEL,
      places: state.places,
      strokes: state.strokes,
      labels: state.labels,
    });
    firstDirtyRef.current = null;
    state.setSaveState('saved');
  }, [slug, map]);

  useEffect(() => {
    if (useMapStore.getState().saveState !== 'dirty') return;

    firstDirtyRef.current ??= Date.now();
    const waited = Date.now() - firstDirtyRef.current;
    const delay = Math.max(0, Math.min(DEBOUNCE_MS, MAX_WAIT_MS - waited));

    const timer = setTimeout(flush, delay);
    return () => clearTimeout(timer);
  }, [places, strokes, labels, title, flush]);

  useEffect(() => {
    // 탭을 닫거나 백그라운드로 보낼 때의 마지막 기회.
    // 서버 저장이 붙으면 여기가 navigator.sendBeacon 자리가 된다.
    const onUnload = () => flush();
    const onHide = () => {
      if (document.visibilityState === 'hidden') flush();
    };
    window.addEventListener('beforeunload', onUnload);
    document.addEventListener('visibilitychange', onHide);
    return () => {
      window.removeEventListener('beforeunload', onUnload);
      document.removeEventListener('visibilitychange', onHide);
    };
  }, [flush]);
}
