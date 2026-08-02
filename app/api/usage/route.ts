import { NextResponse } from 'next/server';
import { readUsage } from '@/lib/kakao/usage';

/**
 * 카카오 API 사용량 확인용. 운영 중 `curl /api/usage`로 지금 얼마나 때리고 있는지 본다.
 *
 * 이 서버 인스턴스 메모리 기준의 근사치다. 정확한 값은 카카오 콘솔 > 통계 > 쿼터.
 */
export function GET() {
  return NextResponse.json(readUsage(), {
    headers: { 'Cache-Control': 'no-store' },
  });
}
