import { describe, expect, it } from 'vitest';
import { distanceToPolyline, distanceToSegment, simplify, type Point } from './rdp';

describe('distanceToSegment', () => {
  it('선분 위로 수직 투영되는 점은 수직 거리를 반환한다', () => {
    expect(distanceToSegment({ x: 5, y: 3 }, { x: 0, y: 0 }, { x: 10, y: 0 })).toBe(3);
  });

  it('선분 밖으로 투영되면 가까운 끝점까지의 거리를 반환한다', () => {
    expect(distanceToSegment({ x: -4, y: 0 }, { x: 0, y: 0 }, { x: 10, y: 0 })).toBe(4);
    expect(distanceToSegment({ x: 14, y: 0 }, { x: 0, y: 0 }, { x: 10, y: 0 })).toBe(4);
  });

  it('길이가 0인 선분은 점 대 점 거리로 축퇴한다', () => {
    expect(distanceToSegment({ x: 3, y: 4 }, { x: 0, y: 0 }, { x: 0, y: 0 })).toBe(5);
  });
});

describe('simplify', () => {
  it('점이 2개 이하면 그대로 둔다', () => {
    const points: Point[] = [{ x: 0, y: 0 }, { x: 1, y: 1 }];
    expect(simplify(points, 1)).toEqual(points);
  });

  it('직선 위의 중간점을 모두 제거한다', () => {
    const line: Point[] = Array.from({ length: 50 }, (_, i) => ({ x: i, y: 0 }));
    expect(simplify(line, 0.5)).toEqual([{ x: 0, y: 0 }, { x: 49, y: 0 }]);
  });

  it('epsilon을 넘는 꺾임은 보존한다', () => {
    const points: Point[] = [
      { x: 0, y: 0 },
      { x: 5, y: 4 },
      { x: 10, y: 0 },
    ];
    expect(simplify(points, 2)).toHaveLength(3);
    expect(simplify(points, 5)).toHaveLength(2);
  });

  it('시작점과 끝점은 항상 유지한다', () => {
    const points: Point[] = Array.from({ length: 200 }, (_, i) => ({
      x: i,
      y: Math.sin(i / 8) * 0.2,
    }));
    const result = simplify(points, 1);
    expect(result[0]).toEqual(points[0]);
    expect(result.at(-1)).toEqual(points.at(-1));
  });

  it('손그림 수준의 곡선을 1/10 이하로 줄인다', () => {
    // 실제 pointermove 샘플과 비슷하게 미세한 떨림이 섞인 곡선
    const raw: Point[] = Array.from({ length: 800 }, (_, i) => {
      const t = i / 800;
      return {
        x: t * 600 + Math.sin(i) * 0.4,
        y: Math.sin(t * Math.PI * 2) * 120 + Math.cos(i) * 0.4,
      };
    });
    const result = simplify(raw, 2);
    expect(result.length).toBeLessThanOrEqual(raw.length / 10);
    expect(result.length).toBeGreaterThan(2);
  });

  it('원본 배열을 변형하지 않는다', () => {
    const points: Point[] = [
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 2, y: 0 },
    ];
    simplify(points, 0.1);
    expect(points).toHaveLength(3);
  });
});

describe('distanceToPolyline', () => {
  const path: Point[] = [
    { x: 0, y: 0 },
    { x: 10, y: 0 },
    { x: 10, y: 10 },
  ];

  it('가장 가까운 선분까지의 거리를 반환한다', () => {
    expect(distanceToPolyline({ x: 12, y: 5 }, path)).toBe(2);
    expect(distanceToPolyline({ x: 5, y: -1 }, path)).toBe(1);
  });

  it('빈 경로는 Infinity를 반환한다', () => {
    expect(distanceToPolyline({ x: 0, y: 0 }, [])).toBe(Infinity);
  });

  it('점이 하나뿐이면 그 점까지의 거리를 반환한다', () => {
    expect(distanceToPolyline({ x: 3, y: 4 }, [{ x: 0, y: 0 }])).toBe(5);
  });
});
