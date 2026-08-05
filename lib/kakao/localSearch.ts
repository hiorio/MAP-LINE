import { fromKakaoXY } from '@/lib/geo/projection';
import type { LatLng, PlaceCandidate } from '@/lib/map/types';
import { recordKakaoCall } from './usage';

/**
 * Kakao Local 키워드 검색. **서버에서만** 호출한다.
 *
 * REST 키가 클라이언트에 노출되면 타인이 사용량을 소진시킬 수 있고 그 비용은 우리가 낸다.
 * 그래서 브라우저는 이 모듈을 직접 쓰지 않고 항상 Route Handler를 경유한다.
 */
const KEYWORD_ENDPOINT = 'https://dapi.kakao.com/v2/local/search/keyword.json';
const ADDRESS_ENDPOINT = 'https://dapi.kakao.com/v2/local/search/address.json';

/** Kakao Local 응답 문서 중 우리가 쓰는 필드만. */
interface KakaoPlaceDocument {
  id?: string;
  place_name?: string;
  address_name?: string;
  road_address_name?: string;
  category_group_name?: string;
  category_name?: string;
  x?: string;
  y?: string;
  /** 기준 좌표를 넘겼을 때만 채워진다. 단위는 m. */
  distance?: string;
}

interface KakaoAddressDocument {
  address_name?: string;
  x?: string;
  y?: string;
  address?: { address_name?: string } | null;
  road_address?: { address_name?: string; building_name?: string } | null;
}

export class MissingRestKeyError extends Error {
  constructor() {
    super('KAKAO_REST_KEY가 설정되지 않았습니다.');
    this.name = 'MissingRestKeyError';
  }
}

export async function searchPlaces(
  query: string,
  size = 5,
  /**
   * 검색 기준점. 보통 지금 보고 있는 지도의 중심이다.
   *
   * 넘기면 거리순으로 정렬한다. "스타벅스"처럼 같은 이름이 전국에 흩어져 있는 질의에서
   * 지금 보고 있는 동네의 지점이 위로 올라온다. 반경은 걸지 않는다 — 걸면 멀리 있는
   * 장소를 일부러 찾을 때 결과가 통째로 사라진다.
   */
  center?: LatLng,
): Promise<PlaceCandidate[]> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const url = new URL(KEYWORD_ENDPOINT);
  url.searchParams.set('query', query);
  url.searchParams.set('size', String(Math.min(Math.max(size, 1), 15)));

  if (center) {
    // 좌표는 x=경도, y=위도 순서다.
    url.searchParams.set('x', String(center.lng));
    url.searchParams.set('y', String(center.lat));
    url.searchParams.set('sort', 'distance');
  }

  // 집계 때문에 검색이 느려지거나 막히면 안 된다. 기다리지 않는다.
  void recordKakaoCall('search');
  const response = await fetch(url, {
    headers: { Authorization: `KakaoAK ${key}` },
    // 상호·좌표는 캐시 취급이므로 짧게 캐시해 쿼터를 아낀다.
    next: { revalidate: 300 },
  });

  if (!response.ok) {
    throw new Error(`Kakao Local 검색 실패 (${response.status})`);
  }

  const body = (await response.json()) as { documents?: KakaoPlaceDocument[] };
  return (body.documents ?? []).map(toCandidate).filter((c): c is PlaceCandidate => c !== null);
}

/** 정확한 주소는 상호 키워드가 아니라 Kakao 주소 검색으로 먼저 좌표화한다. */
export async function searchAddress(address: string, size = 3): Promise<PlaceCandidate[]> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const url = new URL(ADDRESS_ENDPOINT);
  url.searchParams.set('query', address);
  url.searchParams.set('size', String(Math.min(Math.max(size, 1), 30)));

  void recordKakaoCall('search');
  const response = await fetch(url, {
    headers: { Authorization: `KakaoAK ${key}` },
    next: { revalidate: 86_400 },
  });
  if (!response.ok) throw new Error(`Kakao Local 주소 검색 실패 (${response.status})`);

  const body = (await response.json()) as { documents?: KakaoAddressDocument[] };
  return (body.documents ?? [])
    .map(toAddressCandidate)
    .filter((candidate): candidate is PlaceCandidate => candidate !== null);
}

export function toAddressCandidate(document: KakaoAddressDocument): PlaceCandidate | null {
  if (document.x === undefined || document.y === undefined) return null;
  const location = fromKakaoXY(document.x, document.y);
  if (!Number.isFinite(location.lat) || !Number.isFinite(location.lng)) return null;

  const roadAddress = document.road_address?.address_name?.trim();
  const jibunAddress = document.address?.address_name?.trim() || document.address_name?.trim();
  const name = document.road_address?.building_name?.trim() || roadAddress || jibunAddress;
  if (!name) return null;
  return {
    kakaoPlaceId: '',
    name,
    ...(jibunAddress ? { address: jibunAddress } : {}),
    ...(roadAddress ? { roadAddress } : {}),
    location,
  };
}

/**
 * Kakao Local 응답의 `x`가 경도, `y`가 위도다. 순서가 직관과 반대이므로
 * 변환은 한곳에 가둔다.
 */
export function toCandidate(document: KakaoPlaceDocument): PlaceCandidate | null {
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
