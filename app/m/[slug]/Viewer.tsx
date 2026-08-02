'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { KakaoMap } from '@/components/map/KakaoMap';
import { useMapCanvas } from '@/components/map/useMapCanvas';
import { PlaceStrip } from '@/components/panels/PlaceStrip';
import { focusPlaces } from '@/lib/map/focusPlaces';
import { readEditToken } from '@/lib/map/persistence';
import type { StoredMapDocument } from '@/lib/map/getMapDocument';

export function Viewer({ document }: { document: StoredMapDocument }) {
  const [map, setMap] = useState<kakao.maps.Map | null>(null);
  const [canEdit, setCanEdit] = useState(false);

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
          center={document.center}
          level={document.zoomLevel}
          onReady={setMap}
        />
        <ViewerCanvas map={map} document={document} />
      </div>

      <PlaceStrip stops={document.stops} onFocus={(location) => focusPlaces(map, [location])} />

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
      strokes: document.strokes,
      labels: document.labels,
    },
  });

  return (
    <canvas
      ref={canvasRef}
      className="pointer-events-none absolute inset-0 z-10 transition-opacity duration-100"
    />
  );
}

