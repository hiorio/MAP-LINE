import { afterEach, describe, expect, it, vi } from 'vitest';
import { findNearby, toAddressLookup, toNearbyCandidate } from './nearby';

vi.mock('./usage', () => ({ recordKakaoCall: vi.fn() }));

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

function kakaoResponse(documents: object[] = []) {
  return Promise.resolve(new Response(JSON.stringify({ documents }), { status: 200 }));
}

describe('toAddressLookup', () => {
  it('도로명 주소와 건물명을 함께 읽는다', () => {
    expect(
      toAddressLookup({
        road_address: {
          address_name: '서울 강남구 선릉로 757',
          building_name: '더채플앳청담',
        },
        address: { address_name: '서울 강남구 논현동 94-9' },
      }),
    ).toEqual({ address: '서울 강남구 선릉로 757', buildingName: '더채플앳청담' });
  });

  it('건물명이 비어 있으면 주소만 돌려준다', () => {
    expect(
      toAddressLookup({
        road_address: { address_name: '', building_name: '  ' },
        address: { address_name: '서울 강남구 논현동 94-9' },
      }),
    ).toEqual({ address: '서울 강남구 논현동 94-9' });
  });

  it('건물명이 있으면 그 이름으로 주변 키워드 검색을 한 번 더 한다', async () => {
    vi.stubEnv('KAKAO_REST_KEY', 'test-key');
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() =>
        kakaoResponse([
          {
            road_address: {
              address_name: '서울 강남구 선릉로 757',
              building_name: '더채플앳청담',
            },
          },
        ]),
      )
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() =>
        kakaoResponse([
          {
            id: 'wedding-1',
            place_name: '더채플앳청담',
            category_name: '가정,생활 > 결혼 > 예식장',
            x: '127.041',
            y: '37.521',
            distance: '18',
          },
        ]),
      );
    vi.stubGlobal('fetch', fetchMock);

    const result = await findNearby({ lat: 37.521, lng: 127.041 });

    expect(fetchMock).toHaveBeenCalledTimes(5);
    const keywordURL = new URL(String(fetchMock.mock.calls[4]?.[0]));
    expect(keywordURL.pathname).toContain('/search/keyword.json');
    expect(keywordURL.searchParams.get('query')).toBe('더채플앳청담');
    expect(result.places[0]?.name).toBe('더채플앳청담');
  });

  it('카테고리 후보를 최대 15개 요청한다', async () => {
    vi.stubEnv('KAKAO_REST_KEY', 'test-key');
    const fetchMock = vi.fn((_input: unknown) => kakaoResponse());
    vi.stubGlobal('fetch', fetchMock);

    await findNearby({ lat: 37.4979, lng: 127.0276 });

    const categoryURLs = fetchMock.mock.calls
      .map((call) => new URL(String(call[0])))
      .filter((url) => url.pathname.includes('/search/category.json'));
    expect(categoryURLs).toHaveLength(3);
    expect(categoryURLs.every((url) => url.searchParams.get('size') === '15')).toBe(true);
  });

  it('최종 네 곳으로 자르기 전에 사용자가 누른 POI를 전체 후보에서 찾는다', async () => {
    vi.stubEnv('KAKAO_REST_KEY', 'test-key');
    const cafes = Array.from({ length: 8 }, (_, index) => ({
      id: index === 7 ? 'tapped-starbucks' : `cafe-${index}`,
      place_name: index === 7 ? '스타벅스 강남역7번출구점' : `가까운 카페 ${index}`,
      category_group_name: '카페',
      x: String(127.0276 + index * 0.00001),
      y: '37.4979',
      distance: String(index + 1),
    }));
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() => kakaoResponse(cafes))
      .mockImplementationOnce(() => kakaoResponse());
    vi.stubGlobal('fetch', fetchMock);

    const result = await findNearby(
      { lat: 37.4979, lng: 127.0276 },
      'tapped-starbucks',
    );

    expect(result.tappedPlace?.name).toBe('스타벅스 강남역7번출구점');
    expect(result.places).toHaveLength(4);
    expect(result.places[0]?.kakaoPlaceId).toBe('tapped-starbucks');
  });

  it('POI id가 일치하지 않으면 가까운 장소를 누른 장소라고 확정하지 않는다', async () => {
    vi.stubEnv('KAKAO_REST_KEY', 'test-key');
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() =>
        kakaoResponse([
          {
            id: 'nearby-restaurant',
            place_name: '홍할머니떡볶이',
            x: '127.0276',
            y: '37.4979',
            distance: '18',
          },
        ]),
      )
      .mockImplementationOnce(() => kakaoResponse())
      .mockImplementationOnce(() => kakaoResponse());
    vi.stubGlobal('fetch', fetchMock);

    const result = await findNearby(
      { lat: 37.4979, lng: 127.0276 },
      'unrelated-native-map-id',
    );

    expect(result.tappedPlace).toBeUndefined();
    expect(result.places[0]?.name).toBe('홍할머니떡볶이');
  });
});

describe('toNearbyCandidate', () => {
  const document = {
    id: '111',
    place_name: '마리김밥',
    address_name: '서울 서초구 서초동 1373',
    road_address_name: '서울 서초구 강남대로 지하 396',
    category_group_name: '음식점',
    x: '127.0276',
    y: '37.4979',
    distance: '5',
  };

  it('x를 경도로, y를 위도로 읽는다', () => {
    expect(toNearbyCandidate(document)?.location).toEqual({ lat: 37.4979, lng: 127.0276 });
  });

  it('거리를 숫자로 읽는다', () => {
    // 꾹 누른 지점에서 얼마나 떨어졌는지가 어느 가게인지 고르는 근거다.
    expect(toNearbyCandidate(document)?.distanceM).toBe(5);
  });

  it('이름이나 좌표가 없으면 버린다', () => {
    expect(toNearbyCandidate({ ...document, place_name: undefined })).toBeNull();
    expect(toNearbyCandidate({ ...document, x: undefined })).toBeNull();
  });

  it('좌표가 숫자가 아니면 버린다', () => {
    expect(toNearbyCandidate({ ...document, y: 'N/A' })).toBeNull();
  });

  it('선택 필드가 없으면 키 자체를 넣지 않는다', () => {
    expect(toNearbyCandidate({ id: '1', place_name: '이름만', x: '127', y: '37' })).toEqual({
      kakaoPlaceId: '1',
      name: '이름만',
      location: { lat: 37, lng: 127 },
    });
  });
});
