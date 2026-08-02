import { NextResponse } from 'next/server';
import { lastRecordFailure, readUsage, summarizeToday } from '@/lib/kakao/usage';

/**
 * 카카오 API 사용량 확인용. 운영 중 `curl /api/usage`로 본다.
 *
 * 데이터베이스에 닿지 못하면 200을 주지 않는다. 예전에는 오류를 삼키고 빈 목록을
 * 200으로 돌려줬는데, 그러면 "아직 아무도 안 썼다"와 "DB가 죽었다"가 똑같이 보인다.
 * 실제로 배포본이 삭제된 프로젝트를 가리키고 있는데도 이 응답만 보고 정상이라고
 * 판단한 적이 있다. 이 경로는 상태를 보러 오는 곳이니 상태를 숨기면 안 된다.
 *
 * 최종 근거는 카카오 콘솔 > 통계 > 쿼터다. 여기 값은 우리 서버가 보낸 요청 수라
 * 집계 방식이 콘솔과 다를 수 있다.
 */
export async function GET(request: Request) {
  const days = Number(new URL(request.url).searchParams.get('days') ?? 7);
  const usage = await readUsage(Number.isFinite(days) ? days : 7);

  if (!usage.configured) {
    return NextResponse.json(
      { status: 'unconfigured', error: usage.error },
      { status: 503, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  if (!usage.reachable) {
    return NextResponse.json(
      { status: 'unreachable', error: usage.error },
      { status: 502, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const recordFailure = lastRecordFailure();
  return NextResponse.json(
    {
      status: 'ok',
      today: summarizeToday(usage.rows),
      history: usage.rows,
      // 있으면 화면의 사용량이 실제보다 적다는 뜻이다.
      ...(recordFailure ? { recordFailure } : {}),
    },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
