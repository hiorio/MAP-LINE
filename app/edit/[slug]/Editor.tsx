'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { KakaoMap } from '@/components/map/KakaoMap';
import { MapOverlay } from '@/components/map/MapOverlay';
import { PlacePanel } from '@/components/panels/PlacePanel';
import { PlaceStrip } from '@/components/panels/PlaceStrip';
import { focusPlaces } from '@/lib/map/focusPlaces';
import { EditorToolbar } from '@/components/toolbar/EditorToolbar';
import { SearchBar } from '@/components/toolbar/SearchBar';
import { loadDocument, saveDocument, type SaveMode } from '@/lib/map/persistence';
import { DEFAULT_CENTER, DEFAULT_LEVEL, type LatLng } from '@/lib/map/types';
import { useMapStore } from '@/store/useMapStore';
import { useSavedPlacesStore } from '@/store/useSavedPlacesStore';

/* §6.1 저장 전략. 획 하나마다 저장하면 요청이 폭증한다. */
const DEBOUNCE_MS = 2_000;
const MAX_WAIT_MS = 10_000;

export function Editor({ slug }: { slug: string }) {
  const [map, setMap] = useState<kakao.maps.Map | null>(null);
  const [initial, setInitial] = useState<{ center: LatLng; level: number } | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);
  /** 검색 결과를 새 단계가 아니라 이 단계의 후보로 담을 때 쓴다. */
  const [targetStopId, setTargetStopId] = useState<string | null>(null);

  const [saveMode, setSaveMode] = useState<SaveMode>('local');
  const updatedAtRef = useRef<string | undefined>(undefined);
  const hydrate = useMapStore((s) => s.hydrate);
  const hydrateSaved = useSavedPlacesStore((s) => s.hydrate);

  // 보관함은 localStorage에 있으므로 서버 렌더 결과와 어긋나지 않도록 마운트 후에 읽는다.
  useEffect(() => hydrateSaved(), [hydrateSaved]);

  // 저장된 내용을 먼저 읽어야 지도 초기 중심을 그 값으로 띄울 수 있다.
  useEffect(() => {
    let cancelled = false;
    void loadDocument(slug).then(({ document, mode, updatedAt }) => {
      if (cancelled) return;
      hydrate(document ?? {});
      updatedAtRef.current = updatedAt;
      setSaveMode(mode);
      setInitial({
        center: document?.center ?? DEFAULT_CENTER,
        level: document?.zoomLevel ?? DEFAULT_LEVEL,
      });
    });
    return () => {
      cancelled = true;
    };
  }, [slug, hydrate]);

  useAutosave(slug, map, updatedAtRef, setSaveMode);

  return (
    <div className="flex h-dvh flex-col overflow-hidden">
      <EditorTopBar slug={slug} saveMode={saveMode} />
      <div className="relative flex-1">
        {initial && (
          <>
            <KakaoMap center={initial.center} level={initial.level} onReady={setMap} />
            <MapOverlay map={map} />
          </>
        )}
        {!searchOpen && <SearchBar onOpen={() => setSearchOpen(true)} />}
        {searchOpen && (
          <PlacePanel
            map={map}
            targetStopId={targetStopId}
            onTargetStopChange={(stopId) => {
              setTargetStopId(stopId);
              // 단계 목록에서 "후보 추가"를 누른 경우다. 검색창으로 시선을 되돌린다.
              if (stopId) setSearchOpen(true);
            }}
            onClose={() => {
              setSearchOpen(false);
              setTargetStopId(null);
            }}
          />
        )}
      </div>
      {!searchOpen && <EditorPlaceStrip map={map} onOpenList={() => setSearchOpen(true)} />}
      <EditorToolbar />
    </div>
  );
}

/**
 * 담은 장소를 항상 보이게 둔다. 검색 패널 안에만 있으면 닫는 순간 무엇을 담았는지
 * 알 수 없고, 확인하려면 매번 패널을 다시 열어야 한다.
 */
function EditorPlaceStrip({
  map,
  onOpenList,
}: {
  map: kakao.maps.Map | null;
  onOpenList: () => void;
}) {
  const stops = useMapStore((s) => s.stops);

  return (
    <PlaceStrip
      stops={stops}
      onFocus={(location) => focusPlaces(map, [location])}
      trailing={
        <button
          type="button"
          onClick={onOpenList}
          className="h-9 shrink-0 rounded-lg border border-hairline px-3 text-sm"
        >
          단계 편집
        </button>
      }
    />
  );
}

