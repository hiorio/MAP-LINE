import { fromKakaoXY } from '@/lib/geo/projection';
import type { PlaceCandidate } from '@/lib/map/types';
import { recordKakaoCall } from './usage';

/**
 * Kakao Local 키워드 검색. **서버에서만** 호출한다.
 *
 * REST 키가 클라이언트에 노출되면 타인이 사용량을 소진시킬 수 있고 그 비용은 우리가 낸다.
 * 그래서 브라우저는 이 모듈을 직접 쓰지 않고 항상 Route Handler를 경유한다.
 */
const KEYWORD_ENDPOINT = 'https://dapi.kakao.com/v2/local/search/keyword.json';

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
}

export class MissingRestKeyError extends Error {
  constructor() {
    super('KAKAO_REST_KEY가 설정되지 않았습니다.');
    this.name = 'MissingRestKeyError';
  }
}

export async function searchPlaces(query: string, size = 5): Promise<PlaceCandidate[]> {
  const key = process.env.KAKAO_REST_KEY;
  if (!key) throw new MissingRestKeyError();

  const url = new URL(KEYWORD_ENDPOINT);
  url.searchParams.set('query', query);
  url.searchParams.set('size', String(Math.min(Math.max(size, 1), 15)));

  recordKakaoCall('search');
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

  return {
    kakaoPlaceId: document.id ?? '',
    name,
    ...(address ? { address } : {}),
    ...(roadAddress ? { roadAddress } : {}),
    ...(category ? { category } : {}),
    location,
  };
}
