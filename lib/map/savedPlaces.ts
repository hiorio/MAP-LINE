import type { LatLng } from './types';

/**
 * 여러 지도에 걸쳐 재사용하는 개인 장소 보관함.
 *
 * 카카오맵·네이버지도의 "저장"과 같은 자리를 노린다. 다만 계정이 없으므로 이 브라우저의
 * localStorage에만 남는다. 기기를 바꾸거나 저장소를 비우면 사라진다. 계정을 붙이는
 * v1.0에서 서버로 옮길 자리다.
 *
 * **공유되는 지도 문서에는 들어가지 않는다.** 보관함은 내가 모아 둔 목록이고, 링크를
 * 받은 사람이 볼 것은 내가 코스에 올린 단계뿐이다.
 */
const STORAGE_KEY = 'mapline.saved';

export interface SavedPlace {
  id: string;
  name: string;
  address?: string;
  kakaoPlaceId?: string;
  location: LatLng;
  savedAt: string;
}

export function loadSavedPlaces(): SavedPlace[] {
  if (typeof window === 'undefined') return [];
  try {
    const parsed = JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? '[]');
    return Array.isArray(parsed) ? parsed.filter(isSavedPlace) : [];
  } catch {
    return [];
  }
}

export function persistSavedPlaces(places: readonly SavedPlace[]): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(places));
  } catch {
    // 용량이 차면 더 담지 못할 뿐, 편집을 막을 이유는 없다.
  }
}

/**
 * 같은 장소인지 판단한다.
 *
 * 카카오에서 온 장소는 kakaoPlaceId가 유일한 근거다. 지도를 직접 찍어 만든 장소는
 * 그 값이 없으므로 이름과 좌표로 본다. 좌표는 부동소수라 정확히 같기를 기대하지 않고
 * 대략 10m 안쪽이면 같은 곳으로 취급한다.
 */
export function isSamePlace(a: Omit<SavedPlace, 'id' | 'savedAt'>, b: SavedPlace): boolean {
  if (a.kakaoPlaceId && b.kakaoPlaceId) return a.kakaoPlaceId === b.kakaoPlaceId;
  if (a.name !== b.name) return false;
  return (
    Math.abs(a.location.lat - b.location.lat) < 1e-4 &&
    Math.abs(a.location.lng - b.location.lng) < 1e-4
  );
}

function isSavedPlace(value: unknown): value is SavedPlace {
  if (typeof value !== 'object' || value === null) return false;
  const place = value as Partial<SavedPlace>;
  return (
    typeof place.id === 'string' &&
    typeof place.name === 'string' &&
    typeof place.location?.lat === 'number' &&
    typeof place.location?.lng === 'number'
  );
}
