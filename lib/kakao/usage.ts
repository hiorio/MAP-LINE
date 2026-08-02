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
 * 마지막 기록 실패. 집계가 조용히 멈춘 상태를 밖에서 알아볼 수 있게 남긴다.
 * 이 값이 있으면 화면에 보이는 사용량이 실제보다 적다는 뜻이다.
 */
let lastRecordError: { at: string; message: string } | null = null;

export function lastRecordFailure() {
  return lastRecordError;
}

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
    // 집계 실패는 검색을 막지 않는다. 다만 조용히 넘어가면 쿼터 수치가 실제보다
    // 낮게 보여 초과를 놓치므로, 최근 실패를 남겨 /api/usage가 알려 주게 한다.
    lastRecordError = { at: new Date().toISOString(), message: error.message };
    console.error('[kakao-quota] 사용량 기록 실패', error);
    return;
  }
  lastRecordError = null;

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

/**
 * 사용량 조회 결과.
 *
 * `configured`(환경 변수가 있는가)와 `reachable`(질의가 실제로 성공했는가)을 나눠서
 * 돌려준다. 하나로 뭉치면 DB가 죽었을 때도 "설정됨 + 빈 목록"으로 보여서, 사용량이
 * 0인 것인지 DB가 안 붙는 것인지 구분할 수 없다. 실제로 배포 환경에서 잘못된 자격
 * 증명을 그대로 두고 정상이라고 오판한 적이 있다.
 */
export interface UsageResult {
  configured: boolean;
  reachable: boolean;
  rows: UsageRow[];
  error?: string;
}

export async function readUsage(days = 7): Promise<UsageResult> {
  const supabase = getServiceClient();
  if (!supabase) {
    return {
      configured: false,
      reachable: false,
      rows: [],
      error: 'Supabase 환경 변수가 없습니다.',
    };
  }

  const { data, error } = await supabase.rpc('get_api_usage', { p_days: days });
  if (error) {
    console.error('[kakao-quota] 사용량 조회 실패', error);
    return { configured: true, reachable: false, rows: [], error: error.message };
  }

  return { configured: true, reachable: true, rows: (data ?? []) as UsageRow[] };
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
