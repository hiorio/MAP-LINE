import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
const getServiceClient = vi.fn<() => { rpc: typeof rpc } | null>();

vi.mock('@/lib/supabase/server', () => ({
  getServiceClient: () => getServiceClient(),
  isSupabaseConfigured: () => Boolean(getServiceClient()),
}));

const { CREATE_MAP_LIMIT, checkRateLimit, clientIp, tooManyRequests } = await import('./rateLimit');

function request(headers: Record<string, string> = {}) {
  return new Request('http://localhost/api/maps', { method: 'POST', headers });
}

beforeEach(() => {
  rpc.mockReset();
  getServiceClient.mockReset();
  getServiceClient.mockReturnValue({ rpc });
});

describe('clientIp', () => {
  it('x-forwarded-for의 맨 앞을 쓴다', () => {
    // 프록시를 여러 번 거치면 목록이 되고, 원래 클라이언트가 맨 앞이다.
    expect(clientIp(request({ 'x-forwarded-for': '203.0.113.7, 10.0.0.1, 10.0.0.2' }))).toBe(
      '203.0.113.7',
    );
  });

  it('공백을 정리한다', () => {
    expect(clientIp(request({ 'x-forwarded-for': '  203.0.113.7 ' }))).toBe('203.0.113.7');
  });

  it('x-real-ip로 넘어간다', () => {
    expect(clientIp(request({ 'x-real-ip': '198.51.100.9' }))).toBe('198.51.100.9');
  });

  it('아무것도 없으면 unknown이다', () => {
    // 한 바구니에 몰리지만, 헤더가 없는 환경은 프록시 뒤가 아니라는 뜻이다.
    expect(clientIp(request())).toBe('unknown');
  });
});

describe('checkRateLimit', () => {
  const ip = { 'x-forwarded-for': '203.0.113.7' };

  it('한도 안이면 통과시킨다', async () => {
    rpc.mockResolvedValue({ data: CREATE_MAP_LIMIT.limit, error: null });
    expect((await checkRateLimit(request(ip), CREATE_MAP_LIMIT)).allowed).toBe(true);
  });

  it('한도를 넘으면 막는다', async () => {
    rpc.mockResolvedValue({ data: CREATE_MAP_LIMIT.limit + 1, error: null });
    expect((await checkRateLimit(request(ip), CREATE_MAP_LIMIT)).allowed).toBe(false);
  });

  it('IP와 규칙 이름으로 바구니를 나눈다', async () => {
    // 경로가 서로의 한도를 잡아먹으면 검색 몇 번에 지도 생성이 막힌다.
    rpc.mockResolvedValue({ data: 1, error: null });
    await checkRateLimit(request(ip), CREATE_MAP_LIMIT);

    expect(rpc).toHaveBeenCalledWith('bump_rate_limit', {
      p_bucket: 'create-map:203.0.113.7',
      p_window_seconds: CREATE_MAP_LIMIT.windowSeconds,
    });
  });

  it('셀 수 없으면 통과시킨다', async () => {
    // 제한 장치가 고장 났다고 제품이 멈추면 안 된다.
    rpc.mockResolvedValue({ data: null, error: { message: 'boom' } });
    expect((await checkRateLimit(request(ip), CREATE_MAP_LIMIT)).allowed).toBe(true);
  });

  it('Supabase가 없으면 통과시킨다', async () => {
    getServiceClient.mockReturnValue(null);
    expect((await checkRateLimit(request(ip), CREATE_MAP_LIMIT)).allowed).toBe(true);
  });
});

describe('tooManyRequests', () => {
  it('429와 Retry-After를 준다', async () => {
    const response = tooManyRequests(CREATE_MAP_LIMIT);

    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe(String(CREATE_MAP_LIMIT.windowSeconds));
    expect(await response.json()).toMatchObject({
      retryAfterSeconds: CREATE_MAP_LIMIT.windowSeconds,
    });
  });
});
