import { NextResponse } from 'next/server';
import { MissingRestKeyError, searchPlaces } from '@/lib/kakao/localSearch';
import { readCenterParams } from '@/lib/kakao/searchParams';
import { SEARCH_LIMIT, checkRateLimit, tooManyRequests } from '@/lib/rateLimit';

/**
 * Kakao 키워드 검색 프록시.
 * 클라이언트는 Kakao REST API를 직접 호출하지 않는다. REST 키가 노출되면 타인이
 * 사용량을 소진시킬 수 있고 그 비용은 우리 비즈월렛에서 나간다.
 */
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const query = params.get('q')?.trim();
  if (!query) {
    return NextResponse.json({ error: '검색어가 없습니다.' }, { status: 400 });
  }

  // 검색은 호출마다 카카오 쿼터를 태운다. 그 비용은 우리가 낸다.
  const limit = await checkRateLimit(request, SEARCH_LIMIT);
  if (!limit.allowed) return tooManyRequests(SEARCH_LIMIT);

  try {
    // 지금 보고 있는 지도 중심을 넘기면 가까운 곳부터 나온다.
    const places = await searchPlaces(query, 5, readCenterParams(params.get('lat'), params.get('lng')));
    return NextResponse.json({ places });
  } catch (cause) {
    if (cause instanceof MissingRestKeyError) {
      return NextResponse.json(
        { error: '서버에 KAKAO_REST_KEY가 설정되지 않았습니다.' },
        { status: 503 },
      );
    }
    console.error('[api/search]', cause);
    return NextResponse.json({ error: '검색에 실패했습니다.' }, { status: 502 });
  }
}
