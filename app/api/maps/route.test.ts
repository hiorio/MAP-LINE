import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * 라우트 핸들러의 입력 검증과 오류 처리만 본다. Supabase는 가짜로 대체한다.
 * 실제 DB 동작은 `lib/map/mapDocument.integration.test.ts`가 덮는다.
 */
const getServiceClient = vi.fn();
vi.mock('@/lib/supabase/server', () => ({
  getServiceClient: () => getServiceClient(),
  isSupabaseConfigured: () => Boolean(getServiceClient()),
}));

const { POST } = await import('./route');

/** insert 결과만 흉내 내는 최소 클라이언트 */
function fakeClient(insert: () => Promise<{ error: unknown }>) {
  return { from: () => ({ insert }) };
}

function request(body: unknown) {
  return new Request('http://localhost/api/maps', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  getServiceClient.mockReset();
});

describe('POST /api/maps', () => {
  it('Supabase가 없으면 503으로 알린다', async () => {
    // 편집기가 이 응답을 보고 로컬 저장으로 물러난다. 500이면 안 된다.
    getServiceClient.mockReturnValue(null);

    const response = await POST(request({}));
    expect(response.status).toBe(503);
  });

  it('본문이 비어도 기본값으로 만든다', async () => {
    let captured: Record<string, unknown> | undefined;
    getServiceClient.mockReturnValue(
      fakeClient(async (row?: unknown) => {
        captured = row as Record<string, unknown>;
        return { error: null };
      }),
    );

    const response = await POST(
      new Request('http://localhost/api/maps', { method: 'POST', body: 'not json' }),
    );

    expect(response.status).toBe(201);
    // 기본 중심은 강남역, 기본 줌은 3
    expect(captured?.center).toBe('POINT(127.0276 37.4979)');
    expect(captured?.zoom_level).toBe(3);
  });

  it('슬러그와 편집 토큰을 돌려준다', async () => {
    getServiceClient.mockReturnValue(fakeClient(async () => ({ error: null })));

    const body = (await (await POST(request({}))).json()) as {
      slug: string;
      editToken: string;
    };

    expect(body.slug).toMatch(/^[23456789abcdefghijkmnpqrstuvwxyz]{8}$/);
    expect(body.editToken).toMatch(/^[0-9a-f]{32}$/);
  });

  it('중심 좌표를 경도 위도 순서의 WKT로 넘긴다', async () => {
    let captured: Record<string, unknown> | undefined;
    getServiceClient.mockReturnValue(
      fakeClient(async (row?: unknown) => {
        captured = row as Record<string, unknown>;
        return { error: null };
      }),
    );

    await POST(request({ center: { lat: 37.5, lng: 127.1 }, zoomLevel: 7 }));

    expect(captured?.center).toBe('POINT(127.1 37.5)');
    expect(captured?.zoom_level).toBe(7);
  });

  it('말이 안 되는 좌표는 기본값으로 되돌린다', async () => {
    let captured: Record<string, unknown> | undefined;
    getServiceClient.mockReturnValue(
      fakeClient(async (row?: unknown) => {
        captured = row as Record<string, unknown>;
        return { error: null };
      }),
    );

    await POST(request({ center: { lat: 999, lng: 'abc' } }));
    expect(captured?.center).toBe('POINT(127.0276 37.4979)');
  });

  it('줌 레벨을 1~14로 가둔다', async () => {
    const captured: unknown[] = [];
    getServiceClient.mockReturnValue(
      fakeClient(async (row?: unknown) => {
        captured.push((row as Record<string, unknown>).zoom_level);
        return { error: null };
      }),
    );

    await POST(request({ zoomLevel: 0 }));
    await POST(request({ zoomLevel: 99 }));
    await POST(request({ zoomLevel: 2.5 }));

    expect(captured).toEqual([1, 14, 3]);
  });

  it('슬러그가 충돌하면 다시 뽑는다', async () => {
    // 8자라 확률은 낮지만 0은 아니다. 한 번 부딪혔다고 실패로 끝내면 안 된다.
    let attempts = 0;
    getServiceClient.mockReturnValue(
      fakeClient(async () => {
        attempts += 1;
        return attempts === 1 ? { error: { code: '23505' } } : { error: null };
      }),
    );

    const response = await POST(request({}));
    expect(response.status).toBe(201);
    expect(attempts).toBe(2);
  });

  it('중복 외의 DB 오류는 재시도하지 않고 502로 끝낸다', async () => {
    let attempts = 0;
    getServiceClient.mockReturnValue(
      fakeClient(async () => {
        attempts += 1;
        return { error: { code: '42P01', message: 'relation does not exist' } };
      }),
    );

    const response = await POST(request({}));
    expect(response.status).toBe(502);
    expect(attempts).toBe(1);
  });
});
