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

  it('마커 파라미터를 절대 넣지 않는다', () => {
    // markers를 넘기면 카카오가 center를 무시하고 마커에 맞춰 지도를 다시 잡는다.
    // 지도를 만든 사람이 맞춰 둔 화면이 통째로 어긋나므로 핀은 직접 합성한다.
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
