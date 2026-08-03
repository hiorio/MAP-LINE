import type { LatLng } from '@/lib/geo/projection';
import type { RoutePath, TransitLeg, TravelMode } from '@/lib/map/types';
import { MissingRestKeyError } from './localSearch';
import { recordKakaoCall } from './usage';

/**
 * 카카오맵 길찾기. **서버에서만** 호출한다.
 *
 * 카카오모빌리티의 자동차 길찾기(`apis-navi`)와는 다른 API다. 그쪽은 결과의 자체 DB
 * 저장이 정책상 막혀 있어 링크를 나중에 여는 이 제품과 맞지 않는다. 이쪽
 * (`dapi.kakao.com/v2/routing`)은 개발자 운영정책이 적용되고, 사용자 환경 개선 목적에
 * 신선도를 유지하는 캐시는 허용된다. 그래서 도보·대중교통·자전거만 쓴다.
 *
 * 셋 다 별도 신청 없이 기존 REST 키로 열려 있고 각각 하루 1,000건이다.
 */
const ENDPOINTS: Record<Exclude<TravelMode, 'straight'>, string> = {
  walk: 'https://dapi.kakao.com/v2/routing/walk',
  transit: 'https://dapi.kakao.com/v2/routing/publictraffic',
  bicycle: 'https://dapi.kakao.com/v2/routing/bicycle',
};

/** 길찾기가 좌표를 못 냈을 때. 호출 자체는 성공(200)하고 status로 알려 온다. */
export class NoRouteError extends Error {
  constructor(readonly status: string) {
    super(`경로를 찾지 못했습니다 (${status})`);
    this.name = 'NoRouteError';
  }
}

export async function fetchRoute(
  mode: Exclude<TravelMode, 'straight'>,
  from: LatLng,
  to: LatLng,
): Promise<Omit<RoutePath, 'fromPlaceId' | 'toPlaceId' | 'fetchedAt'>> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const url = new URL(ENDPOINTS[mode]);
  // 좌표는 x=경도, y=위도다. Local API와 같은 함정이 여기에도 있다.
  url.searchParams.set('start_x', String(from.lng));
  url.searchParams.set('start_y', String(from.lat));
  url.searchParams.set('end_x', String(to.lng));
  url.searchParams.set('end_y', String(to.lat));

  void recordKakaoCall('route');
  const response = await fetch(url, { headers: { Authorization: `KakaoAK ${key}` } });
  if (!response.ok) {
    throw new Error(`길찾기 실패 (${response.status})`);
  }

  const body: unknown = await response.json();
  return mode === 'transit' ? parseTransit(body) : parsePath(body);
}

type Parsed = Omit<RoutePath, 'fromPlaceId' | 'toPlaceId' | 'fetchedAt'>;

/**
 * 도보·자전거 응답.
 *
 * `route.legs[].steps[].path.points`에 [경도, 위도] 쌍이 들어 있다. 단계마다 나뉘어
 * 있지만 그리는 입장에서는 한 줄이므로 이어 붙인다. 이음매의 중복 좌표는 걷어낸다.
 */
export function parsePath(body: unknown): Parsed {
  const root = asRecord(body);
  const status = typeof root['status'] === 'string' ? root['status'] : 'UNKNOWN';
  const route = asRecord(root['route']);
  const legs = asArray(route['legs']);

  const points: LatLng[] = [];
  let distanceM = 0;
  let durationS = 0;

  for (const leg of legs) {
    const legRecord = asRecord(leg);
    const props = asRecord(legRecord['properties']);
    distanceM += toNumber(props['distance']);
    durationS += toNumber(props['time']);

    for (const step of asArray(legRecord['steps'])) {
      const path = asRecord(asRecord(step)['path']);
      for (const point of asArray(path['points'])) appendPoint(points, point);
    }
  }

  if (points.length < 2) throw new NoRouteError(status);
  return { points, distanceM, durationS };
}

/**
 * 대중교통 응답.
 *
 * 지하철·버스 대안이 여럿 오는데 첫 번째가 카카오의 추천이다. 그것만 쓴다.
 * 좌표뿐 아니라 "2호선 (강남 > 역삼)" 같은 안내 문구가 구간마다 오는데, 노선과
 * 정거장이 담긴 이 문구가 궤적보다 더 쓸모 있어 배지로 함께 남긴다.
 */
export function parseTransit(body: unknown): Parsed {
  const root = asRecord(body);
  const status = typeof root['status'] === 'string' ? root['status'] : 'UNKNOWN';
  const first = asArray(root['routes'])[0];
  if (first === undefined) throw new NoRouteError(status);

  const route = asRecord(first);
  const props = asRecord(route['properties']);

  const points: LatLng[] = [];
  const legs: TransitLeg[] = [];

  for (const step of asArray(route['steps'])) {
    const stepRecord = asRecord(step);
    const stepProps = asRecord(stepRecord['properties']);

    const guidance = stepProps['guidance'];
    const type = stepProps['type'];
    if (typeof guidance === 'string' && guidance !== '') {
      legs.push({ type: typeof type === 'string' ? type : 'UNKNOWN', guidance });
    }

    const path = asRecord(stepRecord['path']);
    for (const point of asArray(path['points'])) appendPoint(points, point);
  }

  if (points.length < 2) throw new NoRouteError(status);
  return {
    points,
    distanceM: toNumber(props['totalDistance']),
    durationS: toNumber(props['totalTime']),
    ...(legs.length > 0 ? { legs } : {}),
  };
}

/** [경도, 위도] 한 쌍을 받아 붙인다. 직전 좌표와 같으면 버린다. */
function appendPoint(points: LatLng[], value: unknown): void {
  if (!Array.isArray(value) || value.length < 2) return;
  const lng = Number(value[0]);
  const lat = Number(value[1]);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

  const last = points.at(-1);
  if (last && last.lat === lat && last.lng === lng) return;
  points.push({ lat, lng });
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function toNumber(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n) : 0;
}
