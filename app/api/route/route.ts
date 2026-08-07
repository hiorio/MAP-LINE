import { NextResponse } from 'next/server';
import { MissingRestKeyError } from '@/lib/kakao/localSearch';
import { NoRouteError, fetchRoute } from '@/lib/kakao/routing';
import { readCenterParams } from '@/lib/kakao/searchParams';
import { isTravelMode } from '@/lib/map/types';
import { ROUTE_LIMIT, checkRateLimit, tooManyRequests } from '@/lib/rateLimit';

/**
 * 두 지점 사이의 실제 경로를 돌려준다.
 *
 * 카카오 REST 키는 서버 전용이라 클라이언트가 직접 길찾기를 부를 수 없다.
 * 도보·대중교통·자전거는 Kakao Maps Routing, 자동차는 Kakao Mobility Directions를
 * 사용하지만 클라이언트에는 같은 경로 응답으로 돌려준다.
 */
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;

  const mode = params.get('mode');
  if (!isTravelMode(mode) || mode === 'straight') {
    return NextResponse.json(
      { error: '지원하지 않는 이동수단입니다.' },
      { status: 400 },
    );
  }

  const from = readCenterParams(params.get('from_lat'), params.get('from_lng'));
  const to = readCenterParams(params.get('to_lat'), params.get('to_lng'));
  if (!from || !to) {
    return NextResponse.json({ error: '좌표가 올바르지 않습니다.' }, { status: 400 });
  }

  const limit = await checkRateLimit(request, ROUTE_LIMIT);
  if (!limit.allowed) return tooManyRequests(ROUTE_LIMIT);

  try {
    return NextResponse.json(await fetchRoute(mode, from, to));
  } catch (cause) {
    if (cause instanceof NoRouteError) {
      // 실패가 아니라 "이 수단으로는 갈 수 없다"는 답이다. 편집기가 직선으로 되돌린다.
      return NextResponse.json({ error: cause.message, status: cause.status }, { status: 422 });
    }
    if (cause instanceof MissingRestKeyError) {
      return NextResponse.json(
        { error: '서버에 KAKAO_REST_KEY가 설정되지 않았습니다.' },
        { status: 503 },
      );
    }
    console.error('[api/route]', cause);
    return NextResponse.json({ error: '경로를 가져오지 못했습니다.' }, { status: 502 });
  }
}
