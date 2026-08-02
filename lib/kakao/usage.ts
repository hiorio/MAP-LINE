import 'server-only';
import { getServiceClient } from '@/lib/supabase/server';

/**
 * 카카오 REST API 호출 횟수를 Postgres에 기록한다.
 *
 * 설계안 §10: 무료 쿼터(정적 지도 일 1,000건 등)는 "추후 별도 안내 전까지"라는 단서가
 * 붙어 있고 초과분은 우리가 낸다. 소진된 뒤에 알면 늦는다.
 *
 * 프로세스 메모리가 아니라 DB에 두는 이유: 재배포하면 사라지고 인스턴스가 여러 개면
 * 각자 따로 세어 합계가 실제보다 **적게** 나온다. 쿼터 초과를 판단해야 하는 값이
 * 작게 나오는 것은 위험한 방향의 오차다.
 *
 * 카카오 콘솔의 [통계 > 쿼터]가 여전히 최종 근거다. 이 값은 우리 쪽에서 본 호출 수이고,
 * 실패한 요청이나 캐시로 막힌 요청까지 세는 방식이 콘솔과 다를 수 있다.
 */
export type KakaoApi = 'search' | 'staticmap' | 'route';

/** 카카오가 공지한 일일 무료 쿼터 */
export const DAILY_QUOTA: Record<KakaoApi, number> = {
  search: 100_000,
  staticmap: 1_000,
  route: 1_000,
};

/** 이 비율을 넘으면 경고 로그를 남긴다 */
const WARN_RATIO = 0.8;

/** 같은 날 같은 API로 경고를 한 번만 남기기 위한 표식 */
const warned = new Set<string>();

/**
 * 호출 1건을 기록한다.
 *
 * 실패해도 throw하지 않는다. 사용량 집계 때문에 검색이나 썸네일 생성이 막히면 안 된다.
 */
export async function recordKakaoCall(api: KakaoApi): Promise<void> {
  const supabase = getServiceClient();
  if (!supabase) return;

  const { data, error } = await supabase.rpc('record_api_call', { p_api: api });
  if (error) {
    console.error('[kakao-quota] 사용량 기록 실패', error);
    return;
  }

  const used = typeof data === 'number' ? data : 0;
  const quota = DAILY_QUOTA[api];
  const key = `${new Date().toISOString().slice(0, 10)}:${api}`;

  if (used >= quota * WARN_RATIO && !warned.has(key)) {
    warned.add(key);
    console.warn(
      `[kakao-quota] ${api} 사용량이 일일 무료 쿼터의 ${Math.round(WARN_RATIO * 100)}%를 넘었습니다 ` +
        `(${used}/${quota}). 카카오 콘솔 > 통계 > 쿼터에서 실제 사용량을 확인하세요.`,
    );
  }
}

export interface UsageRow {
  day: string;
  api: KakaoApi;
  calls: number;
}

export async function readUsage(days = 7) {
  const supabase = getServiceClient();
  if (!supabase) return { configured: false as const, rows: [] as UsageRow[] };

  const { data, error } = await supabase.rpc('get_api_usage', { p_days: days });
  if (error) {
    console.error('[kakao-quota] 사용량 조회 실패', error);
    return { configured: true as const, rows: [] as UsageRow[] };
  }

  return { configured: true as const, rows: (data ?? []) as UsageRow[] };
}

/** 오늘 사용량을 쿼터와 함께 정리한다. */
export function summarizeToday(rows: readonly UsageRow[]) {
  const today = new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);

  return (Object.keys(DAILY_QUOTA) as KakaoApi[]).map((api) => {
    const used = rows.find((row) => row.day === today && row.api === api)?.calls ?? 0;
    const quota = DAILY_QUOTA[api];
    return {
      api,
      used,
      quota,
      ratio: Number((used / quota).toFixed(4)),
      warn: used >= quota * WARN_RATIO,
    };
  });
}
