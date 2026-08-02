import { describe, expect, it } from 'vitest';
import { readCenterParams } from './searchParams';

describe('readCenterParams', () => {
  it('문자열 좌표를 숫자로 읽는다', () => {
    expect(readCenterParams('37.4979', '127.0276')).toEqual({ lat: 37.4979, lng: 127.0276 });
  });

  it('값이 없으면 undefined를 돌려준다', () => {
    // 기준점 없이 정확도순으로 검색하게 된다. 오류가 아니다.
    expect(readCenterParams(null, null)).toBeUndefined();
    expect(readCenterParams(undefined, undefined)).toBeUndefined();
    expect(readCenterParams('37.5', null)).toBeUndefined();
  });

  it('숫자가 아니면 버린다', () => {
    expect(readCenterParams('abc', '127')).toBeUndefined();
  });

  it('빈 값을 좌표 0,0으로 통과시키지 않는다', () => {
    // Number('')도 Number(null)도 0이라 방심하면 기니만 앞바다가 기준점이 된다.
    expect(readCenterParams('', '')).toBeUndefined();
    expect(readCenterParams('   ', '127')).toBeUndefined();
    expect(readCenterParams(null, 0)).toBeUndefined();
  });

  it('진짜 0은 통과시킨다', () => {
    expect(readCenterParams(0, 0)).toEqual({ lat: 0, lng: 0 });
    expect(readCenterParams('0', '0')).toEqual({ lat: 0, lng: 0 });
  });

  it('지구 밖 좌표는 버린다', () => {
    // 클라이언트가 보내는 값이므로 그대로 믿지 않는다.
    expect(readCenterParams('91', '127')).toBeUndefined();
    expect(readCenterParams('37', '181')).toBeUndefined();
  });

  it('경계값은 통과시킨다', () => {
    expect(readCenterParams('90', '180')).toEqual({ lat: 90, lng: 180 });
    expect(readCenterParams('-90', '-180')).toEqual({ lat: -90, lng: -180 });
  });
});
