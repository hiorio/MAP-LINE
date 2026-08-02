import type { LatLng } from '@/lib/map/types';
import { MissingRestKeyError } from './localSearch';
import { recordKakaoCall } from './usage';

/**
 * 카카오 정적 지도. **서버에서만** 호출한다.
 *
 * 알려진 한계: 이 API에는 경로/폴리라인 파라미터가 없다. 마커만 최대 5개까지다.
 * 그래서 손그림은 썸네일에 들어가지 않는다. 넣으려면 받은 이미지 위에 직접 합성해야
 * 하는데, 카카오의 레벨 → 미터/픽셀 대응을 정확히 알아야 획이 엉뚱한 데 찍히지 않는다.
 * 틀린 위치에 그리느니 지도와 핀만 보여주는 편이 낫다고 판단했다.
 */
const STATIC_MAP_ENDPOINT = 'https://dapi.kakao.com/v2/maps/staticmap';

/** 카카오가 허용하는 마커 최대 개수 */
const MAX_MARKERS = 5;

/** OG 이미지 권장 비율(1.91:1)에 맞춘 기본 크기. scale=2라 실제로는 2배로 나온다. */
export const OG_WIDTH = 800;
export const OG_HEIGHT = 420;

export interface StaticMapOptions {
  center: LatLng;
  level: number;
  markers?: readonly LatLng[];
}

export function buildStaticMapUrl({ center, level, markers = [] }: StaticMapOptions): string {
  const url = new URL(STATIC_MAP_ENDPOINT);
  url.searchParams.set('size', `${OG_WIDTH}x${OG_HEIGHT}`);
  // 좌표는 X,Y = 경도,위도 순서다. Local API와 같은 함정이 여기에도 있다.
  url.searchParams.set('center', `${center.lng},${center.lat}`);
  url.searchParams.set('lv', String(clampLevel(level)));
  url.searchParams.set('scale', '2');
  url.searchParams.set('format', 'png');

  for (const marker of markers.slice(0, MAX_MARKERS)) {
    url.searchParams.append('markers', `location:${marker.lng},${marker.lat}`);
  }
  return url.toString();
}

export async function fetchStaticMap(options: StaticMapOptions): Promise<ArrayBuffer> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  recordKakaoCall('staticmap');
  const response = await fetch(buildStaticMapUrl(options), {
    headers: { Authorization: `KakaoAK ${key}` },
  });

  if (!response.ok) {
    throw new Error(`정적 지도 생성 실패 (${response.status})`);
  }
  return response.arrayBuffer();
}

/** 정적 지도는 1~15, 우리 저장값은 1~14라 범위는 겹치지만 방어한다. */
function clampLevel(level: number): number {
  if (!Number.isFinite(level)) return 3;
  return Math.min(15, Math.max(1, Math.round(level)));
}
