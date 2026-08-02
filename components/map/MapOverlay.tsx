'use client';

import { useEffect, useRef, useState } from 'react';
import { createId } from '@/lib/id';
import { distanceToPolyline, simplify, type Point } from '@/lib/geo/rdp';
import { hitsLabel, hitsPin, hitsSavedMarker } from '@/lib/render/scene';
import { flattenStops, type LatLng, type PlaceCandidate, type Stroke } from '@/lib/map/types';
import { createLabel, createPlace, useMapStore } from '@/store/useMapStore';
import { useSavedPlacesStore } from '@/store/useSavedPlacesStore';
import type { SavedPlace } from '@/lib/map/savedPlaces';
import { LongPressMenu } from './LongPressMenu';
import { SavedMarkerMenu } from './SavedMarkerMenu';
import { useLongPress } from './useLongPress';
import { useMapCanvas } from './useMapCanvas';

/* W0에서 실제로 만져 보고 확정한 값들. 근거는 README의 검증 체크리스트 참고. */
const RDP_EPSILON_PX = 2;
const MIN_SAMPLE_PX = 1.5;
const ERASE_HIT_PX = 14;
/** 이만큼 움직이기 전까지는 탭으로 본다. 손이 살짝 떨렸다고 라벨이 옮겨지면 안 된다. */
const LABEL_DRAG_PX = 4;

interface LiveStroke {
  points: Point[];
  color: string;
  width: number;
}

interface Draft {
  kind: 'label' | 'place';
  point: Point;
  coord: LatLng;
  /** 있으면 새로 만드는 게 아니라 이 라벨의 글자를 고치는 중이다. */
  editingLabelId?: string;
  initialText?: string;
}

/**
 * 이동 모드에서 지도 대신 우리가 처리하기로 한 입력.
 *
 * 라벨은 끌어서 옮기고 탭하면 고친다. 보관함 마커는 위치가 카카오에서 온 값이라
 * 옮길 이유가 없고, 탭했을 때 무엇을 할지만 고르게 한다.
 */
type Capture =
  | { kind: 'label'; id: string; start: Point; moved: boolean }
  | { kind: 'saved'; id: string; start: Point };

