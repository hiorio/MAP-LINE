import { create } from 'zustand';
import { createId } from '@/lib/id';
import {
  isSamePlace,
  loadSavedPlaces,
  persistSavedPlaces,
  type SavedPlace,
} from '@/lib/map/savedPlaces';
import type { LatLng } from '@/lib/map/types';

/**
 * 보관함은 지도 문서와 분리된 상태다.
 *
 * `useMapStore`에 넣지 않는 이유: 그쪽은 저장·되돌리기·공유의 단위이고, 보관함은
 * 지도가 바뀌어도 그대로 남는 개인 목록이다. 섞으면 보관함을 건드릴 때마다
 * 지도가 dirty가 되고 되돌리기 기록에도 쌓인다.
 */
export type SavedPlaceInput = Omit<SavedPlace, 'id' | 'savedAt'>;

interface SavedPlacesStore {
  places: SavedPlace[];
  /** 지도 위에 보관함을 겹쳐 보일지. 많이 모으면 지도가 시끄러워진다. */
  visible: boolean;
  hydrated: boolean;

  hydrate: () => void;
  toggle: (place: SavedPlaceInput) => void;
  remove: (id: string) => void;
  setVisible: (visible: boolean) => void;
  isSaved: (place: SavedPlaceInput) => boolean;
}

export const useSavedPlacesStore = create<SavedPlacesStore>((set, get) => ({
  places: [],
  visible: true,
  hydrated: false,

  // localStorage는 서버 렌더 결과와 다르므로 마운트 후에 읽는다.
  hydrate: () => {
    if (get().hydrated) return;
    set({ places: loadSavedPlaces(), hydrated: true });
  },

  toggle: (place) => {
    const { places } = get();
    const existing = places.find((saved) => isSamePlace(place, saved));

    const next = existing
      ? places.filter((saved) => saved.id !== existing.id)
      : [...places, { ...place, id: createId(), savedAt: new Date().toISOString() }];

    persistSavedPlaces(next);
    set({ places: next });
  },

  remove: (id) => {
    const next = get().places.filter((saved) => saved.id !== id);
    persistSavedPlaces(next);
    set({ places: next });
  },

  setVisible: (visible) => set({ visible }),

  isSaved: (place) => get().places.some((saved) => isSamePlace(place, saved)),
}));

export function savedPlaceLocation(place: SavedPlace): LatLng {
  return place.location;
}
