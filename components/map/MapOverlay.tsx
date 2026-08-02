'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { createId } from '@/lib/id';
import { distanceToPolyline, simplify, type Point } from '@/lib/geo/rdp';
import { drawScene, hitsLabel, hitsPin } from '@/lib/render/scene';
import type { LatLng, Stroke } from '@/lib/map/types';
import { createLabel, createPlace, useMapStore } from '@/store/useMapStore';

/* W0에서 실제로 만져 보고 확정한 값들. 근거는 README의 검증 체크리스트 참고. */
const RDP_EPSILON_PX = 2;
const MIN_SAMPLE_PX = 1.5;
const ERASE_HIT_PX = 14;

interface LiveStroke {
  points: Point[];
  color: string;
  width: number;
}

interface Draft {
  kind: 'label' | 'place';
  point: Point;
  coord: LatLng;
}

export function MapOverlay({ map }: { map: kakao.maps.Map | null }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const liveRef = useRef<LiveStroke | null>(null);
  const anchorRef = useRef<{ coord: LatLng; point: Point } | null>(null);
  const dprRef = useRef(1);
  const followQueuedRef = useRef(false);

  const [draft, setDraft] = useState<Draft | null>(null);

  const places = useMapStore((s) => s.places);
  const strokes = useMapStore((s) => s.strokes);
  const labels = useMapStore((s) => s.labels);
  const mode = useMapStore((s) => s.mode);

  const toScreen = useCallback(
    (coord: LatLng): Point => {
      const p = map!
        .getProjection()
        .containerPointFromCoords(new kakao.maps.LatLng(coord.lat, coord.lng));
      return { x: p.x, y: p.y };
    },
    [map],
  );

  const toCoord = useCallback(
    (point: Point): LatLng => {
      const ll = map!
        .getProjection()
        .coordsFromContainerPoint(new kakao.maps.Point(point.x, point.y));
      return { lat: ll.getLat(), lng: ll.getLng() };
    },
    [map],
  );

  const redraw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !map) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = dprRef.current;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, canvas.clientWidth, canvas.clientHeight);

    drawScene(ctx, { places, strokes, labels }, toScreen, map.getLevel());

    const live = liveRef.current;
    if (live && live.points.length > 1) {
      ctx.strokeStyle = live.color;
      ctx.lineWidth = live.width;
      ctx.beginPath();
      ctx.moveTo(live.points[0]!.x, live.points[0]!.y);
      for (let i = 1; i < live.points.length; i++) ctx.lineTo(live.points[i]!.x, live.points[i]!.y);
      ctx.stroke();
    }
  }, [map, places, strokes, labels, toScreen]);

  const redrawRef = useRef(redraw);
  redrawRef.current = redraw;

  /* 백버퍼를 dpr배로 잡고 컨텍스트를 scale하지 않으면 레티나에서 선이 흐릿하다. */
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const resize = () => {
      const parent = canvas.parentElement;
      if (!parent) return;
      const dpr = window.devicePixelRatio || 1;
      dprRef.current = dpr;
      canvas.width = Math.round(parent.clientWidth * dpr);
      canvas.height = Math.round(parent.clientHeight * dpr);
      canvas.style.width = `${parent.clientWidth}px`;
      canvas.style.height = `${parent.clientHeight}px`;
      redrawRef.current();
    };

    resize();
    const observer = new ResizeObserver(resize);
    if (canvas.parentElement) observer.observe(canvas.parentElement);
    window.addEventListener('resize', resize);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', resize);
    };
  }, []);

  /* 팬 중에 모든 좌표를 재투영하면 프레임이 무너진다. 기준 좌표 하나의 이동량만 계산해
     캔버스를 통째로 밀고, idle에서 transform을 지우고 정확히 다시 그린다.
     줌 중에는 축척이 바뀌어 transform 근사가 성립하지 않으므로 아예 숨긴다. */
  useEffect(() => {
    if (!map) return;
    const canvas = canvasRef.current;
    if (!canvas) return;

    const captureAnchor = () => {
      const center = map.getCenter();
      const coord = { lat: center.getLat(), lng: center.getLng() };
      anchorRef.current = { coord, point: toScreen(coord) };
    };

    const onCenterChanged = () => {
      if (followQueuedRef.current) return;
      followQueuedRef.current = true;
      requestAnimationFrame(() => {
        followQueuedRef.current = false;
        const anchor = anchorRef.current;
        if (!anchor) return;
        const now = toScreen(anchor.coord);
        canvas.style.transform = `translate3d(${now.x - anchor.point.x}px, ${now.y - anchor.point.y}px, 0)`;
      });
    };

    const onZoomStart = () => {
      canvas.style.opacity = '0';
    };

    const onIdle = () => {
      canvas.style.transform = '';
      canvas.style.opacity = '1';
      captureAnchor();
      redrawRef.current();
    };

    captureAnchor();
    redrawRef.current();

    kakao.maps.event.addListener(map, 'center_changed', onCenterChanged);
    kakao.maps.event.addListener(map, 'zoom_start', onZoomStart);
    kakao.maps.event.addListener(map, 'idle', onIdle);
    return () => {
      kakao.maps.event.removeListener(map, 'center_changed', onCenterChanged);
      kakao.maps.event.removeListener(map, 'zoom_start', onZoomStart);
      kakao.maps.event.removeListener(map, 'idle', onIdle);
    };
  }, [map, toScreen]);

  /* 그리기 중에는 지도 제스처를 완전히 잠근다. 이걸 안 하면 손가락 한 번에
     그림 절반, 지도 팬 절반이 되어 사용할 수 없는 UX가 된다. */
  useEffect(() => {
    if (!map) return;
    const drawing = mode !== 'pan';
    map.setDraggable(!drawing);
    map.setZoomable(!drawing);
    setDraft(null);
  }, [map, mode]);

  useEffect(() => {
    redraw();
  }, [redraw]);

  const eventPoint = (event: React.PointerEvent<HTMLCanvasElement>): Point => {
    const rect = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  const handlePointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!map) return;
    const point = eventPoint(event);

    if (mode === 'erase') return eraseAt(point);
    if (mode === 'label') return setDraft({ kind: 'label', point, coord: toCoord(point) });
    if (mode === 'place') return setDraft({ kind: 'place', point, coord: toCoord(point) });
    if (mode !== 'draw') return;

    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const { color, width } = useMapStore.getState();
    liveRef.current = { points: [point], color, width };
  };

  const handlePointerMove = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const live = liveRef.current;
    if (!live) return;
    event.preventDefault();

    const point = eventPoint(event);
    const last = live.points.at(-1)!;
    if (Math.hypot(point.x - last.x, point.y - last.y) < MIN_SAMPLE_PX) return;
    live.points.push(point);

    // 라이브 구간만 덧그린다. 전체 재그리기는 커밋 시점에 한 번.
    const ctx = event.currentTarget.getContext('2d');
    if (!ctx) return;
    ctx.strokeStyle = live.color;
    ctx.lineWidth = live.width;
    ctx.beginPath();
    ctx.moveTo(last.x, last.y);
    ctx.lineTo(point.x, point.y);
    ctx.stroke();
  };

  const commitStroke = () => {
    const live = liveRef.current;
    liveRef.current = null;
    if (!live || !map) return;

    const simplified = simplify(live.points, RDP_EPSILON_PX);
    if (simplified.length < 2) {
      redraw();
      return;
    }
    const stroke: Stroke = {
      id: createId(),
      path: simplified.map(toCoord),
      color: live.color,
      width: live.width,
      zoomCreated: map.getLevel(),
    };
    useMapStore.getState().addStroke(stroke);
  };

  /** 지우개는 위에 그려진 것부터 지운다: 라벨 → 핀 → 획. */
  const eraseAt = (point: Point) => {
    const state = useMapStore.getState();

    for (let i = state.labels.length - 1; i >= 0; i--) {
      const label = state.labels[i]!;
      if (hitsLabel(point, label, toScreen(label.location))) return state.removeLabel(label.id);
    }
    for (let i = state.places.length - 1; i >= 0; i--) {
      const place = state.places[i]!;
      if (hitsPin(point, toScreen(place.location))) return state.removePlace(place.id);
    }
    for (let i = state.strokes.length - 1; i >= 0; i--) {
      const stroke = state.strokes[i]!;
      if (distanceToPolyline(point, stroke.path.map(toScreen)) < ERASE_HIT_PX) {
        return state.removeStroke(stroke.id);
      }
    }
  };

  const interactive = mode !== 'pan';

  return (
    <>
      <canvas
        ref={canvasRef}
        className="absolute inset-0 z-10 touch-none transition-opacity duration-100"
        style={{
          pointerEvents: interactive ? 'auto' : 'none',
          cursor: interactive ? 'crosshair' : 'default',
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={commitStroke}
        onPointerCancel={commitStroke}
      />

      {draft && (
        <DraftInput
          point={draft.point}
          placeholder={draft.kind === 'place' ? '장소 이름 후 Enter' : '메모 입력 후 Enter'}
          onCancel={() => setDraft(null)}
          onCommit={(text) => {
            const store = useMapStore.getState();
            if (draft.kind === 'place') store.addPlace(createPlace(draft.coord, text));
            else store.addLabel(createLabel(draft.coord, text));
            setDraft(null);
          }}
        />
      )}
    </>
  );
}

function DraftInput({
  point,
  placeholder,
  onCommit,
  onCancel,
}: {
  point: Point;
  placeholder: string;
  onCommit: (text: string) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState('');

  return (
    <input
      autoFocus
      value={text}
      onChange={(e) => setText(e.target.value)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' && text.trim()) onCommit(text.trim());
        if (e.key === 'Escape') onCancel();
      }}
      onBlur={() => (text.trim() ? onCommit(text.trim()) : onCancel())}
      placeholder={placeholder}
      className="absolute z-20 h-9 w-48 -translate-x-1/2 -translate-y-1/2 rounded-lg border border-ink bg-white px-2 text-sm shadow-lg outline-none"
      style={{ left: point.x, top: point.y }}
    />
  );
}