function EditorTopBar({ slug, saveMode }: { slug: string; saveMode: SaveMode }) {
  const title = useMapStore((s) => s.title);
  const setTitle = useMapStore((s) => s.setTitle);
  const saveState = useMapStore((s) => s.saveState);

  const label =
    saveState === 'saving'
      ? '저장 중…'
      : saveState === 'dirty'
        ? '변경됨'
        : saveMode === 'server'
          ? '저장됨'
          : '이 기기에만 저장됨';

  return (
    <header className="z-30 flex h-12 shrink-0 items-center gap-2 border-b border-hairline bg-white px-3">
      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="제목 없는 지도"
        className="min-w-0 flex-1 bg-transparent text-sm font-medium outline-none placeholder:text-ink/35"
      />
      <span className="shrink-0 text-xs tabular-nums text-ink/45">{label}</span>
      <ShareButton slug={slug} saveMode={saveMode} />
    </header>
  );
}

/**
 * 서버에 저장된 지도만 공유할 수 있다. 로컬 전용 지도는 링크를 줘도 상대가 열 수 없다.
 */
function ShareButton({ slug, saveMode }: { slug: string; saveMode: SaveMode }) {
  const [copied, setCopied] = useState(false);

  const share = async () => {
    const url = `${window.location.origin}/m/${slug}`;
    const title = useMapStore.getState().title || '제목 없는 지도';

    // 모바일에서는 OS 공유 시트가 카톡으로 바로 보내는 가장 짧은 경로다.
    if (navigator.share) {
      try {
        await navigator.share({ title, url });
        return;
      } catch {
        // 사용자가 취소했거나 지원하지 않으면 복사로 넘어간다.
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      window.prompt('아래 주소를 복사하세요', url);
    }
  };

  return (
    <button
      type="button"
      onClick={share}
      disabled={saveMode !== 'server'}
      title={
        saveMode === 'server'
          ? '읽기 전용 링크를 공유합니다'
          : '이 지도는 이 기기에만 저장돼 있어 공유할 수 없습니다'
      }
      className="h-8 shrink-0 rounded-lg border border-hairline px-3 text-sm disabled:opacity-40"
    >
      {copied ? '복사됨' : '공유'}
    </button>
  );
}

/**
 * debounce 2초 + 최대 10초 강제 flush, 이탈 시 마지막 flush.
 * 설계안 §6.1대로 변경분이 아니라 지도 전체 스냅샷을 보낸다.
 */
function useAutosave(
  slug: string,
  map: kakao.maps.Map | null,
  updatedAtRef: React.RefObject<string | undefined>,
  setSaveMode: (mode: SaveMode) => void,
) {
  const stops = useMapStore((s) => s.stops);
  const strokes = useMapStore((s) => s.strokes);
  const labels = useMapStore((s) => s.labels);
  const title = useMapStore((s) => s.title);
  const showCandidateLinks = useMapStore((s) => s.showCandidateLinks);
  const showStopArrows = useMapStore((s) => s.showStopArrows);
  const firstDirtyRef = useRef<number | null>(null);
  const inFlightRef = useRef(false);

  const flush = useCallback(() => {
    const state = useMapStore.getState();
    if (state.saveState === 'idle' || inFlightRef.current) return;

    const center = map?.getCenter();
    inFlightRef.current = true;
    state.setSaveState('saving');

    void saveDocument(
      slug,
      {
        title: state.title,
        showCandidateLinks: state.showCandidateLinks,
        showStopArrows: state.showStopArrows,
        center: center ? { lat: center.getLat(), lng: center.getLng() } : DEFAULT_CENTER,
        zoomLevel: map?.getLevel() ?? DEFAULT_LEVEL,
        stops: state.stops,
        strokes: state.strokes,
        labels: state.labels,
      },
      updatedAtRef.current,
    ).then((result) => {
      inFlightRef.current = false;
      firstDirtyRef.current = null;
      updatedAtRef.current = result.updatedAt ?? updatedAtRef.current;
      setSaveMode(result.mode);
      // 충돌이면 서버에 반영되지 않았으므로 dirty로 남겨 사용자가 알아채게 한다.
      useMapStore.getState().setSaveState(result.conflict ? 'dirty' : 'saved');
    });
  }, [slug, map, updatedAtRef, setSaveMode]);

  useEffect(() => {
    if (useMapStore.getState().saveState !== 'dirty') return;

    firstDirtyRef.current ??= Date.now();
    const waited = Date.now() - firstDirtyRef.current;
    const delay = Math.max(0, Math.min(DEBOUNCE_MS, MAX_WAIT_MS - waited));

    const timer = setTimeout(flush, delay);
    return () => clearTimeout(timer);
  }, [stops, strokes, labels, title, showCandidateLinks, showStopArrows, flush]);

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
