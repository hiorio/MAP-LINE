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
const KEYWORD_ENDPOINT = 'https://dapi.kakao.com/v2/local/search/keyword.json';
const COORD_TO_ADDRESS_ENDPOINT = 'https://dapi.kakao.com/v2/local/geo/coord2address.json';

/** 음식점·카페·관광명소. 모임 코스에 담기는 것의 대부분이다. */
const CATEGORY_CODES = ['FD6', 'CE7', 'AT4'] as const;

/**
 * 손가락으로 짚은 지점 주변. 좁으면 아무것도 안 잡히고 넓으면 엉뚱한 게 섞인다.
 *
 * 반경은 60m를 유지한다. 좁히면 한적한 동네에서 아무것도 안 잡혀 "여기에 핀"밖에
 * 못 하게 된다. 대신 보여 주는 개수를 줄인다. 이 메뉴는 "짚은 자리가 어디인가"를
 * 묻는 것이지 주변 검색 결과가 아니다. 강남 한복판에서 60m 안에 가게가 수십 곳이라
 * 여섯 개를 늘어놓으면 고르는 일이 되어 버린다. 가까운 순으로 잘라 넷만 둔다.
 */
const RADIUS_M = 60;
/** 주소가 가리키는 건물의 POI는 출입구/대표점이 눌린 좌표보다 조금 멀 수 있다. */
const BUILDING_RADIUS_M = 150;
const PER_CATEGORY = 5;
export const NEARBY_LIMIT = 4;

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

export interface AddressLookup {
  address?: string;
  buildingName?: string;
}

export async function findNearby(center: LatLng): Promise<NearbyResult> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const headers = { Authorization: `KakaoAK ${key}` };

  const addressPromise = fetchAddress(center, headers);
  const categoryPromise = Promise.all(
    CATEGORY_CODES.map((code) => fetchCategory(code, center, headers)),
  );
  const addressResult = await addressPromise;

  // 예식장처럼 Kakao의 15개 대표 카테고리에 없는 시설도 있다. 좌표→주소 응답의
  // 건물명이 있으면 그 이름으로 한 번 더 찾아, 음식점 후보보다 앞에 둔다.
  const buildingPromise = addressResult.buildingName
    ? fetchKeyword(addressResult.buildingName, center, headers)
    : Promise.resolve([]);
  const [categoryResults, buildingResults] = await Promise.all([categoryPromise, buildingPromise]);

  // 카테고리가 겹치면 같은 장소가 두 번 나온다.
  const seen = new Set<string>();
  const categoryPlaces = categoryResults
    .flat()
    .sort((a, b) => (a.distanceM ?? Infinity) - (b.distanceM ?? Infinity));
  const places = [...buildingResults, ...categoryPlaces]
    .filter((place) => {
      const id = place.kakaoPlaceId || `${place.name}:${place.location.lat}`;
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .slice(0, NEARBY_LIMIT);

  return { ...(addressResult.address ? { address: addressResult.address } : {}), places };
}

async function fetchAddress(
  center: LatLng,
  headers: Record<string, string>,
): Promise<AddressLookup> {
  const url = new URL(COORD_TO_ADDRESS_ENDPOINT);
  url.searchParams.set('x', String(center.lng));
  url.searchParams.set('y', String(center.lat));

  void recordKakaoCall('search');
  const response = await fetch(url, { headers });
  if (!response.ok) return {};

  const body = (await response.json()) as {
    documents?: {
      road_address?: { address_name?: string; building_name?: string };
      address?: { address_name?: string };
    }[];
  };
  return toAddressLookup(body.documents?.[0]);
}

export function toAddressLookup(document?: {
  road_address?: { address_name?: string; building_name?: string };
  address?: { address_name?: string };
}): AddressLookup {
  const roadAddress = document?.road_address?.address_name?.trim();
  const parcelAddress = document?.address?.address_name?.trim();
  const buildingName = document?.road_address?.building_name?.trim();

  return {
    ...(roadAddress || parcelAddress ? { address: roadAddress || parcelAddress } : {}),
    ...(buildingName ? { buildingName } : {}),
  };
}

async function fetchKeyword(
  query: string,
  center: LatLng,
  headers: Record<string, string>,
): Promise<PlaceCandidate[]> {
  const url = new URL(KEYWORD_ENDPOINT);
  url.searchParams.set('query', query);
  url.searchParams.set('x', String(center.lng));
  url.searchParams.set('y', String(center.lat));
  url.searchParams.set('radius', String(BUILDING_RADIUS_M));
  url.searchParams.set('sort', 'distance');
  url.searchParams.set('size', String(PER_CATEGORY));

  void recordKakaoCall('search');
  const response = await fetch(url, { headers, next: { revalidate: 300 } });
  if (!response.ok) return [];

  const body = (await response.json()) as { documents?: KakaoCategoryDocument[] };
  return (body.documents ?? [])
    .map(toNearbyCandidate)
    .filter((place): place is PlaceCandidate => place !== null);
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
