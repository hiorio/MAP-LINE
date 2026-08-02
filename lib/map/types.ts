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

export type TravelMode = 'walk' | 'car' | 'transit';

export const TRAVEL_MODES: { id: TravelMode; label: string }[] = [
  { id: 'walk', label: '도보' },
  { id: 'car', label: '자동차' },
  { id: 'transit', label: '대중교통' },
];

/** 검색 결과. 아직 지도에 담기지 않은 후보다. */
export interface PlaceCandidate {
  kakaoPlaceId: string;
  name: string;
  address?: string;
  roadAddress?: string;
  category?: string;
  location: LatLng;
}

export interface Place {
  id: string;
  name: string;
  address?: string;
  /**
   * 재조회용 식별자. 설계안 §10에 따라 영구 저장 대상은 이 값과 사용자가 입력한 메모뿐이고
   * 상호명·좌표는 캐시로 취급한다. 지도 롱프레스로 찍은 임의 지점에는 없다.
   */
  kakaoPlaceId?: string;
  location: LatLng;
  memo?: string;
  pinColor: string;
  /** 다음 순번의 핀까지 어떻게 이동하는지. 연결선 스타일을 결정한다. */
  modeToNext: TravelMode;
}

export interface MapDocument {
  title: string;
  center: LatLng;
  zoomLevel: number;
  places: Place[];
  strokes: Stroke[];
  labels: MapLabel[];
}

export const PIN_COLOR = '#E24B4A';

export const STROKE_COLORS = ['#E24B4A', '#2D6BE4', '#2FA35B', '#2C2C2A'] as const;
export const STROKE_WIDTHS = [4, 9] as const;
export const LABEL_COLOR = '#2C2C2A';
export const DEFAULT_FONT_SIZE = 14;

/** 강남역. 위치 권한 없이 첫 화면을 채우기 위한 기본값 */
export const DEFAULT_CENTER: LatLng = { lat: 37.4979, lng: 127.0276 };
export const DEFAULT_LEVEL = 3;
