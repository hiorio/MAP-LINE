import 'server-only';

/**
 * 카카오 REST API 호출 횟수를 프로세스 안에서 센다.
 *
 * 설계안 §10: 무료 쿼터(경로·정적 지도 각 일 1,000건)는 "추후 별도 안내 전까지"라는
 * 단서가 붙어 있고, 초과분은 우리가 낸다. 소진된 뒤에 알면 늦는다.
 *
 * 한계를 분명히 해 둔다: 이 카운터는 **서버 인스턴스 메모리에만** 있다. Vercel처럼
 * 인스턴스가 여러 개거나 자주 재시작되는 환경에서는 합계가 실제보다 적게 나온다.
 * 카카오 콘솔의 [통계 > 쿼터]가 언제나 정답이고, 이 값은 "지금 이 서버가 얼마나
 * 때리고 있는지"를 로그로 보기 위한 근사치다. 정확한 집계가 필요해지면 Postgres
 * 테이블이나 Redis로 옮긴다.
 */
export type KakaoApi = 'search' | 'staticmap';

/** 카카오가 공지한 일일 무료 쿼터 */
const DAILY_QUOTA: Record<KakaoApi, number> = {
  search: 100_000,
  staticmap: 1_000,
};

/** 이 비율을 넘으면 경고 로그를 남긴다 */
const WARN_RATIO = 0.8;

interface DayCount {
  day: string;
  counts: Record<KakaoApi, number>;
  warned: Partial<Record<KakaoApi, boolean>>;
}

let state: DayCount = freshDay();

function freshDay(): DayCount {
  return { day: today(), counts: { search: 0, staticmap: 0 }, warned: {} };
}

/** 쿼터는 KST 자정에 초기화된다고 보고 맞춘다. */
function today(): string {
  return new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

export function recordKakaoCall(api: KakaoApi): void {
  if (state.day !== today()) state = freshDay();

  const used = (state.counts[api] += 1);
  const quota = DAILY_QUOTA[api];

  if (!state.warned[api] && used >= quota * WARN_RATIO) {
    state.warned[api] = true;
    console.warn(
      `[kakao-quota] ${api} 사용량이 일일 무료 쿼터의 ${Math.round(WARN_RATIO * 100)}%를 넘었습니다 ` +
        `(${used}/${quota}). 카카오 콘솔 > 통계 > 쿼터에서 실제 사용량을 확인하세요.`,
    );
  }
}

export function readUsage() {
  if (state.day !== today()) state = freshDay();
  return {
    day: state.day,
    // 이 서버 인스턴스 기준이라는 점을 응답에도 남긴다.
    scope: 'this-server-instance' as const,
    apis: (Object.keys(DAILY_QUOTA) as KakaoApi[]).map((api) => ({
      api,
      used: state.counts[api],
      quota: DAILY_QUOTA[api],
      ratio: Number((state.counts[api] / DAILY_QUOTA[api]).toFixed(4)),
    })),
  };
}
