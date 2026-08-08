import { beforeEach, describe, expect, it, vi } from 'vitest';

const findMidpoint = vi.fn();

vi.mock('@/lib/midpoint/findMidpoint', () => ({
  NoMeetingPlaceError: class NoMeetingPlaceError extends Error {},
  NotEnoughParticipantsError: class NotEnoughParticipantsError extends Error {},
  findMidpoint: (...args: unknown[]) => findMidpoint(...args),
}));

vi.mock('@/lib/rateLimit', () => ({
  MIDPOINT_LIMIT: { name: 'midpoint', limit: 10, windowSeconds: 600 },
  checkRateLimit: async () => ({ allowed: true }),
  tooManyRequests: () => new Response(null, { status: 429 }),
}));

const { POST } = await import('./route');

function request(modes: string[]) {
  return new Request('http://localhost/api/midpoint', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      participants: modes.map((mode, index) => ({
        id: `p${index}`,
        name: `친구 ${index + 1}`,
        location: { lat: 37.5 + index * 0.01, lng: 127 + index * 0.01 },
        mode,
      })),
    }),
  });
}

beforeEach(() => {
  findMidpoint.mockReset();
  findMidpoint.mockResolvedValue({
    center: { lat: 37.505, lng: 127.005 },
    searchRadiusM: 1_000,
    candidates: [],
  });
});

describe('POST /api/midpoint', () => {
  it('참가자마다 자동차와 다른 이동수단을 함께 받을 수 있다', async () => {
    const response = await POST(request(['car', 'transit', 'walk']));

    expect(response.status).toBe(200);
    expect(findMidpoint).toHaveBeenCalledOnce();
    expect(findMidpoint.mock.calls[0]?.[0]).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'p0', mode: 'car' }),
        expect.objectContaining({ id: 'p1', mode: 'transit' }),
      ]),
    );
  });

  it('실제 이동수단이 아닌 직선 모드는 거절한다', async () => {
    const response = await POST(request(['straight', 'transit']));

    expect(response.status).toBe(400);
    expect(findMidpoint).not.toHaveBeenCalled();
  });
});
