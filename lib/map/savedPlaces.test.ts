import { describe, expect, it } from 'vitest';
import { isSamePlace, type SavedPlace } from './savedPlaces';

function saved(overrides: Partial<SavedPlace> = {}): SavedPlace {
  return {
    id: 'saved-1',
    name: '스타벅스 강남대로점',
    kakaoPlaceId: '12345',
    location: { lat: 37.4979, lng: 127.0276 },
    savedAt: '2026-08-02T00:00:00.000Z',
    ...overrides,
  };
}

describe('isSamePlace', () => {
  it('카카오에서 온 장소는 kakaoPlaceId로 판단한다', () => {
    // 상호명은 바뀔 수 있고 좌표도 갱신될 수 있다. 식별자가 유일하게 믿을 값이다.
    const existing = saved();
    expect(
      isSamePlace(
        { name: '스타벅스 강남대로점(리뉴얼)', kakaoPlaceId: '12345', location: { lat: 37.5, lng: 127.1 } },
        existing,
      ),
    ).toBe(true);
  });

  it('kakaoPlaceId가 다르면 이름이 같아도 다른 곳이다', () => {
    // 프랜차이즈는 같은 이름이 전국에 있다.
    expect(
      isSamePlace(
        { name: '스타벅스 강남대로점', kakaoPlaceId: '99999', location: { lat: 37.4979, lng: 127.0276 } },
        saved(),
      ),
    ).toBe(false);
  });

  it('식별자가 없으면 이름과 좌표로 판단한다', () => {
    // 지도를 직접 찍어 만든 장소에는 kakaoPlaceId가 없다.
    const manual = saved({ kakaoPlaceId: undefined, name: '여기 골목' });
    expect(
      isSamePlace({ name: '여기 골목', location: { lat: 37.4979, lng: 127.0276 } }, manual),
    ).toBe(true);
  });

  it('좌표가 미세하게 달라도 같은 곳으로 본다', () => {
    // 화면에서 찍은 좌표는 부동소수라 정확히 같기를 기대할 수 없다.
    const manual = saved({ kakaoPlaceId: undefined, name: '여기 골목' });
    expect(
      isSamePlace({ name: '여기 골목', location: { lat: 37.49791, lng: 127.02761 } }, manual),
    ).toBe(true);
  });

  it('좌표가 충분히 멀면 다른 곳이다', () => {
    const manual = saved({ kakaoPlaceId: undefined, name: '여기 골목' });
    expect(
      isSamePlace({ name: '여기 골목', location: { lat: 37.51, lng: 127.0276 } }, manual),
    ).toBe(false);
  });

  it('이름이 다르면 다른 곳이다', () => {
    const manual = saved({ kakaoPlaceId: undefined, name: '여기 골목' });
    expect(
      isSamePlace({ name: '저기 골목', location: { lat: 37.4979, lng: 127.0276 } }, manual),
    ).toBe(false);
  });

  it('한쪽에만 식별자가 있으면 이름과 좌표로 판단한다', () => {
    expect(
      isSamePlace({ name: '스타벅스 강남대로점', location: { lat: 37.4979, lng: 127.0276 } }, saved()),
    ).toBe(true);
  });
});
