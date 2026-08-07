import type { LatLng } from '@/lib/geo/projection';
import type { RoutePath, TransitLeg, TravelMode } from '@/lib/map/types';
import { MissingRestKeyError } from './localSearch';
import { recordKakaoCall } from './usage';

/**
 * 카카오 길찾기. **서버에서만** 호출한다.
 *
 * 도보·대중교통·자전거는 Kakao Maps Routing, 자동차는 Kakao Mobility Directions를
 * 쓴다. 두 제품의 응답 모양이 달라 여기서 하나의 RoutePath 모양으로 정규화한다.
 */
const ENDPOINTS: Record<Exclude<TravelMode, 'straight' | 'car'>, string> = {
  walk: 'https://dapi.kakao.com/v2/routing/walk',
  transit: 'https://dapi.kakao.com/v2/routing/publictraffic',
  bicycle: 'https://dapi.kakao.com/v2/routing/bicycle',
};
const CAR_ENDPOINT = 'https://apis-navi.kakaomobility.com/v1/directions';

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

  const url = new URL(mode === 'car' ? CAR_ENDPOINT : ENDPOINTS[mode]);
  // 좌표는 x=경도, y=위도다. Local API와 같은 함정이 여기에도 있다.
  if (mode === 'car') {
    url.searchParams.set('origin', `${from.lng},${from.lat}`);
    url.searchParams.set('destination', `${to.lng},${to.lat}`);
    url.searchParams.set('priority', 'RECOMMEND');
    // 도로 좌표가 필요하다. summary=true면 거리·시간만 오고 지도에 그릴 선이 없다.
    url.searchParams.set('summary', 'false');
  } else {
    url.searchParams.set('start_x', String(from.lng));
    url.searchParams.set('start_y', String(from.lat));
    url.searchParams.set('end_x', String(to.lng));
    url.searchParams.set('end_y', String(to.lat));
  }

  void recordKakaoCall('route');
  const response = await fetch(url, { headers: { Authorization: `KakaoAK ${key}` } });
  if (!response.ok) {
    throw new Error(`길찾기 실패 (${response.status})`);
  }

  const body: unknown = await response.json();
  if (mode === 'car') return parseDriving(body);
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

    // 좌표를 붙이기 전후를 재서 이 구간이 몇 개를 차지하는지 남긴다.
    // 나중에 다시 잘라 내야 탈것 구간과 사이의 환승 도보를 달리 그릴 수 있다.
    const before = points.length;
    const path = asRecord(stepRecord['path']);
    for (const point of asArray(path['points'])) appendPoint(points, point);
    const pointCount = points.length - before;

    const guidance = stepProps['guidance'];
    const type = stepProps['type'];
    if (typeof guidance === 'string' && guidance !== '') {
      legs.push({
        type: typeof type === 'string' ? type : 'UNKNOWN',
        guidance,
        pointCount,
      });
    }
  }

  if (points.length < 2) throw new NoRouteError(status);
  return {
    points,
    distanceM: toNumber(props['totalDistance']),
    durationS: toNumber(props['totalTime']),
    ...(legs.length > 0 ? { legs } : {}),
  };
}

/**
 * 자동차 길찾기 응답.
 *
 * 각 도로의 `vertexes`는 `[경도, 위도, 경도, 위도, ...]`인 평평한 배열이다. 경유지
 * 없이 호출해도 여러 section/road로 나뉠 수 있으므로 모두 순서대로 이어 붙인다.
 */
export function parseDriving(body: unknown): Parsed {
  const root = asRecord(body);
  const first = asArray(root['routes'])[0];
  if (first === undefined) throw new NoRouteError('CAR_UNKNOWN');

  const route = asRecord(first);
  const resultCode = toNumber(route['result_code']);
  if (resultCode !== 0) throw new NoRouteError(`CAR_${resultCode}`);

  const summary = asRecord(route['summary']);
  const points: LatLng[] = [];

  for (const section of asArray(route['sections'])) {
    for (const road of asArray(asRecord(section)['roads'])) {
      const vertexes = asArray(asRecord(road)['vertexes']);
      for (let index = 0; index + 1 < vertexes.length; index += 2) {
        appendPoint(points, [vertexes[index], vertexes[index + 1]]);
      }
    }
  }

  if (points.length < 2) throw new NoRouteError('CAR_NO_PATH');
  return {
    points,
    distanceM: toNumber(summary['distance']),
    durationS: toNumber(summary['duration']),
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
