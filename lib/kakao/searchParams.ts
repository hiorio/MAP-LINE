import type { LatLng } from '@/lib/map/types';

/**
 * 검색 기준점 파싱. 값이 없거나 말이 안 되면 undefined를 돌려주고,
 * 호출부는 기준점 없이(정확도순으로) 검색한다.
 *
 * 좌표는 클라이언트가 보내는 값이므로 그대로 믿지 않는다.
 */
export function readCenterParams(lat: unknown, lng: unknown): LatLng | undefined {
  // Number('')와 Number(null)은 0이다. 그대로 두면 빈 값이 좌표 (0,0) —
  // 기니만 앞바다 — 로 통과해 엉뚱한 곳을 기준으로 검색하게 된다.
  if (!isNumericInput(lat) || !isNumericInput(lng)) return undefined;

  const latitude = Number(lat);
  const longitude = Number(lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return undefined;
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return undefined;

  return { lat: latitude, lng: longitude };
}

function isNumericInput(value: unknown): boolean {
  if (typeof value === 'number') return true;
  return typeof value === 'string' && value.trim() !== '';
}
