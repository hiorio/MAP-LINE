import { describe, expect, it } from 'vitest';
import { DAILY_QUOTA, summarizeToday, type UsageRow } from './usage';

/** KST 기준 오늘 날짜. 집계도 KST로 끊는다 — 카카오 쿼터가 KST 자정에 초기화된다. */
function todayKst() {
  return new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

describe('summarizeToday', () => {
  it('기록이 없으면 0으로 채운다', () => {
    const summary = summarizeToday([]);
    expect(summary).toHaveLength(Object.keys(DAILY_QUOTA).length);
    expect(summary.every((row) => row.used === 0 && row.ratio === 0)).toBe(true);
  });

  it('오늘 기록만 집계한다', () => {
    const rows: UsageRow[] = [
      { day: todayKst(), api: 'staticmap', calls: 40 },
      { day: '2020-01-01', api: 'staticmap', calls: 999 },
    ];
    const staticmap = summarizeToday(rows).find((row) => row.api === 'staticmap');
    expect(staticmap?.used).toBe(40);
  });

  it('쿼터 대비 비율을 계산한다', () => {
    const rows: UsageRow[] = [{ day: todayKst(), api: 'staticmap', calls: 250 }];
    const staticmap = summarizeToday(rows).find((row) => row.api === 'staticmap');
    expect(staticmap?.quota).toBe(1000);
    expect(staticmap?.ratio).toBe(0.25);
  });

  it('80%를 넘으면 경고 표시를 켠다', () => {
    const below: UsageRow[] = [{ day: todayKst(), api: 'staticmap', calls: 799 }];
    const at: UsageRow[] = [{ day: todayKst(), api: 'staticmap', calls: 800 }];

    expect(summarizeToday(below).find((r) => r.api === 'staticmap')?.warn).toBe(false);
    expect(summarizeToday(at).find((r) => r.api === 'staticmap')?.warn).toBe(true);
  });

  it('API마다 쿼터가 따로다', () => {
    // 검색은 넉넉하고 정적 지도가 빠듯하다. 같은 호출 수라도 위험도가 다르다.
    const rows: UsageRow[] = [
      { day: todayKst(), api: 'search', calls: 900 },
      { day: todayKst(), api: 'staticmap', calls: 900 },
    ];
    const summary = summarizeToday(rows);
    expect(summary.find((r) => r.api === 'search')?.warn).toBe(false);
    expect(summary.find((r) => r.api === 'staticmap')?.warn).toBe(true);
  });
});
