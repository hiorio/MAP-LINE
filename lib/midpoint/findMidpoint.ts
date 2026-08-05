import { fromKakaoXY, type LatLng } from '@/lib/geo/projection';
import { MissingRestKeyError } from '@/lib/kakao/localSearch';
import { NoRouteError, fetchRoute } from '@/lib/kakao/routing';
import { recordKakaoCall } from '@/lib/kakao/usage';
import {
  dedupeStations,
  rankCandidates,
  searchRadiusM,
  shortlist,
  travelWeightedCenter,
  type Leg,
  type Participant,
  type RankedCandidate,
} from './geometry';

/**
 * 여러 곳에서 오는 사람들이 모이기 좋은 자리를 찾는다.
 *
 * 순서가 곧 비용 관리다.
 *
 *   1. 느린 이동수단 쪽에 무게를 둔 중심을 구한다 (호출 0건)
 *   2. 그 주변의 지하철역을 찾는다 (검색 1건, 하루 10만 건짜리 넉넉한 쿼터)
 *   3. 이동수단별 예상 시간으로 결선 후보 몇 개만 남긴다 (호출 0건)
 *   4. 결선 후보에만 실제 경로를 묻는다 (참가자 × 결선 후보)
 *
 * 4번이 비싸다. 길찾기는 하루 1,000건인데 곱셈으로 늘어난다. 후보를 그대로 다 부르면
 * 몇 번 만에 바닥나므로 3번에서 반드시 줄인다.
 *
 * 후보를 지하철역으로 잡는 이유: 사람들은 실제로 역에서 만난다. 식당이나 카페를
 * 후보로 주면 "거기서 만나자"가 아니라 "거기 가자"가 되어 모임 장소를 미리 정해
 * 버리는 셈이 된다. 역은 어디로든 흩어질 수 있는 자리다.
 */
const CATEGORY_ENDPOINT = 'https://dapi.kakao.com/v2/local/search/category.json';

/** 지하철역 */
const SUBWAY_CATEGORY = 'SW8';

/** 카카오에서 받아 올 후보 수. 여기까지는 싸다. */
const SEARCH_SIZE = 15;

/**
 * 실제 경로를 물어볼 결선 후보 수.
 *
 * 참가자 4명이면 5 × 4 = 20건이다. 하루 1,000건이면 약 50번 계산할 수 있다.
 * 늘리면 답이 조금 나아지지만 하루 사용량이 그만큼 준다.
 */
const ROUTED_FINALISTS = 5;

/** 실제 경로까지 비교한 뒤 사용자에게 보여 줄 후보 수. */
const RETURNED_CANDIDATES = 3;

export interface MidpointResult {
  /** 참고용 기하 중심. 이건 답이 아니라 후보를 찾은 출발점이다. */
  center: LatLng;
  searchRadiusM: number;
  candidates: RankedCandidate<MeetingPlace>[];
}

export interface MeetingPlace {
  kakaoPlaceId?: string;
  name: string;
  address?: string;
  location: LatLng;
}

export class NotEnoughParticipantsError extends Error {
  constructor() {
    super('중간지점을 찾으려면 두 명 이상이 필요합니다.');
    this.name = 'NotEnoughParticipantsError';
  }
}

export class NoMeetingPlaceError extends Error {
  constructor() {
    super('가운데 근처에서 모일 만한 역을 찾지 못했습니다.');
    this.name = 'NoMeetingPlaceError';
  }
}

export async function findMidpoint(participants: Participant[]): Promise<MidpointResult> {
  if (participants.length < 2) throw new NotEnoughParticipantsError();

  const center = travelWeightedCenter(participants);
  if (!center) throw new NotEnoughParticipantsError();

  const radius = searchRadiusM(center, participants.map((p) => p.location));
  const places = await findStations(center, radius);
  if (places.length === 0) throw new NoMeetingPlaceError();

  // 환승역은 노선마다 따로 오므로 먼저 합친다. 합치기 전에 추리면 세 자리를
  // 같은 역이 다 차지해 고를 것이 없어지고 경로 호출도 같은 자리에 세 번 나간다.
  const finalists = shortlist(dedupeStations(places), participants, ROUTED_FINALISTS);

  // 참가자 × 후보를 한꺼번에 띄운다. 순차로 돌면 사람이 기다린다.
  const entries = await Promise.all(
    finalists.map(async (place) => ({
      place,
      legs: await Promise.all(participants.map((person) => legFor(person, place.location))),
    })),
  );

  return {
    center,
    searchRadiusM: radius,
    candidates: rankCandidates(entries).slice(0, RETURNED_CANDIDATES),
  };
}

/**
 * 한 사람이 그 자리까지 가는 데 걸리는 시간.
 *
 * 실패해도 후보 전체를 버리지 않는다. 도보로 갈 수 없는 거리면 그 사람의 다리만
 * 비워 두고, 순위에서 뒤로 밀린다. "왜 안 나오는지" 모르는 것보다 낫다.
 */
async function legFor(person: Participant, to: LatLng): Promise<Leg> {
  try {
    const route = await fetchRoute(person.mode, person.location, to);
    return {
      participantId: person.id,
      mode: person.mode,
      durationS: route.durationS,
      distanceM: route.distanceM,
      points: route.points,
      ...(route.legs ? { transitLegs: route.legs } : {}),
    };
  } catch (cause) {
    // 길이 없는 것과 서버가 죽은 것은 다르다. 뒤쪽은 위로 올려 보내야 고칠 수 있다.
    if (cause instanceof NoRouteError) return { participantId: person.id, mode: person.mode };
    if (cause instanceof MissingRestKeyError) throw cause;
    console.error('[findMidpoint] 경로 실패', cause);
    return { participantId: person.id, mode: person.mode };
  }
}

async function findStations(center: LatLng, radius: number): Promise<MeetingPlace[]> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const url = new URL(CATEGORY_ENDPOINT);
  url.searchParams.set('category_group_code', SUBWAY_CATEGORY);
  url.searchParams.set('x', String(center.lng));
  url.searchParams.set('y', String(center.lat));
  url.searchParams.set('radius', String(radius));
  url.searchParams.set('sort', 'distance');
  url.searchParams.set('size', String(SEARCH_SIZE));

  void recordKakaoCall('search');
  const response = await fetch(url, {
    headers: { Authorization: `KakaoAK ${key}` },
    // 역은 자리를 옮기지 않는다. 같은 자리를 다시 물을 이유가 없다.
    next: { revalidate: 86_400 },
  });
  if (!response.ok) throw new NoMeetingPlaceError();

  const body = (await response.json()) as {
    documents?: {
      id?: string;
      place_name?: string;
      address_name?: string;
      x?: string;
      y?: string;
    }[];
  };

  return (body.documents ?? [])
    .map((doc): MeetingPlace | null => {
      const name = doc.place_name?.trim();
      if (!name || doc.x === undefined || doc.y === undefined) return null;
      const location = fromKakaoXY(doc.x, doc.y);
      if (!Number.isFinite(location.lat) || !Number.isFinite(location.lng)) return null;
      return {
        ...(doc.id ? { kakaoPlaceId: doc.id } : {}),
        name,
        ...(doc.address_name?.trim() ? { address: doc.address_name.trim() } : {}),
        location,
      };
    })
    .filter((place): place is MeetingPlace => place !== null);
}
