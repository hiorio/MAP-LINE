import { stopAnchor, type Place, type RoutePath, type Stop, type StopLeg } from './types';

/**
 * 단계 사이 구간을 다루는 순수 함수들.
 *
 * 구간은 `legs[i] = stops[i] → stops[i+1]`로 자리에 묶여 있다. 단계를 더하거나 빼거나
 * 재배치하면 자리의 의미가 달라지므로, 저장된 경로를 그대로 믿으면 조용히 틀린 그림이
 * 된다. "이 경로가 지금 이 두 지점의 것이 맞는가"를 그릴 때마다 다시 따진다.
 */

/**
 * 경로를 다시 받아야 하는 기간.
 *
 * 카카오 개발자 운영정책 제5조 20호는 캐시 자체를 막지 않지만 최신 상태로 유지할 것을
 * 요구한다. 길이 크게 바뀌는 일은 드물어도 대중교통 노선은 개편된다.
 */
export const ROUTE_TTL_DAYS = 7;

/** 구간 배열을 단계 수에 맞춘다. 길이는 항상 max(0, stops - 1)이다. */
export function syncLegLength(stops: readonly Stop[], legs: readonly StopLeg[]): StopLeg[] {
  const wanted = Math.max(0, stops.length - 1);
  if (legs.length === wanted) return [...legs];

  const next: StopLeg[] = [];
  for (let i = 0; i < wanted; i++) next.push(legs[i] ?? { mode: 'straight' });
  return next;
}

/** 이 구간의 출발·도착 장소. 어느 한쪽이라도 대표가 없으면 경로를 그릴 수 없다. */
export function legEndpoints(
  stops: readonly Stop[],
  index: number,
): { from: Place; to: Place } | null {
  const fromStop = stops[index];
  const toStop = stops[index + 1];
  if (!fromStop || !toStop) return null;

  const from = stopAnchor(fromStop);
  const to = stopAnchor(toStop);
  if (!from || !to) return null;
  return { from, to };
}

/** 저장된 경로가 지금 이 두 지점의 것인가. */
export function matchesEndpoints(route: RoutePath, from: Place, to: Place): boolean {
  return route.fromPlaceId === from.id && route.toPlaceId === to.id;
}

export function isRouteStale(route: RoutePath, now: number = Date.now()): boolean {
  const fetched = new Date(route.fetchedAt).getTime();
  // 시각을 못 읽으면 낡은 것으로 본다. 다시 받는 편이 틀린 그림을 두는 것보다 낫다.
  if (!Number.isFinite(fetched)) return true;
  return now - fetched > ROUTE_TTL_DAYS * 24 * 60 * 60 * 1000;
}

/**
 * 지금 그려도 되는 경로. 없으면 직선으로 되돌린다는 뜻이다.
 *
 * 낡았는지는 보지 않는다. 낡은 경로라도 직선보다는 사실에 가깝고, 갱신은 편집기가
 * 따로 한다. 여기서 버리면 링크를 받은 사람 화면에서 선이 사라진다.
 */
export function drawableRoute(
  stops: readonly Stop[],
  index: number,
  leg: StopLeg | undefined,
): RoutePath | null {
  if (!leg || leg.mode === 'straight' || !leg.route) return null;

  const ends = legEndpoints(stops, index);
  if (!ends) return null;
  return matchesEndpoints(leg.route, ends.from, ends.to) ? leg.route : null;
}

/** 편집기가 다시 받아야 하는 구간들. 모드는 정해졌는데 쓸 만한 경로가 없는 자리다. */
export function legsNeedingRoute(
  stops: readonly Stop[],
  legs: readonly StopLeg[],
  now: number = Date.now(),
): number[] {
  const indexes: number[] = [];

  for (let i = 0; i < legs.length; i++) {
    const leg = legs[i];
    if (!leg || leg.mode === 'straight') continue;
    // 대표가 없으면 받아 올 기준이 없다. 사람이 정할 때까지 기다린다.
    if (!legEndpoints(stops, i)) continue;

    const usable = drawableRoute(stops, i, leg);
    if (!usable || isRouteStale(usable, now)) indexes.push(i);
  }
  return indexes;
}
