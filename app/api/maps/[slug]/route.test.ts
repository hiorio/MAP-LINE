import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * 편집 권한과 충돌 처리를 HTTP 상태 코드로 정확히 옮기는지 본다.
 * 여기서 403과 409를 헷갈리면 편집기가 잘못된 안내를 띄운다.
 */
const getServiceClient = vi.fn();
vi.mock('@/lib/supabase/server', () => ({
  getServiceClient: () => getServiceClient(),
  isSupabaseConfigured: () => Boolean(getServiceClient()),
}));

const { GET, PATCH, DELETE } = await import('./route');

const params = Promise.resolve({ slug: 'abc12345' });

function rpcClient(result: { data?: unknown; error?: unknown }) {
  return { rpc: async () => ({ data: result.data ?? null, error: result.error ?? null }) };
}

function patchRequest(body: unknown, token?: string) {
  return new Request('http://localhost/api/maps/abc12345', {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { 'X-Edit-Token': token } : {}),
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

beforeEach(() => {
  getServiceClient.mockReset();
});

describe('GET /api/maps/[slug]', () => {
  it('Supabase가 없으면 503', async () => {
    getServiceClient.mockReturnValue(null);
    expect((await GET(new Request('http://localhost'), { params })).status).toBe(503);
  });

  it('없는 지도는 404', async () => {
    getServiceClient.mockReturnValue(rpcClient({ data: null }));
    expect((await GET(new Request('http://localhost'), { params })).status).toBe(404);
  });

  it('문서를 그대로 돌려준다', async () => {
    getServiceClient.mockReturnValue(rpcClient({ data: { slug: 'abc12345', places: [] } }));

    const response = await GET(new Request('http://localhost'), { params });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ slug: 'abc12345', places: [] });
  });
});

describe('PATCH /api/maps/[slug]', () => {
  it('편집 토큰 헤더가 없으면 401', async () => {
    getServiceClient.mockReturnValue(rpcClient({ data: {} }));
    expect((await PATCH(patchRequest({ document: {} }), { params })).status).toBe(401);
  });

  it('본문이 JSON이 아니면 400', async () => {
    getServiceClient.mockReturnValue(rpcClient({ data: {} }));
    expect((await PATCH(patchRequest('not json', 'token'), { params })).status).toBe(400);
  });

  it('document가 없으면 400', async () => {
    getServiceClient.mockReturnValue(rpcClient({ data: {} }));
    expect((await PATCH(patchRequest({ document: null }, 'token'), { params })).status).toBe(400);
  });

  it('토큰이 틀리면 403', async () => {
    getServiceClient.mockReturnValue(rpcClient({ error: { code: 'P0001' } }));
    expect((await PATCH(patchRequest({ document: {} }, 'wrong'), { params })).status).toBe(403);
  });

  it('없는 지도는 404', async () => {
    getServiceClient.mockReturnValue(rpcClient({ error: { code: 'P0002' } }));
    expect((await PATCH(patchRequest({ document: {} }, 'token'), { params })).status).toBe(404);
  });

  it('낙관적 잠금 충돌은 409', async () => {
    // 편집기가 409를 받으면 덮어쓰지 않고 로컬에만 남긴다. 다른 코드면 남의 작업이 날아간다.
    getServiceClient.mockReturnValue(rpcClient({ error: { code: 'P0003' } }));

    const response = await PATCH(patchRequest({ document: {} }, 'token'), { params });
    expect(response.status).toBe(409);
  });

  it('알 수 없는 DB 오류는 502', async () => {
    getServiceClient.mockReturnValue(rpcClient({ error: { code: 'XX000' } }));
    expect((await PATCH(patchRequest({ document: {} }, 'token'), { params })).status).toBe(502);
  });

  it('성공하면 저장된 문서를 돌려준다', async () => {
    getServiceClient.mockReturnValue(rpcClient({ data: { slug: 'abc12345', title: '저장됨' } }));

    const response = await PATCH(patchRequest({ document: { title: '저장됨' } }, 'token'), {
      params,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ title: '저장됨' });
  });
});

describe('DELETE /api/maps/[slug]', () => {
  function deleteClient(result: { data?: unknown[]; error?: unknown }) {
    const chain = {
      delete: () => chain,
      eq: () => chain,
      select: async () => ({ data: result.data ?? null, error: result.error ?? null }),
    };
    return { from: () => chain };
  }

  it('토큰이 없으면 401', async () => {
    getServiceClient.mockReturnValue(deleteClient({ data: [] }));
    const request = new Request('http://localhost', { method: 'DELETE' });
    expect((await DELETE(request, { params })).status).toBe(401);
  });

  it('지운 행이 없으면 403', async () => {
    // 슬러그와 토큰을 함께 조건으로 걸었으므로 0건은 "없거나 권한 없음"이다.
    getServiceClient.mockReturnValue(deleteClient({ data: [] }));
    const request = new Request('http://localhost', {
      method: 'DELETE',
      headers: { 'X-Edit-Token': 'wrong' },
    });
    expect((await DELETE(request, { params })).status).toBe(403);
  });

  it('지워지면 200', async () => {
    getServiceClient.mockReturnValue(deleteClient({ data: [{ slug: 'abc12345' }] }));
    const request = new Request('http://localhost', {
      method: 'DELETE',
      headers: { 'X-Edit-Token': 'right' },
    });
    expect((await DELETE(request, { params })).status).toBe(200);
  });
});
