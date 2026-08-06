'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import { KakaoMap } from '@/components/map/KakaoMap';
import { useMapCanvas } from '@/components/map/useMapCanvas';
import { PlaceStrip } from '@/components/panels/PlaceStrip';
import { SharedCourseSheet } from '@/components/panels/SharedCourseSheet';
import { focusPlaces } from '@/lib/map/focusPlaces';
import { readEditToken } from '@/lib/map/persistence';
import { sceneViewport } from '@/lib/map/sceneViewport';
import type { StoredMapDocument } from '@/lib/map/getMapDocument';

export function Viewer({ document }: { document: StoredMapDocument }) {
  const [map, setMap] = useState<kakao.maps.Map | null>(null);
  const [canEdit, setCanEdit] = useState(false);
  const [courseOpen, setCourseOpen] = useState(false);
  const viewport = useMemo(
    () => sceneViewport(document, { width: 800, height: 420 }),
    [document],
  );

  // 편집 토큰은 이 브라우저에만 있다. 서버 렌더 결과와 어긋나지 않도록 마운트 후에 본다.
  useEffect(() => {
    setCanEdit(Boolean(readEditToken(document.slug)));
  }, [document.slug]);

  useEffect(() => {
    // 프리페치·크롤러와 구분하기 위해 실제로 열렸을 때만 센다.
    void fetch(`/api/maps/${document.slug}/view`, { method: 'POST' }).catch(() => {});
  }, [document.slug]);

  return (
    <div className="flex h-dvh flex-col overflow-hidden">
      <header className="z-30 flex h-12 shrink-0 items-center gap-2 border-b border-hairline bg-white px-3">
        <h1 className="min-w-0 flex-1 truncate text-sm font-medium">
          {document.title || '제목 없는 지도'}
        </h1>
        {document.stops.length > 0 && (
          <button
            type="button"
            onClick={() => setCourseOpen(true)}
            className="h-8 shrink-0 rounded-lg border border-hairline px-3 text-sm"
          >
            모임 동선
          </button>
        )}
        {canEdit && (
          <Link
            href={`/edit/${document.slug}`}
            className="h-8 shrink-0 rounded-lg border border-hairline px-3 text-sm leading-8"
          >
            편집하기
          </Link>
        )}
      </header>

      <div className="relative flex-1">
        <KakaoMap
          center={viewport.center}
          level={viewport.level}
          onReady={(readyMap) => {
            setMap(readyMap);
            // 실제 컨테이너 비율로 한 번 더 맞춘다. 초기 중심도 이미 장면 기준이라
            // 이 호출 전 잠깐 강남의 빈 지도가 보이는 일은 없다.
            focusPlaces(readyMap, viewport.coordinates, 56);
          }}
        />
        <ViewerCanvas map={map} document={document} />
      </div>

      <PlaceStrip stops={document.stops} onFocus={(location) => focusPlaces(map, [location])} />

      {courseOpen && (
        <SharedCourseSheet
          stops={document.stops}
          legs={document.legs ?? []}
          onFocus={(location) => focusPlaces(map, [location])}
          onClose={() => setCourseOpen(false)}
        />
      )}

      {/* 설계안 §7.4 — 뷰어에서 생성으로 유도하는 전환 지점 */}
      <Link
        href="/"
        className="z-30 flex h-12 shrink-0 items-center justify-center border-t border-hairline bg-ink text-sm font-medium text-white"
      >
        나도 지도 만들기
      </Link>
    </div>
  );
}

/** 입력 없이 장면만 그린다. 편집기와 같은 drawScene을 쓰므로 그림이 항상 같다. */
function ViewerCanvas({
  map,
  document,
}: {
  map: kakao.maps.Map | null;
  document: StoredMapDocument;
}) {
  const { canvasRef } = useMapCanvas({
    map,
    scene: {
      stops: document.stops,
      // 저장된 경로를 그대로 그린다. 보는 쪽에서 길찾기를 부르지 않는다.
      legs: document.legs ?? [],
      strokes: document.strokes,
      labels: document.labels,
      showCandidateLinks: document.showCandidateLinks,
      showStopArrows: document.showStopArrows,
    },
  });

  return (
    <canvas
      ref={canvasRef}
      className="pointer-events-none absolute inset-0 z-10 transition-opacity duration-100"
    />
  );
}
