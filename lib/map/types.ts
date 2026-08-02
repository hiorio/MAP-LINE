import type { LatLng } from '../geo/projection';

export type { LatLng };

export interface Stroke {
  id: string;
  path: LatLng[];
  color: string;
  width: number;
  /** 그린 시점의 카카오 줌 레벨. 다른 줌에서 굵기·투명도를 보정하는 기준 */
  zoomCreated: number;
}

export interface MapLabel {
  id: string;
  location: LatLng;
  text: string;
  fontSize: number;
  color: string;
}

/**
 * 코스의 한 단계. 지도 위 번호 하나에 대응한다.
 *
 * 후보를 여러 개 담을 수 있는 이유: 모임을 짤 때 "2번은 점심인데 어디로 갈지는
 * 아직 안 정했다"가 흔하다. 후보를 함께 공유해서 같이 고르는 것이 이 제품의 쓰임새다.
 *
 * 단계 자체에는 속성이 없다. 후보 목록이 곧 단계이므로 별도 식별자를 서버에 저장하지
 * 않고, 불러올 때 순번으로 묶어 다시 만든다.
 */
export interface Stop {
  id: string;
  candidates: Place[];
}

/** 검색 결과. 아직 지도에 담기지 않은 후보다. */
export interface PlaceCandidate {
  kakaoPlaceId: string;
  name: string;
  address?: string;
  roadAddress?: string;
  category?: string;
  location: LatLng;
  /** 검색 기준점에서의 거리(m). 기준점을 넘겼을 때만 있다. */
  distanceM?: number;
}

/** 거리 표기. 1km 미만은 m, 그 이상은 소수점 한 자리 km. */
export function formatDistance(meters: number): string {
  if (!Number.isFinite(meters) || meters < 0) return '';
  if (meters < 1000) return `${Math.round(meters)}m`;
  return `${(meters / 1000).toFixed(1)}km`;
}

export interface Place {
  id: string;
  name: string;
  address?: string;
  /**
   * 재조회용 식별자. 설계안 §10에 따라 영구 저장 대상은 이 값과 사용자가 입력한 메모뿐이고
   * 상호명·좌표는 캐시로 취급한다. 지도를 직접 찍어 만든 지점에는 없다.
   */
  kakaoPlaceId?: string;
  location: LatLng;
  memo?: string;
  pinColor: string;
}

export interface MapDocument {
  title: string;
  center: LatLng;
  zoomLevel: number;
  stops: Stop[];
  strokes: Stroke[];
  labels: MapLabel[];
}

/** 지도에 찍힌 모든 후보를 단계 번호와 함께 펼친다. 렌더와 히트 테스트가 쓴다. */
export function flattenStops(stops: readonly Stop[]): { place: Place; stopNumber: number }[] {
  return stops.flatMap((stop, index) =>
    stop.candidates.map((place) => ({ place, stopNumber: index + 1 })),
  );
}

/**
 * 단계의 대표 위치. 후보들의 평균 좌표다.
 *
 * 단계 사이 화살표를 그릴 때 쓴다. 후보가 여럿일 때 특정 후보에서 선을 뽑으면 나머지
 * 후보는 동선에서 빠진 것처럼 보인다. 무리의 가운데에서 출발시키면 "이 단계에서
 * 다음 단계로"만 말하게 되어 어느 후보를 고르든 틀리지 않는다.
 *
 * 한 동네 안에 흩어진 후보들이므로 구면 보정 없이 산술평균으로 충분하다.
 */
export function stopCentroid(stop: Stop): LatLng | null {
  if (stop.candidates.length === 0) return null;

  const sum = stop.candidates.reduce(
    (acc, place) => ({ lat: acc.lat + place.location.lat, lng: acc.lng + place.location.lng }),
    { lat: 0, lng: 0 },
  );
  return {
    lat: sum.lat / stop.candidates.length,
    lng: sum.lng / stop.candidates.length,
  };
}

export const PIN_COLOR = '#E24B4A';

export const STROKE_COLORS = ['#E24B4A', '#2D6BE4', '#2FA35B', '#2C2C2A'] as const;
export const STROKE_WIDTHS = [4, 9] as const;
export const LABEL_COLOR = '#2C2C2A';
export const DEFAULT_FONT_SIZE = 14;

/** 강남역. 위치 권한 없이 첫 화면을 채우기 위한 기본값 */
export const DEFAULT_CENTER: LatLng = { lat: 37.4979, lng: 127.0276 };
export const DEFAULT_LEVEL = 3;
