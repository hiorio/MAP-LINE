import type { LatLng } from '@/lib/geo/projection';
import type { Point } from '@/lib/geo/rdp';

/**
 * 카카오 지도의 좌표 → 픽셀 변환.
 *
 * 카카오는 이 대응을 문서로 내놓지 않아 직접 쟀다. 동적 지도의
 * `getProjection().containerPointFromCoords()`로 레벨별·위도별 척도를 뽑고,
 * 정적 지도에서 `center`를 알려진 각도만큼 옮겼을 때 이미지가 실제로 몇 픽셀
 * 밀리는지 대조해 검증했다. 위도 37.5와 35.16, 레벨 1·2·3·5·7에서 240px 이동
 * 기준 오차 0px, 레벨 9에서만 2px이었다(레벨 9는 1px이 64m라 반올림 수준이다).
 *
 * 척도의 성질:
 * - 위도 1도당 픽셀 수는 **위도와 무관하게 일정**하다. 메르카토르가 아니다.
 * - 경도 1도당 픽셀 수는 그 위도의 cos배다.
 * 즉 두 축의 미터/픽셀이 같은 등거리 투영이고, 레벨이 1 오를 때마다 정확히 절반이 된다.
 */
export const PX_PER_DEG_LAT_AT_LEVEL_1 = 443960;

/** 해당 레벨에서 위도 1도가 차지하는 CSS 픽셀 수. */
export function pxPerDegreeLat(level: number): number {
  return PX_PER_DEG_LAT_AT_LEVEL_1 / 2 ** (level - 1);
}

/** 해당 레벨·위도에서 경도 1도가 차지하는 CSS 픽셀 수. */
export function pxPerDegreeLng(level: number, lat: number): number {
  return pxPerDegreeLat(level) * Math.cos((lat * Math.PI) / 180);
}

export interface StaticProjectionOptions {
  center: LatLng;
  level: number;
  /** CSS 픽셀 기준 크기. 중심이 이 사각형의 한가운데에 온다. */
  width: number;
  height: number;
}

/**
 * 중심과 레벨이 주어진 지도 이미지에서 좌표가 놓일 CSS 픽셀 위치.
 *
 * 썸네일이 다루는 범위는 넓어야 동네 하나라 중심 위도의 척도를 그대로 쓴다.
 * 이 범위에서 경도 척도의 위도 의존은 픽셀 이하로 묻힌다.
 */
export function createStaticProjection({
  center,
  level,
  width,
  height,
}: StaticProjectionOptions): (coord: LatLng) => Point {
  const perLat = pxPerDegreeLat(level);
  const perLng = pxPerDegreeLng(level, center.lat);
  const originX = width / 2;
  const originY = height / 2;

  return ({ lat, lng }) => ({
    x: originX + (lng - center.lng) * perLng,
    // 위도는 북쪽이 클수록 화면에서는 위쪽, 즉 y가 작아진다.
    y: originY - (lat - center.lat) * perLat,
  });
}
