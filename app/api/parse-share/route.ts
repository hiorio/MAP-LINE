import { NextResponse } from 'next/server';
import { MissingRestKeyError, searchPlaces } from '@/lib/kakao/localSearch';
import { parseShareText } from '@/lib/kakao/parseShareText';
import { readCenterParams } from '@/lib/kakao/searchParams';
import { SEARCH_LIMIT, checkRateLimit, tooManyRequests } from '@/lib/rateLimit';

/** 프랜차이즈 동명 지점을 자동 확정하면 엉뚱한 지점이 담긴다. 항상 고르게 한다. */
const CANDIDATE_COUNT = 3;

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

  const parsed = parseShareText(text);
  if (!parsed) {
    return NextResponse.json(
      { error: '장소 이름을 찾지 못했습니다. 이름이나 주소를 함께 붙여넣어 주세요.' },
      { status: 422 },
    );
  }

  try {
    // URL은 버리고, 뽑아낸 이름·지역으로 Kakao Local에 정식 재검색을 건다.
    // 지도 중심을 함께 넘겨 동명 지점 중 가까운 것이 위로 오게 한다.
    const coordinate = center as { lat?: unknown; lng?: unknown } | undefined;
    const places = await searchPlaces(
      parsed.query,
      CANDIDATE_COUNT,
      readCenterParams(coordinate?.lat, coordinate?.lng),
    );
    return NextResponse.json({ parsed, places });
  } catch (cause) {
    if (cause instanceof MissingRestKeyError) {
      return NextResponse.json(
        { parsed, places: [], error: '서버에 KAKAO_REST_KEY가 설정되지 않았습니다.' },
        { status: 503 },
      );
    }
    console.error('[api/parse-share]', cause);
    return NextResponse.json({ parsed, places: [], error: '검색에 실패했습니다.' }, { status: 502 });
  }
}
