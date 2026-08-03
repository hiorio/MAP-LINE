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
  /**
   * 대표 후보의 id. 실제 경로를 그릴 때 출발·도착점이 된다.
   *
   * 중간지점은 후보들의 평균이라 건물도 길도 아닌 가상의 점이고, 거기서 길찾기를
   * 시작할 수 없다. 그렇다고 첫 후보를 말없이 쓰면 나머지 후보가 동선에서 빠진 것처럼
   * 보인다. 어디를 기준으로 그린 경로인지 사람이 정하게 한다.
   */
  primaryId?: string;
}

/**
 * 단계에서 단계로 어떻게 이동하는가.
 *
 * 'straight'가 기본이다. 후보가 아직 여럿이라 어디로 갈지 안 정한 단계에까지
 * 정확한 경로를 그리면 정해진 것처럼 보인다.
 */
export type TravelMode = 'straight' | 'walk' | 'transit' | 'bicycle';

export const TRAVEL_MODES: readonly TravelMode[] = ['straight', 'walk', 'transit', 'bicycle'];

export function isTravelMode(value: unknown): value is TravelMode {
  return typeof value === 'string' && (TRAVEL_MODES as readonly string[]).includes(value);
}

/** 대중교통 경로를 이루는 한 구간. 노선 배지로 보여 준다. */
export interface TransitLeg {
  type: string;
  /** "2호선 (강남 > 역삼)" 같은 카카오가 준 안내 문구 */
  guidance: string;
  /**
   * 이 구간이 `RoutePath.points`에서 차지하는 좌표 개수.
   *
   * 대중교통 경로는 탈것 구간의 좌표만 이어 붙인 한 줄이다. 어디까지가 지하철이고
   * 어디부터 버스인지 알 수 없으면 사이의 환승 도보를 구분해 그릴 수 없다.
   * 개수를 남겨 두면 다시 잘라 낼 수 있다.
   */
  pointCount?: number;
}

/**
 * 길찾기로 받아 온 실제 경로.
 *
 * `fromPlaceId`/`toPlaceId`/`fetchedAt`을 함께 담는 이유: 끝점이 바뀌었는데 옛 경로를
 * 계속 그리면 조용히 틀린 그림이 된다. 어떤 두 지점을 언제 기준으로 구한 것인지 남겨
 * 두면 다시 구해야 하는지 스스로 판단할 수 있다. 카카오 운영정책이 요구하는
 * "캐시 후 최신 데이터로 유지"의 근거이기도 하다.
 */
export interface RoutePath {
  points: LatLng[];
  distanceM: number;
  durationS: number;
  /** 대중교통일 때만 있다. */
  legs?: TransitLeg[];
  fromPlaceId: string;
  toPlaceId: string;
  fetchedAt: string;
}

/**
 * 단계 사이 한 구간. `legs[i]`가 `stops[i] → stops[i+1]`에 대응한다.
 *
 * 배열 순서를 단계 번호의 유일한 근거로 두는 기존 규칙을 그대로 따른다.
 * 단계를 재배치하면 끝점이 달라지고, 그러면 `route`의 끝점 id가 어긋나 저절로 버려진다.
 */
export interface StopLeg {
  mode: TravelMode;
  /** 직선이거나 아직 못 구했으면 없다. */
  route?: RoutePath;
}

/**
 * 이 단계에서 길찾기의 기준이 될 장소.
 *
 * 후보가 하나면 고를 것이 없으므로 그것이 곧 대표다. 여럿인데 대표를 안 정했으면
 * 기준이 없다는 뜻이고, 그때는 경로를 그리지 않는 것이 정직하다.
 */
export function stopAnchor(stop: Stop): Place | null {
  if (stop.candidates.length === 1) return stop.candidates[0] ?? null;
  if (!stop.primaryId) return null;
  return stop.candidates.find((place) => place.id === stop.primaryId) ?? null;
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
  /** 단계 사이 구간. 길이는 항상 max(0, stops.length - 1)이다. */
  legs: StopLeg[];
  strokes: Stroke[];
  labels: MapLabel[];
  /**
   * 자동으로 그리는 선을 켤지 끌지.
   *
   * 문서에 담는 이유: 만든 사람이 직접 동선을 그리고 자동 화살표를 껐다면, 링크를 받은
   * 사람에게도 꺼져 있어야 한다. 편집기 개인 설정으로 두면 공유된 지도가 만든 사람이
   * 의도한 모습과 달라진다.
   */
  showCandidateLinks: boolean;
  showStopArrows: boolean;
}

export const DEFAULT_SHOW_CANDIDATE_LINKS = true;
export const DEFAULT_SHOW_STOP_ARROWS = true;

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
