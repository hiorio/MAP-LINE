import { describe, expect, it } from 'vitest';
import { toCandidate } from './localSearch';

describe('toCandidate', () => {
  const document = {
    id: '1234567',
    place_name: '스타벅스 강남대로점',
    address_name: '서울 강남구 역삼동 825-20',
    road_address_name: '서울 강남구 강남대로 390',
    category_group_name: '카페',
    x: '127.0276',
    y: '37.4979',
  };

  it('x를 경도로, y를 위도로 읽는다', () => {
    expect(toCandidate(document)?.location).toEqual({ lat: 37.4979, lng: 127.0276 });
  });

  it('필요한 필드를 옮겨 담는다', () => {
    expect(toCandidate(document)).toEqual({
      kakaoPlaceId: '1234567',
      name: '스타벅스 강남대로점',
      address: '서울 강남구 역삼동 825-20',
      roadAddress: '서울 강남구 강남대로 390',
      category: '카페',
      location: { lat: 37.4979, lng: 127.0276 },
    });
  });

  it('이름이나 좌표가 없으면 버린다', () => {
    expect(toCandidate({ ...document, place_name: undefined })).toBeNull();
    expect(toCandidate({ ...document, x: undefined })).toBeNull();
    expect(toCandidate({ ...document, y: undefined })).toBeNull();
  });

  it('좌표가 숫자가 아니면 버린다', () => {
    expect(toCandidate({ ...document, x: 'N/A' })).toBeNull();
  });

  it('선택 필드가 비어 있으면 키 자체를 넣지 않는다', () => {
    const result = toCandidate({
      id: '1',
      place_name: '이름만 있는 곳',
      x: '127',
      y: '37',
    });
    expect(result).toEqual({
      kakaoPlaceId: '1',
      name: '이름만 있는 곳',
      location: { lat: 37, lng: 127 },
    });
  });

  it('category_group_name이 없으면 category_name으로 대체한다', () => {
    const result = toCandidate({ ...document, category_group_name: '', category_name: '음식점 > 카페' });
    expect(result?.category).toBe('음식점 > 카페');
  });

  it('기준 좌표를 넘겼을 때만 오는 distance를 숫자로 읽는다', () => {
    expect(toCandidate({ ...document, distance: '1532' })?.distanceM).toBe(1532);
  });

  it('distance가 없으면 키 자체를 넣지 않는다', () => {
    expect(toCandidate(document)).not.toHaveProperty('distanceM');
    expect(toCandidate({ ...document, distance: '' })).not.toHaveProperty('distanceM');
  });
});
