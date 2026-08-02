import { describe, expect, it } from 'vitest';
import {
  FADE_FREE_LEVELS,
  SCALE_CLAMP_MAX,
  SCALE_CLAMP_MIN,
  fromKakaoXY,
  strokeRenderAlpha,
  strokeRenderWidth,
  toGeoJsonLineString,
  toWkbPoint,
} from './projection';

describe('fromKakaoXY', () => {
  it('x를 경도로, y를 위도로 읽는다', () => {
    // Kakao Local API 응답 형태 그대로 (문자열)
    expect(fromKakaoXY('127.0276', '37.4979')).toEqual({ lat: 37.4979, lng: 127.0276 });
  });

  it('숫자 입력도 처리한다', () => {
    expect(fromKakaoXY(127, 37)).toEqual({ lat: 37, lng: 127 });
  });
});

describe('PostGIS 직렬화', () => {
  it('POINT는 경도 위도 순서다', () => {
    expect(toWkbPoint({ lat: 37.4979, lng: 127.0276 })).toBe('POINT(127.0276 37.4979)');
  });

  it('GeoJSON LineString도 경도 위도 순서다', () => {
    expect(toGeoJsonLineString([{ lat: 37.5, lng: 127 }, { lat: 37.6, lng: 127.1 }])).toEqual({
      type: 'LineString',
      coordinates: [
        [127, 37.5],
        [127.1, 37.6],
      ],
    });
  });
});

describe('strokeRenderWidth', () => {
  it('같은 줌에서는 원래 굵기를 유지한다', () => {
    expect(strokeRenderWidth(4, 5, 5)).toBe(4);
  });

  it('축소할수록 얇아지되 하한 아래로는 내려가지 않는다', () => {
    expect(strokeRenderWidth(4, 3, 4)).toBeLessThan(4);
    // 줌 3에서 그린 획을 줌 10에서 보면 지리 비율상 1/128이지만 하한이 막는다
    expect(strokeRenderWidth(4, 3, 10)).toBeCloseTo(4 * SCALE_CLAMP_MIN);
  });

  it('확대해도 상한 이상으로 두꺼워지지 않는다', () => {
    expect(strokeRenderWidth(4, 10, 1)).toBeCloseTo(4 * SCALE_CLAMP_MAX);
  });

  it('굵기 보정은 단조적이다', () => {
    const widths = [1, 3, 5, 7, 9].map((level) => strokeRenderWidth(4, 5, level));
    for (let i = 1; i < widths.length; i++) {
      expect(widths[i]!).toBeLessThanOrEqual(widths[i - 1]!);
    }
  });
});

describe('strokeRenderAlpha', () => {
  it('그린 줌 근처에서는 완전히 불투명하다', () => {
    expect(strokeRenderAlpha(5, 5)).toBe(1);
    expect(strokeRenderAlpha(5, 5 + FADE_FREE_LEVELS)).toBe(1);
    expect(strokeRenderAlpha(5, 5 - FADE_FREE_LEVELS)).toBe(1);
  });

  it('줌 차이가 커지면 흐려진다', () => {
    expect(strokeRenderAlpha(5, 9)).toBeLessThan(1);
    expect(strokeRenderAlpha(5, 9)).toBe(strokeRenderAlpha(5, 1));
  });

  it('완전히 사라지지는 않는다', () => {
    expect(strokeRenderAlpha(1, 14)).toBeGreaterThanOrEqual(0.35);
  });
});
