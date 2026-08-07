import { NextResponse } from 'next/server';
import { MissingRestKeyError } from '@/lib/kakao/localSearch';
import { findNearby } from '@/lib/kakao/nearby';
import { readCenterParams } from '@/lib/kakao/searchParams';
import { SEARCH_LIMIT, checkRateLimit, tooManyRequests } from '@/lib/rateLimit';

/**
 * 지도를 꾹 눌렀을 때 그 지점 주변의 장소를 돌려준다.
 *
 * 한 번 부를 때 카카오 요청이 여러 건 나가므로(카테고리마다 하나 + 주소 하나)
 * 검색과 같은 빈도 제한을 건다.
 */
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const center = readCenterParams(params.get('lat'), params.get('lng'));
  // 기본 지도 POI를 탭한 경우에만 온다. 좌표 주변 후보를 자르기 전에 이 id를 찾아야
  // 밀집 지역에서도 사용자가 누른 장소가 최종 네 곳 밖으로 밀려나지 않는다.
  const poiID = params.get('poiId')?.trim() || undefined;
  if (!center) {
    return NextResponse.json({ error: '좌표가 올바르지 않습니다.' }, { status: 400 });
  }

  const limit = await checkRateLimit(request, SEARCH_LIMIT);
  if (!limit.allowed) return tooManyRequests(SEARCH_LIMIT);

  try {
    return NextResponse.json(await findNearby(center, poiID));
  } catch (cause) {
    if (cause instanceof MissingRestKeyError) {
      return NextResponse.json(
        { error: '서버에 KAKAO_REST_KEY가 설정되지 않았습니다.', places: [] },
        { status: 503 },
      );
    }
    console.error('[api/nearby]', cause);
    // 주변 검색이 실패해도 "여기에 직접 핀"은 할 수 있어야 한다.
    return NextResponse.json({ error: '주변을 찾지 못했습니다.', places: [] }, { status: 502 });
  }
}
