import { NextResponse } from 'next/server';
import { readUsage, summarizeToday } from '@/lib/kakao/usage';

/**
 * 카카오 API 사용량 확인용. 운영 중 `curl /api/usage`로 본다.
 *
 * 최종 근거는 카카오 콘솔 > 통계 > 쿼터다. 여기 값은 우리 서버가 보낸 요청 수라
 * 집계 방식이 콘솔과 다를 수 있다.
 */
export async function GET(request: Request) {
  const days = Number(new URL(request.url).searchParams.get('days') ?? 7);
  const { configured, rows } = await readUsage(Number.isFinite(days) ? days : 7);

  if (!configured) {
    return NextResponse.json(
      { error: 'Supabase가 설정되지 않아 사용량을 집계하지 않습니다.' },
      { status: 503 },
    );
  }

  return NextResponse.json(
    { today: summarizeToday(rows), history: rows },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
