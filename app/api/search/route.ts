import { NextResponse } from 'next/server';
import { MissingRestKeyError, searchPlaces } from '@/lib/kakao/localSearch';

/**
 * Kakao 키워드 검색 프록시.
 * 클라이언트는 Kakao REST API를 직접 호출하지 않는다. REST 키가 노출되면 타인이
 * 사용량을 소진시킬 수 있고 그 비용은 우리 비즈월렛에서 나간다.
 */
export async function GET(request: Request) {
  const query = new URL(request.url).searchParams.get('q')?.trim();
  if (!query) {
    return NextResponse.json({ error: '검색어가 없습니다.' }, { status: 400 });
  }

  try {
    return NextResponse.json({ places: await searchPlaces(query) });
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
