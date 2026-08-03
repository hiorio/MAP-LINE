import { create } from 'zustand';
import { createId } from '@/lib/id';
import { syncLegLength } from '@/lib/map/legs';
import {
  DEFAULT_FONT_SIZE,
  DEFAULT_SHOW_CANDIDATE_LINKS,
  DEFAULT_SHOW_STOP_ARROWS,
  LABEL_COLOR,
  PIN_COLOR,
  STROKE_COLORS,
  STROKE_WIDTHS,
  type LatLng,
  type MapDocument,
  type MapLabel,
  type Place,
  type PlaceCandidate,
  type RoutePath,
  type Stop,
  type StopLeg,
  type Stroke,
  type TravelMode,
} from '@/lib/map/types';

/** 핀·메모는 모드가 아니라 지도를 꾹 눌러 그 자리에서 고른다. */
export type EditorMode = 'pan' | 'draw' | 'erase';
export type SaveState = 'idle' | 'dirty' | 'saving' | 'saved';

/**
 * 되돌리기는 획 배열 스냅샷을 쌓는다.
 *
 * 설계안은 "pop 방식"이라고 했지만 지우개가 중간 획을 지울 수 있으므로 단순 pop은
 * 엉뚱한 획을 되살린다. 획은 RDP를 거쳐 점 수십 개 수준이라 스냅샷을 떠도
 * 메모리가 문제되지 않고, §6.1의 "지도 단위 전체 스냅샷" 저장 전략과도 결이 같다.
 */
interface Snapshot {
  stops: Stop[];
  /** 단계 사이 구간. 길이는 언제나 stops.length - 1로 맞춰 둔다. */
  legs: StopLeg[];
  strokes: Stroke[];
  labels: MapLabel[];
}

const MAX_HISTORY = 50;

interface MapStore extends Snapshot {
  title: string;
  /** 자동으로 그리는 선의 표시 여부. 문서에 담겨 공유된다. */
  showCandidateLinks: boolean;
  showStopArrows: boolean;
  mode: EditorMode;
  color: string;
  width: number;
  saveState: SaveState;
  history: Snapshot[];

  setTitle: (title: string) => void;
  setShowCandidateLinks: (show: boolean) => void;
  setShowStopArrows: (show: boolean) => void;
  setMode: (mode: EditorMode) => void;
  setColor: (color: string) => void;
  setWidth: (width: number) => void;
  setSaveState: (state: SaveState) => void;

  addStroke: (stroke: Stroke) => void;
  removeStroke: (id: string) => void;
  addLabel: (label: MapLabel) => void;
  /** 글자를 고치거나 위치를 옮길 때 쓴다. */
  updateLabel: (id: string, patch: Partial<Omit<MapLabel, 'id'>>) => void;
  removeLabel: (id: string) => void;

  /** 고른 장소들을 새 단계 하나로 담는다. 여러 개면 그 단계의 후보가 된다. */
  addStop: (candidates: Place[]) => void;
  /** 이미 있는 단계에 후보를 더한다. */
  addCandidates: (stopId: string, candidates: Place[]) => void;
  /** 후보 하나를 뺀다. 마지막 후보가 빠지면 단계도 사라진다. */
  removeCandidate: (placeId: string) => void;
  removeStop: (stopId: string) => void;
  moveStop: (from: number, to: number) => void;
  /** 실제 경로의 기준이 될 후보를 정한다. 같은 후보를 다시 누르면 해제된다. */
  setPrimary: (stopId: string, placeId: string) => void;

  /** 구간의 이동수단. 사용자의 의도라 경로를 못 받아도 남는다. */
  setLegMode: (index: number, mode: TravelMode) => void;
  /** 길찾기 결과를 채운다. null이면 이 수단으로는 갈 수 없다는 뜻이다. */
  setLegRoute: (index: number, route: RoutePath | null) => void;

  undo: () => void;
  clearAll: () => void;
  hydrate: (document: Partial<MapDocument>) => void;
}

