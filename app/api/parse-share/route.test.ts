import { beforeEach, describe, expect, it, vi } from 'vitest';

const searchAddress = vi.fn();
const searchPlaces = vi.fn();

vi.mock('@/lib/kakao/localSearch', () => ({
  MissingRestKeyError: class MissingRestKeyError extends Error {},
  searchAddress: (...args: unknown[]) => searchAddress(...args),
  searchPlaces: (...args: unknown[]) => searchPlaces(...args),
}));

vi.mock('@/lib/rateLimit', () => ({
  SEARCH_LIMIT: { key: 'search', max: 100 },
  checkRateLimit: async () => ({ allowed: true }),
  tooManyRequests: () => new Response(null, { status: 429 }),
}));

const { POST } = await import('./route');

function request(text: string) {
  return new Request('http://localhost/api/parse-share', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
}

function place(name: string, lat: number, lng: number) {
  return { kakaoPlaceId: '', name, address: `${name} 주소`, location: { lat, lng } };
}

beforeEach(() => {
  searchAddress.mockReset();
  searchPlaces.mockReset();
  searchAddress.mockImplementation(async (address: string) => [place(`정확:${address}`, 37.5, 127)]);
  searchPlaces.mockImplementation(async (query: string) => [place(`검색:${query}`, 37.6, 127.1)]);
});

describe('POST /api/parse-share', () => {
  it('여러 주소를 각각 검색하고 장소별 묶음으로 돌려준다', async () => {
    const response = await POST(
      request(['장소 A', '서울특별시 강남구 길 1', '장소 B', '서울특별시 마포구 길 2'].join('\n')),
    );
    const body = (await response.json()) as { groups: { places: { name: string }[] }[] };

    expect(response.status).toBe(200);
    expect(searchAddress).toHaveBeenCalledTimes(2);
    expect(searchPlaces).toHaveBeenCalledTimes(2);
    expect(body.groups).toHaveLength(2);
    // 정확 주소 결과가 첫 후보이며 이름은 공유 원문의 장소명을 유지한다.
    expect(body.groups[0]?.places[0]?.name).toBe('장소 A');
    expect(body.groups[1]?.places[0]?.name).toBe('장소 B');
  });

  it('한 요청에서 최대 열 곳까지만 처리한다', async () => {
    const text = Array.from({ length: 12 }, (_, index) => [
      `장소 ${index}`,
      `서울특별시 강남구 테헤란로 ${index + 1}`,
    ]).flat().join('\n');

    const response = await POST(request(text));
    const body = (await response.json()) as { groups: unknown[] };
    expect(body.groups).toHaveLength(10);
    expect(searchAddress).toHaveBeenCalledTimes(10);
  });

  it('장소 목록이 없는 카카오맵 그룹 공유를 장소명으로 검색하지 않는다', async () => {
    const response = await POST(
      request(
        ['[카카오맵] 음식점 그룹', '[카카오맵] 음식점 그룹', 'https://kko.to/DzukR3dcsd0'].join('\n'),
      ),
    );
    const body = (await response.json()) as { error: string };

    expect(response.status).toBe(422);
    expect(body.error).toContain('장소 목록이 포함되지 않아');
    expect(searchAddress).not.toHaveBeenCalled();
    expect(searchPlaces).not.toHaveBeenCalled();
  });
});
