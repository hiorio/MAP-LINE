import { describe, expect, it } from 'vitest';
import { OG_HEIGHT, OG_WIDTH, buildStaticMapUrl } from './staticMap';

const center = { lat: 37.4979, lng: 127.0276 };

function params(url: string) {
  return new URL(url).searchParams;
}

describe('buildStaticMapUrl', () => {
  it('중심 좌표를 경도,위도 순서로 넣는다', () => {
    // Local API와 마찬가지로 X가 경도다. 뒤집으면 지도가 엉뚱한 곳을 가리킨다.
    expect(params(buildStaticMapUrl({ center, level: 3 })).get('center')).toBe(
      '127.0276,37.4979',
    );
  });

  it('OG 권장 비율 크기와 2배 스케일을 쓴다', () => {
    const p = params(buildStaticMapUrl({ center, level: 3 }));
    expect(p.get('size')).toBe(`${OG_WIDTH}x${OG_HEIGHT}`);
    expect(p.get('scale')).toBe('2');
    expect(p.get('format')).toBe('png');
  });

  it('마커를 경도,위도 순서로 반복 파라미터로 넣는다', () => {
    const url = buildStaticMapUrl({
      center,
      level: 3,
      markers: [
        { lat: 37.5, lng: 127.0 },
        { lat: 37.6, lng: 127.1 },
      ],
    });
    expect(params(url).getAll('markers')).toEqual([
      'location:127,37.5',
      'location:127.1,37.6',
    ]);
  });

  it('마커는 5개를 넘기지 않는다', () => {
    // 카카오가 최대 5개만 받는다. 더 보내면 요청 자체가 실패한다.
    const markers = Array.from({ length: 9 }, (_, i) => ({ lat: 37 + i / 100, lng: 127 }));
    expect(params(buildStaticMapUrl({ center, level: 3, markers })).getAll('markers')).toHaveLength(5);
  });

  it('마커가 없으면 markers 파라미터를 넣지 않는다', () => {
    expect(params(buildStaticMapUrl({ center, level: 3 })).getAll('markers')).toEqual([]);
  });

  it('줌 레벨을 1~15로 가둔다', () => {
    expect(params(buildStaticMapUrl({ center, level: 0 })).get('lv')).toBe('1');
    expect(params(buildStaticMapUrl({ center, level: 99 })).get('lv')).toBe('15');
    expect(params(buildStaticMapUrl({ center, level: 7 })).get('lv')).toBe('7');
  });

  it('레벨이 숫자가 아니면 기본값으로 돌린다', () => {
    expect(params(buildStaticMapUrl({ center, level: Number.NaN })).get('lv')).toBe('3');
  });
});
