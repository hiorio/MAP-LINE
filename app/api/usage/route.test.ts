import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * 이 경로는 상태를 보러 오는 곳이다. DB에 닿지 못했는데 200에 빈 목록을 주면
 * "아직 아무도 안 썼다"와 구분할 수 없고, 실제로 그것 때문에 잘못된 자격 증명을
 * 정상이라고 오판한 적이 있다.
 */
const readUsage = vi.fn();
const lastRecordFailure = vi.fn(() => null as { at: string; message: string } | null);

vi.mock('@/lib/kakao/usage', () => ({
  readUsage: (days: number) => readUsage(days),
  lastRecordFailure: () => lastRecordFailure(),
  summarizeToday: (rows: unknown[]) => rows,
}));

const { GET } = await import('./route');

const request = (query = '') => new Request(`http://localhost/api/usage${query}`);

beforeEach(() => {
  readUsage.mockReset();
  lastRecordFailure.mockReset();
  lastRecordFailure.mockReturnValue(null);
});

describe('GET /api/usage', () => {
  it('환경 변수가 없으면 503으로 알린다', async () => {
    readUsage.mockResolvedValue({
      configured: false,
      reachable: false,
      rows: [],
      error: 'Supabase 환경 변수가 없습니다.',
    });

    const response = await GET(request());
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ status: 'unconfigured' });
  });

  it('DB에 닿지 못하면 502를 준다', async () => {
    // 여기서 200을 주면 장애가 "사용량 0"으로 위장된다.
    readUsage.mockResolvedValue({
      configured: true,
      reachable: false,
      rows: [],
      error: 'connection refused',
    });

    const response = await GET(request());
    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({
      status: 'unreachable',
      error: 'connection refused',
    });
  });

  it('사용량이 0이어도 닿았으면 200이다', async () => {
    readUsage.mockResolvedValue({ configured: true, reachable: true, rows: [] });

    const response = await GET(request());
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: 'ok', history: [] });
  });

  it('기록이 실패한 적 있으면 함께 알린다', async () => {
    // 집계가 멈춘 동안 화면의 사용량은 실제보다 적다. 그 사실이 응답에 보여야 한다.
    readUsage.mockResolvedValue({ configured: true, reachable: true, rows: [] });
    lastRecordFailure.mockReturnValue({ at: '2026-08-02T00:00:00Z', message: 'boom' });

    const body = (await (await GET(request())).json()) as { recordFailure?: unknown };
    expect(body.recordFailure).toEqual({ at: '2026-08-02T00:00:00Z', message: 'boom' });
  });

  it('기록 실패가 없으면 그 키를 넣지 않는다', async () => {
    readUsage.mockResolvedValue({ configured: true, reachable: true, rows: [] });

    const body = await (await GET(request())).json();
    expect(body).not.toHaveProperty('recordFailure');
  });

  it('days 파라미터를 넘기고, 숫자가 아니면 기본값을 쓴다', async () => {
    readUsage.mockResolvedValue({ configured: true, reachable: true, rows: [] });

    await GET(request('?days=30'));
    expect(readUsage).toHaveBeenLastCalledWith(30);

    await GET(request('?days=abc'));
    expect(readUsage).toHaveBeenLastCalledWith(7);
  });
});