export const useMapStore = create<MapStore>((set, get) => ({
  title: '',
  showCandidateLinks: DEFAULT_SHOW_CANDIDATE_LINKS,
  showStopArrows: DEFAULT_SHOW_STOP_ARROWS,
  mode: 'pan',
  color: STROKE_COLORS[0],
  width: STROKE_WIDTHS[0],
  saveState: 'idle',
  stops: [],
  legs: [],
  strokes: [],
  labels: [],
  history: [],

  setTitle: (title) => set({ title, saveState: 'dirty' }),
  // 되돌리기 대상은 아니다. 제목과 마찬가지로 문서 설정이지 편집 내용이 아니다.
  setShowCandidateLinks: (showCandidateLinks) => set({ showCandidateLinks, saveState: 'dirty' }),
  setShowStopArrows: (showStopArrows) => set({ showStopArrows, saveState: 'dirty' }),
  setMode: (mode) => set({ mode }),
  setColor: (color) => set({ color }),
  setWidth: (width) => set({ width }),
  setSaveState: (saveState) => set({ saveState }),

  addStroke: (stroke) =>
    set((s) => ({ ...commit(s), strokes: [...s.strokes, stroke] })),

  removeStroke: (id) =>
    set((s) => ({ ...commit(s), strokes: s.strokes.filter((x) => x.id !== id) })),

  addLabel: (label) => set((s) => ({ ...commit(s), labels: [...s.labels, label] })),

  updateLabel: (id, patch) =>
    set((s) => {
      const labels = s.labels.map((label) =>
        label.id === id ? { ...label, ...patch } : label,
      );
      return labels.some((label, i) => label !== s.labels[i])
        ? { ...commit(s), labels }
        : s;
    }),

  removeLabel: (id) =>
    set((s) => ({ ...commit(s), labels: s.labels.filter((x) => x.id !== id) })),

  addStop: (candidates) =>
    set((s) =>
      candidates.length === 0
        ? s
        : withStops(s, [...s.stops, { id: createId(), candidates }]),
    ),

  addCandidates: (stopId, candidates) =>
    set((s) =>
      candidates.length === 0
        ? s
        : withStops(
            s,
            s.stops.map((stop) =>
              stop.id === stopId
                ? { ...stop, candidates: [...stop.candidates, ...candidates] }
                : stop,
            ),
          ),
    ),

  removeCandidate: (placeId) =>
    set((s) => {
      const stops = s.stops
        .map((stop) => dropDanglingPrimary({
          ...stop,
          candidates: stop.candidates.filter((place) => place.id !== placeId),
        }))
        // 후보가 하나도 없는 단계는 존재할 이유가 없다. 번호만 비어 보인다.
        .filter((stop) => stop.candidates.length > 0);

      return stops.length === s.stops.length &&
        stops.every((stop, i) => stop.candidates.length === s.stops[i]!.candidates.length)
        ? s
        : withStops(s, stops);
    }),

  removeStop: (stopId) =>
    set((s) => withStops(s, s.stops.filter((stop) => stop.id !== stopId))),

  /** 배열 순서가 곧 단계 번호다. 이 배열을 유일한 근거로 둔다. */
  moveStop: (from, to) =>
    set((s) => {
      if (from === to || from < 0 || to < 0 || from >= s.stops.length || to >= s.stops.length) {
        return s;
      }
      const next = [...s.stops];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved!);
      // 구간의 모드는 자리에 남는다. 끝점이 달라진 경로는 그릴 때 걸러진다.
      return withStops(s, next);
    }),

  setPrimary: (stopId, placeId) =>
    set((s) => {
      const stops = s.stops.map((stop) => {
        if (stop.id !== stopId) return stop;
        if (!stop.candidates.some((place) => place.id === placeId)) return stop;
        // 같은 후보를 다시 누르면 "아직 안 정함"으로 되돌린다.
        if (stop.primaryId === placeId) return withoutPrimary(stop);
        return { ...stop, primaryId: placeId };
      });
      return stops.every((stop, i) => stop === s.stops[i]) ? s : withStops(s, stops);
    }),

  setLegMode: (index, mode) =>
    set((s) => {
      const current = s.legs[index];
      if (!current || current.mode === mode) return s;
      const legs = [...s.legs];
      // 수단이 바뀌면 이전 경로는 다른 수단의 것이다. 남겨 두면 잠깐 틀린 선이 보인다.
      legs[index] = { mode };
      return { ...commit(s), legs };
    }),

  setLegRoute: (index, route) =>
    set((s) => {
      const current = s.legs[index];
      if (!current) return s;
      const legs = [...s.legs];
      legs[index] = route ? { mode: current.mode, route } : { mode: current.mode };
      // 길찾기 결과는 되돌리기 대상이 아니다. 사용자가 한 일이 아니라 받아 온 값이다.
      return { legs, saveState: 'dirty' as const };
    }),

  undo: () => {
    const { history } = get();
    const previous = history.at(-1);
    if (!previous) return;
    set({
      stops: previous.stops,
      legs: previous.legs,
      strokes: previous.strokes,
      labels: previous.labels,
      history: history.slice(0, -1),
      saveState: 'dirty',
    });
  },

  clearAll: () =>
    set((s) => (s.stops.length + s.strokes.length + s.labels.length === 0
      ? s
      : { ...commit(s), stops: [], legs: [], strokes: [], labels: [] })),

  hydrate: (document) => {
    const stops = document.stops ?? [];
    set({
      title: document.title ?? '',
      showCandidateLinks: document.showCandidateLinks ?? DEFAULT_SHOW_CANDIDATE_LINKS,
      showStopArrows: document.showStopArrows ?? DEFAULT_SHOW_STOP_ARROWS,
      stops,
      // 예전에 저장된 지도에는 구간이 없다. 단계 수에 맞춰 직선으로 채운다.
      legs: syncLegLength(stops, document.legs ?? []),
      strokes: document.strokes ?? [],
      labels: document.labels ?? [],
      history: [],
      saveState: 'idle',
    });
  },
}));

