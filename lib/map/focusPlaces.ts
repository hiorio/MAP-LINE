import type { LatLng } from './types';

/**
 * 지도를 주어진 좌표들이 보이는 곳으로 옮긴다.
 *
 * 한 곳이면 그 지점을 중심에 둔다. `setBounds`에 점 하나를 주면 최대 배율까지 파고들어
 * 주변이 하나도 안 보이는 화면이 된다.
 */
export function focusPlaces(
  map: kakao.maps.Map | null,
  coords: readonly LatLng[],
  padding = 32,
): void {
  if (!map || coords.length === 0) return;

  if (coords.length === 1) {
    const only = coords[0]!;
    map.setCenter(new kakao.maps.LatLng(only.lat, only.lng));
    return;
  }

  const bounds = new kakao.maps.LatLngBounds();
  for (const coord of coords) {
    bounds.extend(new kakao.maps.LatLng(coord.lat, coord.lng));
  }
  map.setBounds(bounds, padding, padding, padding, padding);
}
