import { describe, expect, it } from 'vitest';
import {
  createStaticProjection,
  pxPerDegreeLat,
  pxPerDegreeLng,
  PX_PER_DEG_LAT_AT_LEVEL_1,
} from './staticProjection';

const SEOUL = { lat: 37.5, lng: 127.0 };

describe('pxPerDegreeLat', () => {
  it('레벨이 1 오를 때마다 정확히 절반이 된다', () => {
    expect(pxPerDegreeLat(1)).toBe(PX_PER_DEG_LAT_AT_LEVEL_1);
    expect(pxPerDegreeLat(2)).toBe(PX_PER_DEG_LAT_AT_LEVEL_1 / 2);
    expect(pxPerDegreeLat(4)).toBe(PX_PER_DEG_LAT_AT_LEVEL_1 / 8);
  });
});

describe('pxPerDegreeLng', () => {
  it('경도 척도는 위도의 cos배다', () => {
    // 실측 결과 위도 축은 위도와 무관하게 일정하고, 경도 축만 cos로 좁아졌다.
    expect(pxPerDegreeLng(3, 37.5)).toBeCloseTo(pxPerDegreeLat(3) * Math.cos((37.5 * Math.PI) / 180), 6);
  });

  it('적도에서는 두 축의 척도가 같다', () => {
    expect(pxPerDegreeLng(3, 0)).toBeCloseTo(pxPerDegreeLat(3), 6);
  });

  it('위도가 높을수록 경도 1도가 좁아진다', () => {
    expect(pxPerDegreeLng(3, 38.5)).toBeLessThan(pxPerDegreeLng(3, 33.5));
  });
});

describe('createStaticProjection', () => {
  const project = createStaticProjection({ center: SEOUL, level: 3, width: 800, height: 420 });

  it('중심 좌표는 이미지 한가운데에 온다', () => {
    expect(project(SEOUL)).toEqual({ x: 400, y: 210 });
  });

  it('북쪽으로 갈수록 y가 작아진다', () => {
    // 화면 좌표는 아래로 갈수록 커지므로 위도와 방향이 반대다.
    expect(project({ ...SEOUL, lat: SEOUL.lat + 0.001 }).y).toBeLessThan(210);
    expect(project({ ...SEOUL, lat: SEOUL.lat - 0.001 }).y).toBeGreaterThan(210);
  });

  it('동쪽으로 갈수록 x가 커진다', () => {
    expect(project({ ...SEOUL, lng: SEOUL.lng + 0.001 }).x).toBeGreaterThan(400);
  });

  it('실측한 척도대로 픽셀을 계산한다', () => {
    // 정적 지도에서 center를 이만큼 옮겼을 때 이미지가 실제로 240px(=이미지 픽셀,
    // scale 2배) 밀리는 것을 확인한 값이다. CSS 픽셀로는 120px이다.
    const dLat = 120 / pxPerDegreeLat(3);
    expect(project({ ...SEOUL, lat: SEOUL.lat + dLat }).y).toBeCloseTo(210 - 120, 6);

    const dLng = 120 / pxPerDegreeLng(3, SEOUL.lat);
    expect(project({ ...SEOUL, lng: SEOUL.lng + dLng }).x).toBeCloseTo(400 + 120, 6);
  });

  it('레벨을 한 단계 올리면 같은 좌표가 중심에 절반만큼 가까워진다', () => {
    const zoomedOut = createStaticProjection({ center: SEOUL, level: 4, width: 800, height: 420 });
    const far = { lat: SEOUL.lat + 0.01, lng: SEOUL.lng + 0.01 };
    expect(zoomedOut(far).x - 400).toBeCloseTo((project(far).x - 400) / 2, 6);
    expect(zoomedOut(far).y - 210).toBeCloseTo((project(far).y - 210) / 2, 6);
  });
});
