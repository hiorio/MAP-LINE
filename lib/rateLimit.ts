import 'server-only';
import { NextResponse } from 'next/server';
import { getServiceClient } from '@/lib/supabase/server';

/**
 * IP 기준 요청 빈도 제한.
 *
 * **한도를 넘지 않았을 때와 확인할 수 없을 때는 통과시킨다.** 제한 장치가 고장 났다고
 * 제품이 멈추면 안 된다. 여기서 막으려는 것은 자동화된 반복 호출이고, 그건 DB가 살아
 * 있을 때만 의미가 있다(생성은 어차피 DB가 필요하다).
 *
 * IP는 프록시가 붙인 헤더에서 읽으므로 위조할 수 있다. 결정적인 방어가 아니라
 * 우발적·단순 반복을 걸러내는 장치다. 진짜 공격을 막아야 할 규모가 되면
 * Cloudflare 같은 앞단이 할 일이다.
 */
export interface RateLimitRule {
  /** 무엇을 세는지. 경로마다 달라야 서로의 한도를 잡아먹지 않는다. */
  name: string;
  limit: number;
  windowSeconds: number;
}

/** 지도 생성: 사람이 한 시간에 20개를 만들 일은 없다. */
export const CREATE_MAP_LIMIT: RateLimitRule = {
  name: 'create-map',
  limit: 20,
  windowSeconds: 60 * 60,
};

/** 카카오 검색: 호출마다 쿼터를 태운다. 사람의 검색 속도로는 닿지 않는 값이다. */
export const SEARCH_LIMIT: RateLimitRule = {
  name: 'search',
  limit: 60,
  windowSeconds: 60,
};

/**
 * 요청자의 IP. Railway·Vercel 모두 프록시를 거치므로 소켓 주소가 아니라 헤더를 본다.
 * `x-forwarded-for`는 쉼표로 이어진 목록이고 맨 앞이 원래 클라이언트다.
 */
export function clientIp(request: Request): string {
  const forwarded = request.headers.get('x-forwarded-for');
  if (forwarded) {
    const first = forwarded.split(',')[0]?.trim();
    if (first) return first;
  }
  return request.headers.get('x-real-ip')?.trim() || 'unknown';
}

export interface RateLimitResult {
  allowed: boolean;
  hits: number;
  rule: RateLimitRule;
}

export async function checkRateLimit(
  request: Request,
  rule: RateLimitRule,
): Promise<RateLimitResult> {
  const supabase = getServiceClient();
  // 셀 수 없으면 통과시킨다. 제한 장치의 장애가 제품의 장애가 되면 안 된다.
  if (!supabase) return { allowed: true, hits: 0, rule };

  const { data, error } = await supabase.rpc('bump_rate_limit', {
    p_bucket: `${rule.name}:${clientIp(request)}`,
    p_window_seconds: rule.windowSeconds,
  });

  if (error) {
    console.error('[rate-limit] 집계 실패', error);
    return { allowed: true, hits: 0, rule };
  }

  const hits = typeof data === 'number' ? data : 0;
  return { allowed: hits <= rule.limit, hits, rule };
}

/** 한도를 넘었을 때 돌려줄 응답. 언제 다시 되는지 함께 알려 준다. */
export function tooManyRequests(rule: RateLimitRule) {
  return NextResponse.json(
    {
      error: '요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.',
      retryAfterSeconds: rule.windowSeconds,
    },
    {
      status: 429,
      headers: {
        'Retry-After': String(rule.windowSeconds),
        'Cache-Control': 'no-store',
      },
    },
  );
}
