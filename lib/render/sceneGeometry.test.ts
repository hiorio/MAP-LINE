import { describe, expect, it } from 'vitest';
import type { Point } from '@/lib/geo/rdp';
import type { LatLng, Place, RoutePath, Stop, StopLeg } from '@/lib/map/types';
import { legShapes, routeAnnotations } from './sceneGeometry';

/** 위경도를 그대로 픽셀로 읽는 투영. 기대값을 눈으로 따라갈 수 있다. */
const project = ({ lat, lng }: LatLng): Point => ({ x: lng, y: lat });

function place(id: string, lat: number, lng: number): Place {
  return { id, name: id, location: { lat, lng }, pinColor: '#E24B4A' };
}

function stop(id: string, p: Place): Stop {
  return { id, candidates: [p] };
}

function route(points: LatLng[], fromPlaceId: string, toPlaceId: string): RoutePath {
  return {
    points,
    distanceM: 100,
    durationS: 100,
    fromPlaceId,
    toPlaceId,
    fetchedAt: new Date().toISOString(),
  };
}

describe('legShapes', () => {
  it('실제 경로가 있으면 궤적을 그린다', () => {
    const a = place('a', 0, 0);
    const b = place('b', 0, 400);
    const legs: StopLeg[] = [
      { mode: 'walk', route: route([{ lat: 0, lng: 0 }, { lat: 10, lng: 200 }, { lat: 0, lng: 400 }], 'a', 'b') },
    ];

    const [shape] = legShapes([stop('s1', a), stop('s2', b)], legs, project);
    expect(shape?.kind).toBe('path');
    expect(shape?.kind === 'path' && shape.segments).toEqual([
      [
        { x: 0, y: 0 },
        { x: 200, y: 10 },
        { x: 400, y: 0 },
      ],
    ]);
  });

  it('경로가 핀에서 멀리 떨어져 시작·끝나면 접근선을 잇는다', () => {
    // 카카오 대중교통 응답은 탈것 구간의 좌표만 준다. 역까지의 도보는 좌표가 없어
    // 그대로 두면 선이 핀 어디에도 닿지 않고 허공에 뜬다.
    const a = place('a', 0, 0);
    const b = place('b', 0, 1000);
    const legs: StopLeg[] = [
      // 지하철 구간만: 출발지에서 300px 떨어진 곳에서 시작해 도착지 200px 앞에서 끝난다.
      { mode: 'transit', route: route([{ lat: 0, lng: 300 }, { lat: 0, lng: 800 }], 'a', 'b') },
    ];

    const [shape] = legShapes([stop('s1', a), stop('s2', b)], legs, project);
    expect(shape?.kind).toBe('path');
    if (shape?.kind !== 'path') return;

    expect(shape.connectors).toHaveLength(2);
    // 출발 핀에서 나와 경로 첫 점으로 들어간다.
    expect(shape.connectors[0]!.to).toEqual({ x: 300, y: 0 });
    // 경로 마지막 점에서 나와 도착 핀 쪽으로 간다.
    expect(shape.connectors[1]!.from).toEqual({ x: 800, y: 0 });
    // 핀 밑에서 선이 시작·끝나지 않도록 물려 놓는다.
    expect(shape.connectors[0]!.from.x).toBeGreaterThan(0);
    expect(shape.connectors[1]!.to.x).toBeLessThan(1000);
  });

  it('접근선이 붙으면 화살촉도 그 끝으로 간다', () => {
    // 화살촉이 언주역에 남아 있으면 지하철이 목적지인 것처럼 보인다.
    const a = place('a', 0, 0);
    const b = place('b', 0, 1000);
    const legs: StopLeg[] = [
      { mode: 'transit', route: route([{ lat: 0, lng: 300 }, { lat: 0, lng: 800 }], 'a', 'b') },
    ];

    const [shape] = legShapes([stop('s1', a), stop('s2', b)], legs, project);
    if (shape?.kind !== 'path') throw new Error('path여야 한다');

    expect(shape.end.x).toBeGreaterThan(800);
    expect(shape.ux).toBeCloseTo(1, 5);
  });

  it('경로가 핀에 붙어 있으면 접근선을 만들지 않는다', () => {
    // 도보는 출발지에서 십수 미터 안에서 시작한다. 접근선을 그리면 군더더기다.
    const a = place('a', 0, 0);
    const b = place('b', 0, 400);
    const legs: StopLeg[] = [
      { mode: 'walk', route: route([{ lat: 0, lng: 2 }, { lat: 0, lng: 398 }], 'a', 'b') },
    ];

    const [shape] = legShapes([stop('s1', a), stop('s2', b)], legs, project);
    expect(shape?.kind === 'path' && shape.connectors).toEqual([]);
  });

  it('경로가 없으면 중간지점을 잇는 직선으로 되돌아간다', () => {
    const a = place('a', 0, 0);
    const b = place('b', 0, 400);
    const [shape] = legShapes([stop('s1', a), stop('s2', b)], [{ mode: 'walk' }], project);
    expect(shape?.kind).toBe('arrow');
    expect(shape?.mode).toBe('straight');
  });

  it('환승이 있으면 탈것 구간을 나누고 사이를 도보로 잇는다', () => {
    // 지하철 → 걸어서 환승 → 버스. 가운데 도보는 좌표가 오지 않는다.
    const a = place('a', 0, 0);
    const b = place('b', 0, 1000);
    const path = route(
      [
        { lat: 0, lng: 100 }, { lat: 0, lng: 300 },
        { lat: 0, lng: 500 }, { lat: 0, lng: 900 },
      ],
      'a',
      'b',
    );
    path.legs = [
      { type: 'SUBWAY', guidance: '9호선', pointCount: 2 },
      { type: 'BUS', guidance: '간선 143', pointCount: 2 },
    ];

    const [shape] = legShapes([stop('s1', a), stop('s2', b)], [{ mode: 'transit', route: path }], project);
    if (shape?.kind !== 'path') throw new Error('path여야 한다');

    expect(shape.segments).toHaveLength(2);
    expect(shape.segments[0]).toEqual([{ x: 100, y: 0 }, { x: 300, y: 0 }]);
    expect(shape.segments[1]).toEqual([{ x: 500, y: 0 }, { x: 900, y: 0 }]);
    // 환승 도보 + 출발지 접근 + 도착지 접근
    expect(shape.connectors).toContainEqual({ from: { x: 300, y: 0 }, to: { x: 500, y: 0 } });
    expect(shape.connectors).toHaveLength(3);
  });

  it('구간 정보가 없는 예전 경로는 한 줄로 둔다', () => {
    // 잘못 자르느니 이어진 채로 두는 편이 낫다.
    const a = place('a', 0, 0);
    const b = place('b', 0, 400);
    const path = route([{ lat: 0, lng: 2 }, { lat: 0, lng: 200 }, { lat: 0, lng: 398 }], 'a', 'b');
    path.legs = [{ type: 'SUBWAY', guidance: '9호선' }];

    const [shape] = legShapes([stop('s1', a), stop('s2', b)], [{ mode: 'transit', route: path }], project);
    expect(shape?.kind === 'path' && shape.segments).toHaveLength(1);
  });

  it('구간 모양은 단계 사이 자리와 어긋나지 않는다', () => {
    // 그릴 수 없는 구간을 걸러 내면 뒤 구간의 모드가 앞으로 밀린다.
    const a = place('a', 0, 0);
    const b = place('b', 0, 3);
    const c = place('c', 0, 900);
    const legs: StopLeg[] = [
      { mode: 'walk' },
      { mode: 'transit', route: route([{ lat: 0, lng: 100 }, { lat: 0, lng: 800 }], 'b', 'c') },
    ];

    const shapes = legShapes([stop('s1', a), stop('s2', b), stop('s3', c)], legs, project);
    // 1→2는 너무 가까워 화살표를 못 그린다. 그래도 2→3은 제 모드로 남아야 한다.
    expect(shapes.some((s) => s.kind === 'path' && s.mode === 'transit')).toBe(true);
  });

  it('실제 경로의 길이 중간에 이동수단·거리·시간을 놓는다', () => {
    const a = place('a', 0, 0);
    const b = place('b', 0, 1000);
    const path = route(
      [{ lat: 0, lng: 0 }, { lat: 0, lng: 900 }, { lat: 0, lng: 1000 }],
      'a',
      'b',
    );
    path.distanceM = 1200;
    path.durationS = 16 * 60;

    const [annotation] = routeAnnotations(
      [stop('s1', a), stop('s2', b)],
      [{ mode: 'walk', route: path }],
      project,
    );

    expect(annotation?.at).toEqual({ x: 500, y: 0 });
    expect(annotation?.text).toBe('도보 · 1.2km · 16분');
  });

  it('실제 경로가 없거나 끝점이 바뀐 구간에는 시간 라벨을 만들지 않는다', () => {
    const a = place('a', 0, 0);
    const b = place('b', 0, 1000);
    const stops = [stop('s1', a), stop('s2', b)];

    expect(routeAnnotations(stops, [{ mode: 'walk' }], project)).toEqual([]);
    expect(
      routeAnnotations(
        stops,
        [{ mode: 'walk', route: route([{ lat: 0, lng: 0 }, { lat: 0, lng: 1000 }], 'a', 'old-b') }],
        project,
      ),
    ).toEqual([]);
  });
});