export function MapOverlay({
  map,
  container,
}: {
  map: kakao.maps.Map | null;
  container: HTMLElement | null;
}) {
  const liveRef = useRef<LiveStroke | null>(null);
  const captureRef = useRef<Capture | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [draggedLabel, setDraggedLabel] = useState<{ id: string; coord: LatLng } | null>(null);
  const [menu, setMenu] = useState<{ point: Point; coord: LatLng } | null>(null);
  const [savedMenu, setSavedMenu] = useState<{ point: Point; place: SavedPlace } | null>(null);

  const stops = useMapStore((s) => s.stops);
  const strokes = useMapStore((s) => s.strokes);
  const labels = useMapStore((s) => s.labels);
  const mode = useMapStore((s) => s.mode);
  const showCandidateLinks = useMapStore((s) => s.showCandidateLinks);
  const showStopArrows = useMapStore((s) => s.showStopArrows);

  const savedPlaces = useSavedPlacesStore((s) => s.places);
  const savedVisible = useSavedPlacesStore((s) => s.visible);
  const visibleSaved = savedVisible ? savedPlaces : [];

  // 끄는 동안에는 확정 전 위치로 그린다.
  const renderedLabels = draggedLabel
    ? labels.map((label) =>
        label.id === draggedLabel.id ? { ...label, location: draggedLabel.coord } : label,
      )
    : labels;

  const { canvasRef, toScreen, toCoord, redraw } = useMapCanvas({
    map,
    scene: {
      stops,
      strokes,
      labels: renderedLabels,
      saved: visibleSaved,
      showCandidateLinks,
      showStopArrows,
    },
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

  /* 그리기·지우개 중에는 지도 제스처를 완전히 잠근다. 이걸 안 하면 손가락 한 번에
     그림 절반, 지도 팬 절반이 되어 사용할 수 없는 UX가 된다. */
  useEffect(() => {
    if (!map) return;
    const drawing = mode !== 'pan';
    map.setDraggable(!drawing);
    map.setZoomable(!drawing);
    setDraft(null);
    setMenu(null);
    setSavedMenu(null);
  }, [map, mode]);

  /* ---------------------------------------------------------------- 이동 모드
     기본은 지도 이동이다. 꾹 누르면 무엇을 놓을지 고르는 메뉴가 뜨고,
     이미 놓인 라벨을 짚으면 그것만 가로채 수정·이동한다. */
  const labelAt = (point: Point) => {
    if (!map) return null;
    const { labels: current } = useMapStore.getState();
    for (let i = current.length - 1; i >= 0; i--) {
      const label = current[i]!;
      if (hitsLabel(point, label, toScreen(label.location))) return label;
    }
    return null;
  };

  const savedAt = (point: Point) => {
    if (!map || !savedVisible) return null;
    const { places } = useSavedPlacesStore.getState();
    for (let i = places.length - 1; i >= 0; i--) {
      const place = places[i]!;
      if (hitsSavedMarker(point, toScreen(place.location))) return place;
    }
    return null;
  };

  useLongPress({
    target: mode === 'pan' ? container : null,
    onLongPress: (point) => {
      if (!map) return;
      setMenu({ point, coord: toCoord(point) });
    },
    // 라벨이 위에 그려지므로 먼저 본다.
    shouldCapture: (point) => labelAt(point) !== null || savedAt(point) !== null,
    onCapturedDown: (point) => {
      const label = labelAt(point);
      if (label) {
        captureRef.current = { kind: 'label', id: label.id, start: point, moved: false };
        return;
      }
      const saved = savedAt(point);
      if (saved) captureRef.current = { kind: 'saved', id: saved.id, start: point };
    },
    onCapturedMove: (point) => {
      const capture = captureRef.current;
      // 보관함 마커의 좌표는 카카오에서 온 값이다. 끌어서 옮길 이유가 없다.
      if (capture?.kind !== 'label') return;
      if (
        !capture.moved &&
        Math.hypot(point.x - capture.start.x, point.y - capture.start.y) < LABEL_DRAG_PX
      ) {
        return;
      }
      capture.moved = true;
      setDraggedLabel({ id: capture.id, coord: toCoord(point) });
    },
    onCapturedUp: () => finishCapture(),
  });

  const finishCapture = () => {
    const capture = captureRef.current;
    if (!capture) return;
    captureRef.current = null;

    if (capture.kind === 'saved') {
      const place = useSavedPlacesStore.getState().places.find((item) => item.id === capture.id);
      if (place) setSavedMenu({ point: capture.start, place });
      return;
    }

    const label = useMapStore.getState().labels.find((item) => item.id === capture.id);
    if (capture.moved) {
      // 끄는 동안에는 화면에만 그렸다. 손을 뗄 때 한 번만 기록한다.
      if (draggedLabel) {
        useMapStore.getState().updateLabel(capture.id, { location: draggedLabel.coord });
      }
    } else if (label) {
      setDraft({
        kind: 'label',
        point: capture.start,
        coord: label.location,
        editingLabelId: label.id,
        initialText: label.text,
      });
    }
    setDraggedLabel(null);
  };

  /** 보관함 장소를 코스에 담을 때 쓸 형태로 바꾼다. */
  const placeFromSaved = (place: SavedPlace) =>
    createPlace(place.location, place.name, {
      ...(place.address ? { address: place.address } : {}),
      ...(place.kakaoPlaceId ? { kakaoPlaceId: place.kakaoPlaceId } : {}),
    });

  /* ------------------------------------------------- 그리기·지우개 모드 입력 */
  const eventPoint = (event: React.PointerEvent<HTMLCanvasElement>): Point => {
    const rect = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  const handlePointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!map) return;

    /* 뒤따르는 mousedown이 포커스를 캔버스로 옮기지 못하게 막는다.
       막지 않으면 입력창이 뜨자마자 blur되어 스스로 취소한다. */
    event.preventDefault();
    const point = eventPoint(event);

    if (mode === 'erase') return eraseAt(point);
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
    useMapStore.getState().addStroke({
      id: createId(),
      path: simplified.map(toCoord),
      color: live.color,
      width: live.width,
      zoomCreated: map.getLevel(),
    } satisfies Stroke);
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
    const saved = savedAt(point);
    if (saved) return useSavedPlacesStore.getState().remove(saved.id);
    for (let i = state.strokes.length - 1; i >= 0; i--) {
      const stroke = state.strokes[i]!;
      if (distanceToPolyline(point, stroke.path.map(toScreen)) < ERASE_HIT_PX) {
        return state.removeStroke(stroke.id);
      }
    }
  };

  const drawing = mode !== 'pan';

  return (
    <>
      <canvas
        ref={canvasRef}
        className="absolute inset-0 z-10 touch-none transition-opacity duration-100"
        style={{
          // 이동 모드에서는 캔버스가 이벤트를 받지 않아야 지도가 움직인다.
          pointerEvents: drawing ? 'auto' : 'none',
          cursor: drawing ? 'crosshair' : 'default',
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={commitStroke}
        onPointerCancel={commitStroke}
      />

      {menu && (
        <LongPressMenu
          point={menu.point}
          coord={menu.coord}
          onClose={() => setMenu(null)}
          onPickPlace={(candidate: PlaceCandidate) => {
            useMapStore.getState().addStop([
              createPlace(candidate.location, candidate.name, {
                ...(candidate.roadAddress ?? candidate.address
                  ? { address: candidate.roadAddress ?? candidate.address }
                  : {}),
                ...(candidate.kakaoPlaceId ? { kakaoPlaceId: candidate.kakaoPlaceId } : {}),
              }),
            ]);
            setMenu(null);
          }}
          onDropPin={() => {
            setDraft({ kind: 'place', point: menu.point, coord: menu.coord });
            setMenu(null);
          }}
          onAddLabel={() => {
            setDraft({ kind: 'label', point: menu.point, coord: menu.coord });
            setMenu(null);
          }}
        />
      )}

      {savedMenu && (
        <SavedMarkerMenu
          point={savedMenu.point}
          place={savedMenu.place}
          stops={stops}
          onClose={() => setSavedMenu(null)}
          onAddAsStop={() => {
            useMapStore.getState().addStop([placeFromSaved(savedMenu.place)]);
            setSavedMenu(null);
          }}
          onAddToStop={(stopId) => {
            useMapStore.getState().addCandidates(stopId, [placeFromSaved(savedMenu.place)]);
            setSavedMenu(null);
          }}
          onRemove={() => {
            useSavedPlacesStore.getState().remove(savedMenu.place.id);
            setSavedMenu(null);
          }}
        />
      )}

      {draft && (
        <DraftInput
          key={draft.editingLabelId ?? `${draft.kind}-${draft.point.x}-${draft.point.y}`}
          point={draft.point}
          initialText={draft.initialText ?? ''}
          placeholder={
            draft.kind === 'place'
              ? '장소 이름 후 Enter'
              : draft.editingLabelId
                ? '메모 수정 후 Enter'
                : '메모 입력 후 Enter'
          }
          onCancel={() => setDraft(null)}
          onCommit={(text) => {
            const store = useMapStore.getState();
            if (draft.editingLabelId) store.updateLabel(draft.editingLabelId, { text });
            else if (draft.kind === 'place') store.addStop([createPlace(draft.coord, text)]);
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
  initialText,
  onCommit,
  onCancel,
}: {
  point: Point;
  placeholder: string;
  initialText: string;
  onCommit: (text: string) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState(initialText);
  const inputRef = useRef<HTMLInputElement>(null);

  /* 뜬 직후의 blur는 사용자가 다른 곳을 누른 게 아니라 클릭이 끝나면서 포커스가
     되돌아간 것이다. 그걸 취소로 받으면 입력창이 뜨자마자 사라진다. */
  const settledRef = useRef(false);
  useEffect(() => {
    const timer = setTimeout(() => {
      settledRef.current = true;
    }, 300);
    inputRef.current?.focus();
    // 고치는 경우엔 전체를 잡아 둔다. 바로 다시 쓰거나 지우기 편하다.
    if (initialText) inputRef.current?.select();
    return () => clearTimeout(timer);
    // 마운트 시 한 번만. initialText는 key로 새 인스턴스를 만들어 반영한다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
      className="absolute z-40 h-9 w-48 -translate-x-1/2 -translate-y-1/2 rounded-lg border border-ink bg-white px-2 text-sm shadow-lg outline-none"
      style={{ left: point.x, top: point.y }}
    />
  );
}
