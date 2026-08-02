import { describe, expect, it } from 'vitest';
import { toNearbyCandidate } from './nearby';

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
