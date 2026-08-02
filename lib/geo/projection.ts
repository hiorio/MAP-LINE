import type { Point } from './rdp';

export interface LatLng {
  lat: number;
  lng: number;
}

/**
 * 화면 좌표 ↔ 지리 좌표 변환의 최소 계약.
 * DrawCanvas는 카카오 SDK가 아니라 이 인터페이스에만 의존하므로
 * 테스트에서 가짜 구현으로 대체할 수 있다.
 */
export interface ScreenProjection {
  toScreen(coord: LatLng): Point;
  toCoord(point: Point): LatLng;
}

/** 카카오 지도 레벨 범위. 1이 최대 확대, 14가 최대 축소로 방향이 뒤집혀 있다. */
export const MIN_LEVEL = 1;
export const MAX_LEVEL = 14;

export const SCALE_CLAMP_MIN = 0.35;
export const SCALE_CLAMP_MAX = 1.2;
export const FADE_FREE_LEVELS = 2;

/**
 * 그린 시점과 다른 줌에서 보일 때의 선 굵기 보정.
 *
 * 획을 지리 좌표에 고정하면 축소할수록 화면상 획이 짧아진다. 굵기를 그대로 두면
 * 축소 시 선이 뭉툭한 덩어리로 남고, 지리 비율대로 줄이면 실 한 올이 되어 사라진다.
 * 양쪽을 clamp로 막는다.
 */
export function strokeRenderWidth(baseWidth: number, zoomCreated: number, level: number): number {
  const scale = Math.pow(2, zoomCreated - level);
  return baseWidth * Math.min(SCALE_CLAMP_MAX, Math.max(SCALE_CLAMP_MIN, scale));
}

/**
 * 그린 줌에서 멀어질수록 흐리게 만든다.
 * 줌 3에서 그린 섬세한 선이 줌 10에서 뭉개진 채 선명하게 남는 것보다는 낫다.
 */
export function strokeRenderAlpha(zoomCreated: number, level: number): number {
  const delta = Math.abs(zoomCreated - level);
  if (delta <= FADE_FREE_LEVELS) return 1;
  return Math.max(0.35, 1 - (delta - FADE_FREE_LEVELS) * 0.16);
}

/**
 * Kakao Local API는 x가 경도, y가 위도다. 순서가 직관과 반대이므로
 * 좌표를 다루는 경계마다 이 함수를 거치게 해 실수를 한곳에 가둔다.
 */
export function fromKakaoXY(x: string | number, y: string | number): LatLng {
  return { lat: Number(y), lng: Number(x) };
}

/** PostGIS geography는 POINT(경도 위도) 순서다. */
export function toWkbPoint({ lat, lng }: LatLng): string {
  return `POINT(${lng} ${lat})`;
}

export function toGeoJsonLineString(path: readonly LatLng[]) {
  return {
    type: 'LineString' as const,
    coordinates: path.map(({ lat, lng }) => [lng, lat] as [number, number]),
  };
}
