import { create } from 'zustand';
import { createId } from '@/lib/id';
import {
  DEFAULT_FONT_SIZE,
  LABEL_COLOR,
  PIN_COLOR,
  STROKE_COLORS,
  STROKE_WIDTHS,
  type LatLng,
  type MapDocument,
  type MapLabel,
  type Place,
  type PlaceCandidate,
  type Stroke,
  type TravelMode,
} from '@/lib/map/types';

export type EditorMode = 'pan' | 'draw' | 'erase' | 'label' | 'place';
export type SaveState = 'idle' | 'dirty' | 'saving' | 'saved';

/**
 * 되돌리기는 획 배열 스냅샷을 쌓는다.
 *
 * 설계안은 "pop 방식"이라고 했지만 지우개가 중간 획을 지울 수 있으므로 단순 pop은
 * 엉뚱한 획을 되살린다. 획은 RDP를 거쳐 점 수십 개 수준이라 스냅샷을 떠도
 * 메모리가 문제되지 않고, §6.1의 "지도 단위 전체 스냅샷" 저장 전략과도 결이 같다.
 */
interface Snapshot {
  places: Place[];
  strokes: Stroke[];
  labels: MapLabel[];
}

const MAX_HISTORY = 50;

interface MapStore extends Snapshot {
  title: string;
  mode: EditorMode;
  color: string;
  width: number;
  saveState: SaveState;
  history: Snapshot[];

  setTitle: (title: string) => void;
  setMode: (mode: EditorMode) => void;
  setColor: (color: string) => void;
  setWidth: (width: number) => void;
  setSaveState: (state: SaveState) => void;

  addStroke: (stroke: Stroke) => void;
  removeStroke: (id: string) => void;
  addLabel: (label: MapLabel) => void;
  removeLabel: (id: string) => void;

  addPlace: (place: Place) => void;
  removePlace: (id: string) => void;
  updatePlace: (id: string, patch: Partial<Omit<Place, 'id'>>) => void;
  movePlace: (from: number, to: number) => void;

  undo: () => void;
  clearAll: () => void;
  hydrate: (document: Partial<MapDocument>) => void;
}

export const useMapStore = create<MapStore>((set, get) => ({
  title: '',
  mode: 'pan',
  color: STROKE_COLORS[0],
  width: STROKE_WIDTHS[0],
  saveState: 'idle',
  places: [],
  strokes: [],
  labels: [],
  history: [],

  setTitle: (title) => set({ title, saveState: 'dirty' }),
  setMode: (mode) => set({ mode }),
  setColor: (color) => set({ color }),
  setWidth: (width) => set({ width }),
  setSaveState: (saveState) => set({ saveState }),

  addStroke: (stroke) =>
    set((s) => ({ ...commit(s), strokes: [...s.strokes, stroke] })),

  removeStroke: (id) =>
    set((s) => ({ ...commit(s), strokes: s.strokes.filter((x) => x.id !== id) })),

  addLabel: (label) => set((s) => ({ ...commit(s), labels: [...s.labels, label] })),

  removeLabel: (id) =>
    set((s) => ({ ...commit(s), labels: s.labels.filter((x) => x.id !== id) })),

  addPlace: (place) => set((s) => ({ ...commit(s), places: [...s.places, place] })),

  removePlace: (id) =>
    set((s) => ({ ...commit(s), places: s.places.filter((x) => x.id !== id) })),

  updatePlace: (id, patch) =>
    set((s) => ({
      ...commit(s),
      places: s.places.map((x) => (x.id === id ? { ...x, ...patch } : x)),
    })),

  /** 순서가 곧 핀 번호이자 연결선의 방향이다. 배열 순서를 유일한 근거로 둔다. */
  movePlace: (from, to) =>
    set((s) => {
      if (from === to || from < 0 || to < 0 || from >= s.places.length || to >= s.places.length) {
        return s;
      }
      const next = [...s.places];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved!);
      return { ...commit(s), places: next };
    }),

  undo: () => {
    const { history } = get();
    const previous = history.at(-1);
    if (!previous) return;
    set({
      places: previous.places,
      strokes: previous.strokes,
      labels: previous.labels,
      history: history.slice(0, -1),
      saveState: 'dirty',
    });
  },

  clearAll: () =>
    set((s) => (s.places.length + s.strokes.length + s.labels.length === 0
      ? s
      : { ...commit(s), places: [], strokes: [], labels: [] })),

  hydrate: (document) =>
    set({
      title: document.title ?? '',
      places: document.places ?? [],
      strokes: document.strokes ?? [],
      labels: document.labels ?? [],
      history: [],
      saveState: 'idle',
    }),
}));

/** 변경 직전 상태를 히스토리에 밀어 넣고 저장 상태를 dirty로 돌린다. */
function commit(state: Snapshot & { history: Snapshot[] }) {
  const snapshot: Snapshot = {
    places: state.places,
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
  source?: Pick<PlaceCandidate, 'address' | 'kakaoPlaceId'>,
): Place {
  return {
    id: createId(),
    name,
    ...(source?.address ? { address: source.address } : {}),
    ...(source?.kakaoPlaceId ? { kakaoPlaceId: source.kakaoPlaceId } : {}),
    location,
    pinColor: PIN_COLOR,
    modeToNext: 'walk' satisfies TravelMode,
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
