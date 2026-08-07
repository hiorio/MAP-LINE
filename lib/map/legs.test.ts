import { describe, expect, it } from 'vitest';
import {
  ROUTE_TTL_DAYS,
  CAR_ROUTE_TTL_HOURS,
  drawableRoute,
  isRouteStale,
  legEndpoints,
  legsNeedingRoute,
  syncLegLength,
} from './legs';
import { stopAnchor, type Place, type RoutePath, type Stop, type StopLeg } from './types';

function place(id: string): Place {
  return { id, name: id, location: { lat: 37.5, lng: 127 }, pinColor: '#E24B4A' };
}

function route(fromPlaceId: string, toPlaceId: string, fetchedAt = new Date().toISOString()): RoutePath {
  return {
    points: [
      { lat: 37.5, lng: 127 },
      { lat: 37.51, lng: 127.01 },
    ],
    distanceM: 100,
    durationS: 60,
    fromPlaceId,
    toPlaceId,
    fetchedAt,
  };
}

const single = (id: string, placeId: string): Stop => ({ id, candidates: [place(placeId)] });

describe('stopAnchor', () => {
  it('후보가 하나면 지정 없이도 그것이 대표다', () => {
    expect(stopAnchor(single('s1', 'a'))?.id).toBe('a');
  });

  it('후보가 여럿인데 대표를 안 정했으면 기준이 없다', () => {
    // 중간지점은 가상의 점이라 길찾기 출발지가 될 수 없다.
    const stop: Stop = { id: 's1', candidates: [place('a'), place('b')] };
    expect(stopAnchor(stop)).toBeNull();
  });

  it('대표로 지정한 후보를 고른다', () => {
    const stop: Stop = { id: 's1', candidates: [place('a'), place('b')], primaryId: 'b' };
    expect(stopAnchor(stop)?.id).toBe('b');
  });

  it('대표 id가 후보에 없으면 기준이 없다', () => {
    const stop: Stop = { id: 's1', candidates: [place('a'), place('b')], primaryId: 'zzz' };
    expect(stopAnchor(stop)).toBeNull();
  });
});

describe('syncLegLength', () => {
  it('단계 수보다 하나 적게 맞춘다', () => {
    const stops = [single('s1', 'a'), single('s2', 'b'), single('s3', 'c')];
    expect(syncLegLength(stops, [])).toHaveLength(2);
  });

  it('단계가 하나 이하면 구간이 없다', () => {
    expect(syncLegLength([single('s1', 'a')], [{ mode: 'walk' }])).toEqual([]);
    expect(syncLegLength([], [])).toEqual([]);
  });

  it('남는 자리는 직선으로 채운다', () => {
    const stops = [single('s1', 'a'), single('s2', 'b'), single('s3', 'c')];
    expect(syncLegLength(stops, [{ mode: 'walk' }])).toEqual([{ mode: 'walk' }, { mode: 'straight' }]);
  });

  it('길이가 이미 맞으면 내용을 건드리지 않는다', () => {
    const stops = [single('s1', 'a'), single('s2', 'b')];
    const legs: StopLeg[] = [{ mode: 'transit' }];
    expect(syncLegLength(stops, legs)).toEqual(legs);
  });
});

describe('legEndpoints', () => {
  const stops = [single('s1', 'a'), single('s2', 'b')];

  it('앞뒤 단계의 대표를 돌려준다', () => {
    expect(legEndpoints(stops, 0)).toMatchObject({ from: { id: 'a' }, to: { id: 'b' } });
  });

  it('마지막 단계 뒤에는 구간이 없다', () => {
    expect(legEndpoints(stops, 1)).toBeNull();
  });

  it('한쪽이라도 대표가 없으면 기준이 없다', () => {
    const undecided: Stop = { id: 's2', candidates: [place('b'), place('c')] };
    expect(legEndpoints([stops[0]!, undecided], 0)).toBeNull();
  });
});

describe('drawableRoute', () => {
  const stops = [single('s1', 'a'), single('s2', 'b')];

  it('끝점이 맞으면 그린다', () => {
    expect(drawableRoute(stops, 0, { mode: 'walk', route: route('a', 'b') })).not.toBeNull();
  });

  it('끝점이 달라진 경로는 버린다', () => {
    // 단계를 재배치하거나 대표를 바꾸면 저장된 경로는 엉뚱한 두 지점의 것이 된다.
    expect(drawableRoute(stops, 0, { mode: 'walk', route: route('a', 'zzz') })).toBeNull();
  });

  it('직선 모드면 경로가 있어도 안 그린다', () => {
    expect(drawableRoute(stops, 0, { mode: 'straight', route: route('a', 'b') })).toBeNull();
  });

  it('낡았어도 그린다', () => {
    // 링크를 받은 사람 화면에서 선이 사라지는 것보다 낫다. 갱신은 편집기가 한다.
    const old = route('a', 'b', '2020-01-01T00:00:00.000Z');
    expect(drawableRoute(stops, 0, { mode: 'walk', route: old })).not.toBeNull();
  });

  it('구간이 없으면 null', () => {
    expect(drawableRoute(stops, 0, undefined)).toBeNull();
  });
});

describe('isRouteStale', () => {
  const now = Date.parse('2026-08-10T00:00:00.000Z');

  it('기한 안이면 신선하다', () => {
    expect(isRouteStale(route('a', 'b', '2026-08-09T00:00:00.000Z'), now)).toBe(false);
  });

  it('기한을 넘기면 낡았다', () => {
    const old = new Date(now - (ROUTE_TTL_DAYS + 1) * 86_400_000).toISOString();
    expect(isRouteStale(route('a', 'b', old), now)).toBe(true);
  });

  it('시각을 못 읽으면 낡은 것으로 본다', () => {
    expect(isRouteStale(route('a', 'b', 'nope'), now)).toBe(true);
  });

  it('현재 교통을 반영하는 자동차 경로는 한 시간 뒤 갱신한다', () => {
    const old = new Date(now - (CAR_ROUTE_TTL_HOURS + 0.5) * 3_600_000).toISOString();
    expect(isRouteStale(route('a', 'b', old), now, 'car')).toBe(true);
    expect(isRouteStale(route('a', 'b', old), now, 'walk')).toBe(false);
  });
});

describe('legsNeedingRoute', () => {
  const stops = [single('s1', 'a'), single('s2', 'b'), single('s3', 'c')];

  it('모드는 정했는데 경로가 없는 자리를 고른다', () => {
    expect(legsNeedingRoute(stops, [{ mode: 'walk' }, { mode: 'straight' }])).toEqual([0]);
  });

  it('직선 구간은 부르지 않는다', () => {
    expect(legsNeedingRoute(stops, [{ mode: 'straight' }, { mode: 'straight' }])).toEqual([]);
  });

  it('쓸 수 있는 경로가 있으면 부르지 않는다', () => {
    expect(legsNeedingRoute(stops, [{ mode: 'walk', route: route('a', 'b') }, { mode: 'straight' }])).toEqual([]);
  });

  it('낡은 경로는 다시 받는다', () => {
    const old = route('a', 'b', '2020-01-01T00:00:00.000Z');
    expect(legsNeedingRoute(stops, [{ mode: 'walk', route: old }, { mode: 'straight' }])).toEqual([0]);
  });

  it('대표를 안 정한 단계가 끼면 기다린다', () => {
    // 부를 기준이 없다. 쿼터만 태우고 실패한다.
    const undecided: Stop = { id: 's2', candidates: [place('b'), place('x')] };
    expect(legsNeedingRoute([stops[0]!, undecided], [{ mode: 'walk' }])).toEqual([]);
  });
});
