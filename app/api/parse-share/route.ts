import { NextResponse } from 'next/server';
import { MissingRestKeyError, searchAddress, searchPlaces } from '@/lib/kakao/localSearch';
import { parseShareTexts, type ParsedShare } from '@/lib/kakao/parseShareText';
import type { PlaceCandidate } from '@/lib/map/types';
import { readCenterParams } from '@/lib/kakao/searchParams';
import { SEARCH_LIMIT, checkRateLimit, tooManyRequests } from '@/lib/rateLimit';

/** 프랜차이즈 동명 지점을 자동 확정하면 엉뚱한 지점이 담긴다. 항상 고르게 한다. */
const CANDIDATE_COUNT = 5;
const MAX_SHARED_ITEMS = 10;

export async function POST(request: Request) {
  let text: unknown;
  let center: unknown;
  try {
    ({ text, center } = (await request.json()) as { text?: unknown; center?: unknown });
  } catch {
    return NextResponse.json({ error: '잘못된 요청 본문입니다.' }, { status: 400 });
  }

  if (typeof text !== 'string' || text.trim().length === 0) {
    return NextResponse.json({ error: '붙여넣은 텍스트가 없습니다.' }, { status: 400 });
  }

  // 이 경로도 결국 Kakao Local을 부른다. 검색과 같은 한도를 공유한다.
  const limit = await checkRateLimit(request, SEARCH_LIMIT);
  if (!limit.allowed) return tooManyRequests(SEARCH_LIMIT);

  const parsedItems = parseShareTexts(text).slice(0, MAX_SHARED_ITEMS);
  if (parsedItems.length === 0) {
    return NextResponse.json(
      { error: '장소 이름을 찾지 못했습니다. 이름이나 주소를 함께 붙여넣어 주세요.' },
      { status: 422 },
    );
  }

  try {
    // URL은 버리고, 뽑아낸 이름·지역으로 Kakao Local에 정식 재검색을 건다.
    // 지도 중심을 함께 넘겨 동명 지점 중 가까운 것이 위로 오게 한다.
    const coordinate = center as { lat?: unknown; lng?: unknown } | undefined;
    const mapCenter = readCenterParams(coordinate?.lat, coordinate?.lng);
    const groups = await Promise.all(
      parsedItems.map(async (parsed) => ({
        parsed,
        places: await findCandidates(parsed, mapCenter),
      })),
    );
    // 웹의 기존 붙여넣기 화면은 평평한 places를 읽는다. groups를 추가하되 호환 필드는
    // 유지해 앱 업데이트와 웹 배포 순서가 달라도 깨지지 않게 한다.
    const places = dedupe(groups.flatMap((group) => group.places));
    return NextResponse.json({ parsed: parsedItems[0], groups, places });
  } catch (cause) {
    if (cause instanceof MissingRestKeyError) {
      return NextResponse.json(
        { parsed: parsedItems[0], groups: [], places: [], error: '서버에 KAKAO_REST_KEY가 설정되지 않았습니다.' },
        { status: 503 },
      );
    }
    console.error('[api/parse-share]', cause);
    return NextResponse.json({ parsed: parsedItems[0], groups: [], places: [], error: '검색에 실패했습니다.' }, { status: 502 });
  }
}

async function findCandidates(parsed: ParsedShare, center?: { lat: number; lng: number }) {
  const [exact, keyword] = await Promise.all([
    parsed.address ? searchAddress(parsed.address, 3) : Promise.resolve([]),
    searchPlaces(parsed.query, CANDIDATE_COUNT, center),
  ]);
  // 주소 검색 결과는 건물명이 없을 수 있다. 공유 원문에 장소명이 있으면 그 이름을
  // 보존하되 좌표·주소는 정확한 주소 검색 결과를 쓴다.
  const namedExact = exact.map((place) => ({
    ...place,
    name: parsed.name === parsed.address ? place.name : parsed.name,
  }));
  return dedupe([...namedExact, ...keyword]).slice(0, CANDIDATE_COUNT);
}

function dedupe(places: readonly PlaceCandidate[]): PlaceCandidate[] {
  const seen = new Set<string>();
  return places.filter((place) => {
    const key = place.kakaoPlaceId || `${place.location.lat.toFixed(6)},${place.location.lng.toFixed(6)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
