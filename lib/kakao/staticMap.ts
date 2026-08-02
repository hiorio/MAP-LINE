import type { LatLng } from '@/lib/map/types';
import { MissingRestKeyError } from './localSearch';
import { recordKakaoCall } from './usage';

/**
 * 카카오 정적 지도. **서버에서만** 호출한다.
 *
 * 마커 파라미터는 일부러 쓰지 않는다. `markers`를 넘기면 카카오가 **`center`를 무시하고
 * 마커들에 맞춰 지도를 다시 잡는다**. 실제로 확인해 보니 마커 하나를 넘기면 그 마커가
 * 무조건 이미지 한가운데에 놓였다. 지도를 만든 사람이 맞춰 둔 화면이 통째로 어긋나는
 * 셈이고, 마커 5개 제한과 번호 없는 기본 핀 모양도 편집기와 맞지 않는다.
 *
 * 그래서 여기서는 표시 없는 순수한 지도만 받고, 핀·화살표·손그림·메모는
 * `lib/render/ogOverlay.ts`가 그린 SVG를 얹어 합성한다. 좌표 → 픽셀 대응은
 * `lib/map/staticProjection.ts`에 실측해 둔 값을 쓴다.
 */
const STATIC_MAP_ENDPOINT = 'https://dapi.kakao.com/v2/maps/staticmap';

/** OG 이미지 권장 비율(1.91:1)에 맞춘 기본 크기. CSS 픽셀 기준이다. */
export const OG_WIDTH = 800;
export const OG_HEIGHT = 420;

/** 고해상도 화면에서 흐릿하지 않도록 2배로 받는다. 실제 이미지는 1600x840이다. */
export const OG_SCALE = 2;

export interface StaticMapOptions {
  center: LatLng;
  level: number;
}

export function buildStaticMapUrl({ center, level }: StaticMapOptions): string {
  const url = new URL(STATIC_MAP_ENDPOINT);
  url.searchParams.set('size', `${OG_WIDTH}x${OG_HEIGHT}`);
  // 좌표는 X,Y = 경도,위도 순서다. Local API와 같은 함정이 여기에도 있다.
  url.searchParams.set('center', `${center.lng},${center.lat}`);
  url.searchParams.set('lv', String(clampLevel(level)));
  url.searchParams.set('scale', String(OG_SCALE));
  url.searchParams.set('format', 'png');
  return url.toString();
}

export async function fetchStaticMap(options: StaticMapOptions): Promise<ArrayBuffer> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  // 집계 때문에 썸네일 생성이 느려지거나 막히면 안 된다. 기다리지 않는다.
  void recordKakaoCall('staticmap');
  const response = await fetch(buildStaticMapUrl(options), {
    headers: { Authorization: `KakaoAK ${key}` },
  });

  if (!response.ok) {
    throw new Error(`정적 지도 생성 실패 (${response.status})`);
  }
  return response.arrayBuffer();
}

/**
 * 정적 지도는 1~15, 우리 저장값은 1~14라 범위는 겹치지만 방어한다.
 *
 * 오버레이를 얹는 쪽도 **반드시 이 값을 써야 한다**. 요청한 레벨과 그린 레벨이
 * 어긋나면 획이 통째로 엉뚱한 배율로 찍힌다.
 */
export function clampLevel(level: number): number {
  if (!Number.isFinite(level)) return 3;
  return Math.min(15, Math.max(1, Math.round(level)));
}
