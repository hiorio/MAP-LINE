import { describe, expect, it } from 'vitest';
import { formatDistance } from './types';

describe('formatDistance', () => {
  it('1km 미만은 m로 반올림한다', () => {
    expect(formatDistance(0)).toBe('0m');
    expect(formatDistance(123.4)).toBe('123m');
    expect(formatDistance(999)).toBe('999m');
  });

  it('1km 이상은 소수점 한 자리 km로 쓴다', () => {
    expect(formatDistance(1000)).toBe('1.0km');
    expect(formatDistance(1532)).toBe('1.5km');
    expect(formatDistance(12345)).toBe('12.3km');
  });

  it('말이 안 되는 값은 빈 문자열로 둔다', () => {
    expect(formatDistance(Number.NaN)).toBe('');
    expect(formatDistance(-5)).toBe('');
    expect(formatDistance(Number.POSITIVE_INFINITY)).toBe('');
  });
});
