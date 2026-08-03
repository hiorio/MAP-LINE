import type { LatLng } from '@/lib/geo/projection';

/**
 * 중간지점 계산의 순수 부분.
 *
 * 외부 호출이 전혀 없다. 어디를 후보로 볼지 좁히고, 받아 온 소요 시간으로 순위를
 * 매기는 규칙만 담는다. 카카오를 부르는 일은 `findMidpoint.ts`가 한다.
 */

const EARTH_RADIUS_M = 6_371_000;

/** 두 지점 사이 직선거리(m). 후보를 싸게 걸러내는 데 쓴다. */
export function distanceM(a: LatLng, b: LatLng): number {
  const toRad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * toRad;
  const dLng = (b.lng - a.lng) * toRad;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * toRad) * Math.cos(b.lat * toRad) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h)));
}

/**
 * 참가자들의 기하 중심.
 *
 * 이건 답이 아니라 **어디를 뒤질지 정하는 출발점**이다. 평균 좌표는 강 한복판이나
 * 역이 없는 곳일 수 있어 그 자체로는 모일 곳이 못 된다. 이 주변의 실제 장소를 찾아
 * 진짜 소요 시간으로 다시 줄을 세운다.
 *
 * 한 도시 안에 흩어진 사람들이므로 구면 보정 없이 산술평균으로 충분하다.
 */
export function centroidOf(points: readonly LatLng[]): LatLng | null {
  if (points.length === 0) return null;
  const sum = points.reduce(
    (acc, p) => ({ lat: acc.lat + p.lat, lng: acc.lng + p.lng }),
    { lat: 0, lng: 0 },
  );
  return { lat: sum.lat / points.length, lng: sum.lng / points.length };
}

/**
 * 후보지를 찾을 반경(m).
 *
 * 사람들이 흩어진 정도에 맞춘다. 다 같은 동네면 좁게, 도시 반대편이면 넓게 본다.
 * 고정값을 쓰면 한쪽에서는 아무것도 안 잡히고 다른 쪽에서는 엉뚱한 게 섞인다.
 * 카카오 카테고리 검색의 상한이 20km라 그 아래로 가둔다.
 */
export function searchRadiusM(center: LatLng, points: readonly LatLng[]): number {
  const farthest = points.reduce((max, p) => Math.max(max, distanceM(center, p)), 0);
  return Math.min(20_000, Math.max(1_000, Math.round(farthest * 0.6)));
}

/**
 * 카카오는 환승역을 노선마다 따로 준다. "이촌역 경의중앙선"과 "이촌역 4호선"이
 * 별개 항목으로 온다. 사람 입장에서는 같은 곳이다.
 *
 * 그대로 두면 세 자리를 같은 역이 다 차지해 고를 것이 없어지고, 실제 경로 호출도
 * 같은 자리에 세 번 나간다. 환승역일수록 모이기 좋은 곳이라 이 일이 자주 생긴다.
 */
export function stationBaseName(name: string): string {
  // 끝에 붙은 노선 이름을 떼어 낸다. "…경의중앙선", "…2호선", "…신분당선" 모두 선으로 끝난다.
  return name.replace(/\s+\S*선$/, '').trim() || name;
}

/** 같은 역은 하나만 남긴다. 목록이 거리순이므로 가장 가까운 입구가 남는다. */
export function dedupeStations<T extends { name: string }>(places: readonly T[]): T[] {
  const seen = new Set<string>();
  return places.filter((place) => {
    const base = stationBaseName(place.name);
    if (seen.has(base)) return false;
    seen.add(base);
    return true;
  });
}

export interface Participant {
  id: string;
  name?: string;
  location: LatLng;
  /** 이 사람이 오는 방법. 사람마다 다를 수 있다. */
  mode: 'walk' | 'transit' | 'bicycle';
}