/** 단계를 갈아끼우면서 구간 배열을 따라 맞춘다. 둘은 항상 같이 움직여야 한다. */
function withStops(state: Snapshot & { history: Snapshot[] }, stops: Stop[]) {
  return { ...commit(state), stops, legs: syncLegLength(stops, state.legs) };
}

/** 대표로 지정한 후보가 사라졌으면 지정도 지운다. 없는 곳을 가리키게 두지 않는다. */
function dropDanglingPrimary(stop: Stop): Stop {
  if (!stop.primaryId) return stop;
  if (stop.candidates.some((place) => place.id === stop.primaryId)) return stop;
  return withoutPrimary(stop);
}

/** 키 자체를 없앤다. undefined를 남기면 저장 페이로드에 빈 값이 실린다. */
function withoutPrimary(stop: Stop): Stop {
  const next = { ...stop };
  delete next.primaryId;
  return next;
}

/** 변경 직전 상태를 히스토리에 밀어 넣고 저장 상태를 dirty로 돌린다. */
function commit(state: Snapshot & { history: Snapshot[] }) {
  const snapshot: Snapshot = {
    stops: state.stops,
    legs: state.legs,
    strokes: state.strokes,
    labels: state.labels,
  };
  return {
    history: [...state.history, snapshot].slice(-MAX_HISTORY),
    saveState: 'dirty' as const,
  };
}

export function createPlace(
  location: LatLng,
  name: string,
  source?: { address?: string | undefined; kakaoPlaceId?: string | undefined },
): Place {
  return {
    id: createId(),
    name,
    ...(source?.address ? { address: source.address } : {}),
    ...(source?.kakaoPlaceId ? { kakaoPlaceId: source.kakaoPlaceId } : {}),
    location,
    pinColor: PIN_COLOR,
  };
}

export function placeFromCandidate(candidate: PlaceCandidate): Place {
  return createPlace(candidate.location, candidate.name, {
    ...(candidate.roadAddress ?? candidate.address
      ? { address: candidate.roadAddress ?? candidate.address }
      : {}),
    kakaoPlaceId: candidate.kakaoPlaceId,
  });
}

export function createLabel(location: MapLabel['location'], text: string): MapLabel {
  return {
    id: createId(),
    location,
    text,
    fontSize: DEFAULT_FONT_SIZE,
    color: LABEL_COLOR,
  };
}
