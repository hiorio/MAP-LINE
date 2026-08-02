import { fromKakaoXY } from '@/lib/geo/projection';
import type { LatLng, PlaceCandidate } from '@/lib/map/types';
import { MissingRestKeyError } from './localSearch';
import { recordKakaoCall } from './usage';

/**
 * 지도를 꾹 눌렀을 때 그 지점 주변의 장소를 찾는다.
 *
 * 카카오 지도 SDK는 타일에 그려진 가게가 무엇인지 알려 주지 않는다. 화면에 보이는
 * "○○식당"을 눌렀다는 사실을 코드가 알 방법이 없으므로, 좌표로 주변을 되짚는다.
 *
 * 키워드 없이 주변을 훑으려면 카테고리 코드가 필요하고 코드마다 요청이 하나씩이다.
 * 모든 카테고리를 훑으면 한 번 누를 때마다 십수 건이 나가므로, 이 제품에서 실제로
 * 코스에 담는 종류만 고른다.
 */
const CATEGORY_ENDPOINT = 'https://dapi.kakao.com/v2/local/search/category.json';
const COORD_TO_ADDRESS_ENDPOINT = 'https://dapi.kakao.com/v2/local/geo/coord2address.json';

/** 음식점·카페·관광명소. 모임 코스에 담기는 것의 대부분이다. */
const CATEGORY_CODES = ['FD6', 'CE7', 'AT4'] as const;

/** 손가락으로 짚은 지점 주변. 좁으면 아무것도 안 잡히고 넓으면 엉뚱한 게 섞인다. */
const RADIUS_M = 60;
const PER_CATEGORY = 5;
export const NEARBY_LIMIT = 6;

interface KakaoCategoryDocument {
  id?: string;
  place_name?: string;
  address_name?: string;
  road_address_name?: string;
  category_group_name?: string;
  category_name?: string;
  x?: string;
  y?: string;
  distance?: string;
}

export interface NearbyResult {
  /** 그 지점의 주소. 주변에 아무 장소가 없어도 이건 보여 줄 수 있다. */
  address?: string;
  places: PlaceCandidate[];
}

export async function findNearby(center: LatLng): Promise<NearbyResult> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const headers = { Authorization: `KakaoAK ${key}` };

  const [address, ...categoryResults] = await Promise.all([
    fetchAddress(center, headers),
    ...CATEGORY_CODES.map((code) => fetchCategory(code, center, headers)),
  ]);

  // 카테고리가 겹치면 같은 장소가 두 번 나온다.
  const seen = new Set<string>();
  const places = categoryResults
    .flat()
    .filter((place) => {
      const id = place.kakaoPlaceId || `${place.name}:${place.location.lat}`;
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .sort((a, b) => (a.distanceM ?? Infinity) - (b.distanceM ?? Infinity))
    .slice(0, NEARBY_LIMIT);

  return { ...(address ? { address } : {}), places };
}

async function fetchAddress(
  center: LatLng,
  headers: Record<string, string>,
): Promise<string | undefined> {
  const url = new URL(COORD_TO_ADDRESS_ENDPOINT);
  url.searchParams.set('x', String(center.lng));
  url.searchParams.set('y', String(center.lat));

  void recordKakaoCall('search');
  const response = await fetch(url, { headers });
  if (!response.ok) return undefined;

  const body = (await response.json()) as {
    documents?: { road_address?: { address_name?: string }; address?: { address_name?: string } }[];
  };
  const first = body.documents?.[0];
  return first?.road_address?.address_name ?? first?.address?.address_name ?? undefined;
}

async function fetchCategory(
  code: string,
  center: LatLng,
  headers: Record<string, string>,
): Promise<PlaceCandidate[]> {
  const url = new URL(CATEGORY_ENDPOINT);
  url.searchParams.set('category_group_code', code);
  url.searchParams.set('x', String(center.lng));
  url.searchParams.set('y', String(center.lat));
  url.searchParams.set('radius', String(RADIUS_M));
  url.searchParams.set('sort', 'distance');
  url.searchParams.set('size', String(PER_CATEGORY));

  void recordKakaoCall('search');
  const response = await fetch(url, { headers, next: { revalidate: 300 } });
  // 한 카테고리가 실패해도 나머지는 보여 준다.
  if (!response.ok) return [];

  const body = (await response.json()) as { documents?: KakaoCategoryDocument[] };
  return (body.documents ?? [])
    .map(toNearbyCandidate)
    .filter((place): place is PlaceCandidate => place !== null);
}

export function toNearbyCandidate(document: KakaoCategoryDocument): PlaceCandidate | null {
  const name = document.place_name?.trim();
  if (!name || document.x === undefined || document.y === undefined) return null;

  const location = fromKakaoXY(document.x, document.y);
  if (!Number.isFinite(location.lat) || !Number.isFinite(location.lng)) return null;

  const address = document.address_name?.trim();
  const roadAddress = document.road_address_name?.trim();
  const category = (document.category_group_name || document.category_name)?.trim();
  const distanceM = Number(document.distance);

  return {
    kakaoPlaceId: document.id ?? '',
    name,
    ...(address ? { address } : {}),
    ...(roadAddress ? { roadAddress } : {}),
    ...(category ? { category } : {}),
    ...(Number.isFinite(distanceM) && document.distance ? { distanceM } : {}),
    location,
  };
}