/**
 * 실제 경로를 물어볼 결선 후보를 고른다.
 *
 * 길찾기는 하루 1,000건이고 한 번 계산에 `참가자 수 × 후보 수`만큼 나간다. 후보를
 * 그대로 다 부르면 몇 번 만에 바닥난다. 직선거리로 미리 줄을 세워 앞의 몇 개만 남긴다.
 *
 * 직선거리로도 순서가 크게 틀리지 않는다. 실제 경로는 길을 따라 돌아갈 뿐 방향이
 * 뒤집히지는 않기 때문이다. 다만 최종 판단은 반드시 실제 시간으로 한다.
 */
export function shortlist<T extends { location: LatLng }>(
  candidates: readonly T[],
  participants: readonly Participant[],
  limit: number,
): T[] {
  return [...candidates]
    .map((candidate) => ({
      candidate,
      // 가장 멀리서 오는 사람을 기준으로 본다. 합이 아니라 최댓값이어야
      // 한 사람만 유난히 멀리 오는 자리를 미리 걸러 낸다.
      worst: participants.reduce(
        (max, person) => Math.max(max, distanceM(candidate.location, person.location)),
        0,
      ),
    }))
    .sort((a, b) => a.worst - b.worst)
    .slice(0, limit)
    .map((entry) => entry.candidate);
}

export interface Leg {
  participantId: string;
  mode: Participant['mode'];
  /** 길찾기가 실패하면 없다. 그 수단으로는 갈 수 없다는 뜻이다. */
  durationS?: number;
  distanceM?: number;
}

export interface RankedCandidate<T> {
  place: T;
  legs: Leg[];
  /** 가장 오래 걸리는 사람의 시간. 순위의 기준이다. */
  maxDurationS: number;
  totalDurationS: number;
  /**
   * 가장 오래 걸리는 사람과 가장 짧은 사람의 차이. 얼마나 공평한지.
   *
   * 모두의 경로를 구했을 때만 값이 있다. 한 명이라도 빠지면 알 수 없는 값인데,
   * 남은 사람이 하나면 최대와 최소가 같아져 "편차 0분 = 완벽하게 공평"으로 읽힌다.
   * 모르는 것을 0으로 보여 주느니 비워 둔다.
   */
  spreadS?: number;
  /** 모든 참가자의 경로를 구했는가. */
  complete: boolean;
}

/**
 * 후보들을 공평한 순서로 세운다.
 *
 * 기준은 **가장 오래 걸리는 사람의 시간**이다. 합계를 줄이면 여러 명이 조금씩 편한
 * 대신 한 사람이 아주 멀리 가는 자리가 뽑힌다. 모임에서 그건 좋은 답이 아니다.
 * 합계는 같은 값일 때의 2차 기준으로만 쓴다.
 *
 * 한 명이라도 경로를 못 구한 후보는 뒤로 보낸다. 아예 버리지는 않는다. 도보로 갈 수
 * 없는 거리라도 "여기까지는 이만큼 걸린다"가 판단에 도움이 된다.
 */
export function rankCandidates<T>(
  entries: readonly { place: T; legs: Leg[] }[],
): RankedCandidate<T>[] {
  return entries
    .map(({ place, legs }) => {
      const times = legs.map((leg) => leg.durationS).filter((t): t is number => t !== undefined);
      const complete = times.length === legs.length && legs.length > 0;
      const max = times.length > 0 ? Math.max(...times) : Number.POSITIVE_INFINITY;
      const min = times.length > 0 ? Math.min(...times) : 0;
      return {
        place,
        legs,
        maxDurationS: max,
        totalDurationS: times.reduce((sum, t) => sum + t, 0),
        ...(complete ? { spreadS: max - min } : {}),
        complete,
      };
    })
    .sort((a, b) => {
      // 다 구해진 후보가 먼저다.
      if (a.complete !== b.complete) return a.complete ? -1 : 1;
      if (a.maxDurationS !== b.maxDurationS) return a.maxDurationS - b.maxDurationS;
      return a.totalDurationS - b.totalDurationS;
    });
}
