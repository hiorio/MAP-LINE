export interface Point {
  x: number;
  y: number;
}

/**
 * 점 p에서 선분 ab까지의 최단 거리.
 * a와 b가 같은 점이면 점 대 점 거리로 축퇴한다.
 */
export function distanceToSegment(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  if (dx === 0 && dy === 0) return Math.hypot(p.x - a.x, p.y - a.y);

  const t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy), 0, 1);
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

/**
 * Ramer-Douglas-Peucker 단순화. 반복(스택) 구현이라 긴 획에서도 스택이 넘치지 않는다.
 *
 * 이 프로젝트는 위경도가 아니라 **화면 좌표**에서 단순화한다.
 * 고정 줌에서 화면↔위경도 변환은 국소적으로 선형이므로 결과는 "줌에 비례하는
 * epsilon을 쓴 위경도 RDP"와 사실상 같고, 오차 단위가 픽셀이라 지각적으로도 맞다.
 * 대신 획마다 그린 시점의 줌 레벨(zoomCreated)을 함께 저장한다.
 *
 * 단순화하지 않으면 곡선 하나에 좌표가 수백 개 쌓인다. 목표는 1/10 이하.
 */
export function simplify<T extends Point>(points: readonly T[], epsilon: number): T[] {
  if (points.length < 3 || epsilon <= 0) return points.slice();

  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;

  const stack: [number, number][] = [[0, points.length - 1]];
  while (stack.length > 0) {
    const [first, last] = stack.pop()!;
    const a = points[first]!;
    const b = points[last]!;

    let maxDistance = -1;
    let index = -1;
    for (let i = first + 1; i < last; i++) {
      const distance = distanceToSegment(points[i]!, a, b);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }

    if (maxDistance > epsilon && index > 0) {
      keep[index] = 1;
      stack.push([first, index], [index, last]);
    }
  }

  return points.filter((_, i) => keep[i] === 1);
}

/** 점에서 폴리라인까지의 최단 거리. 지우개 히트 테스트에 쓴다. */
export function distanceToPolyline(p: Point, points: readonly Point[]): number {
  if (points.length === 0) return Infinity;
  if (points.length === 1) return Math.hypot(p.x - points[0]!.x, p.y - points[0]!.y);

  let min = Infinity;
  for (let i = 1; i < points.length; i++) {
    const d = distanceToSegment(p, points[i - 1]!, points[i]!);
    if (d < min) min = d;
  }
  return min;
}

function clamp(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}
