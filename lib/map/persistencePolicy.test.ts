import { describe, expect, it } from 'vitest';
import { stripNonPersistableRouteCaches } from './persistencePolicy';

describe('stripNonPersistableRouteCaches', () => {
  it('자동차 선택은 남기고 외부 길찾기 결과만 제거한다', () => {
    const route = { points: [{ lat: 37.5, lng: 127 }], distanceM: 10, durationS: 20 };
    const input = { title: '여행', legs: [{ mode: 'car', route }] };

    expect(stripNonPersistableRouteCaches(input)).toEqual({
      title: '여행',
      legs: [{ mode: 'car' }],
    });
    expect(input.legs[0]?.route).toBe(route);
  });

  it('다른 이동수단의 허용된 경로 캐시는 보존한다', () => {
    const route = { points: [{ lat: 37.5, lng: 127 }] };
    const input = { legs: [{ mode: 'walk', route }, { mode: 'straight' }] };
    expect(stripNonPersistableRouteCaches(input)).toEqual(input);
  });

  it('legs가 없는 불완전 문서도 그대로 통과시킨다', () => {
    const input = { title: '빈 지도' };
    expect(stripNonPersistableRouteCaches(input)).toBe(input);
  });
});
