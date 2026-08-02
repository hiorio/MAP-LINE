'use client';

import { useEffect, useRef, useState } from 'react';
import { createId } from '@/lib/id';
import { distanceToPolyline, simplify, type Point } from '@/lib/geo/rdp';
import { hitsLabel, hitsPin } from '@/lib/render/scene';
import { flattenStops, type LatLng, type Stroke } from '@/lib/map/types';
import { createLabel, createPlace, useMapStore } from '@/store/useMapStore';
import { useMapCanvas } from './useMapCanvas';

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
  const liveRef = useRef<LiveStroke | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);

  const stops = useMapStore((s) => s.stops);
  const strokes = useMapStore((s) => s.strokes);
  const labels = useMapStore((s) => s.labels);
  const mode = useMapStore((s) => s.mode);

  const { canvasRef, toScreen, toCoord, redraw } = useMapCanvas({
    map,
    scene: { stops, strokes, labels },
    // 그리는 중인 획은 스토어에 들어가기 전이므로 장면 뒤에 덧그린다.
    afterDraw: (ctx) => {
      const live = liveRef.current;
      if (!live || live.points.length < 2) return;
      ctx.strokeStyle = live.color;
      ctx.lineWidth = live.width;
      ctx.beginPath();
      ctx.moveTo(live.points[0]!.x, live.points[0]!.y);
      for (let i = 1; i < live.points.length; i++) ctx.lineTo(live.points[i]!.x, live.points[i]!.y);
      ctx.stroke();
    },
  });

  /* 그리기 중에는 지도 제스처를 완전히 잠근다. 이걸 안 하면 손가락 한 번에
     그림 절반, 지도 팬 절반이 되어 사용할 수 없는 UX가 된다. */
  useEffect(() => {
    if (!map) return;
    const drawing = mode !== 'pan';
    map.setDraggable(!drawing);
    map.setZoomable(!drawing);
    setDraft(null);
  }, [map, mode]);

  const eventPoint = (event: React.PointerEvent<HTMLCanvasElement>): Point => {
    const rect = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  const handlePointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!map) return;

    /* 뒤따르는 mousedown이 포커스를 캔버스로 옮기지 못하게 막는다.
       막지 않으면 바로 아래에서 띄우는 입력창이 뜨자마자 blur되어 스스로 취소한다.
       합성 pointerdown만으로는 재현되지 않고 실제 마우스로만 드러나는 경로다. */
    event.preventDefault();

    const point = eventPoint(event);

    if (mode === 'erase') return eraseAt(point);
    if (mode === 'label') return setDraft({ kind: 'label', point, coord: toCoord(point) });
    if (mode === 'place') return setDraft({ kind: 'place', point, coord: toCoord(point) });
    if (mode !== 'draw') return;

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
    // 후보 하나만 지운다. 그 단계의 마지막 후보였다면 단계도 함께 사라진다.
    const pins = flattenStops(state.stops);
    for (let i = pins.length - 1; i >= 0; i--) {
      const { place } = pins[i]!;
      if (hitsPin(point, toScreen(place.location))) return state.removeCandidate(place.id);
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
            if (draft.kind === 'place') store.addStop([createPlace(draft.coord, text)]);
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
  const inputRef = useRef<HTMLInputElement>(null);

  /* 뜬 직후의 blur는 사용자가 다른 곳을 누른 게 아니라 클릭이 끝나면서 포커스가
     되돌아간 것이다. 그걸 취소로 받으면 입력창이 뜨자마자 사라진다.
     짧은 유예 동안은 blur를 무시하고 포커스를 되찾는다. */
  const settledRef = useRef(false);
  useEffect(() => {
    const timer = setTimeout(() => {
      settledRef.current = true;
    }, 300);
    inputRef.current?.focus();
    return () => clearTimeout(timer);
  }, []);

  return (
    <input
      ref={inputRef}
      autoFocus
      value={text}
      onChange={(e) => setText(e.target.value)}
      onKeyDown={(e) => {
        // 한글 입력 중 조합을 확정하는 Enter도 keydown으로 들어온다. 그걸 제출로 받으면
        // 마지막 글자가 빠진 채 저장된다. 조합이 끝난 Enter만 제출로 본다.
        if (e.nativeEvent.isComposing) return;
        if (e.key === 'Enter' && text.trim()) onCommit(text.trim());
        if (e.key === 'Escape') onCancel();
      }}
      onBlur={() => {
        if (!settledRef.current) {
          inputRef.current?.focus();
          return;
        }
        if (text.trim()) onCommit(text.trim());
        else onCancel();
      }}
      placeholder={placeholder}
      className="absolute z-20 h-9 w-48 -translate-x-1/2 -translate-y-1/2 rounded-lg border border-ink bg-white px-2 text-sm shadow-lg outline-none"
      style={{ left: point.x, top: point.y }}
    />
  );
}
