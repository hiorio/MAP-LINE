import { describe, expect, it } from 'vitest';
import { stopCentroid, type Place, type Stop } from './types';

function place(lat: number, lng: number, name = 'x'): Place {
  return { id: `${lat},${lng}`, name, location: { lat, lng }, pinColor: '#E24B4A' };
}

function stop(candidates: Place[]): Stop {
  return { id: 'stop', candidates };
}

describe('stopCentroid', () => {
  it('후보가 하나면 그 위치를 그대로 쓴다', () => {
    expect(stopCentroid(stop([place(37.5, 127)]))).toEqual({ lat: 37.5, lng: 127 });
  });

  it('후보가 여럿이면 가운데를 낸다', () => {
    // 특정 후보에서 화살표를 뽑으면 나머지 후보가 동선에서 빠진 것처럼 보인다.
    const centroid = stopCentroid(stop([place(37.4, 127.0), place(37.6, 127.2)]));
    expect(centroid?.lat).toBeCloseTo(37.5, 10);
    expect(centroid?.lng).toBeCloseTo(127.1, 10);
  });

  it('세 곳 이상도 평균으로 낸다', () => {
    const centroid = stopCentroid(
      stop([place(37.0, 127.0), place(37.3, 127.0), place(37.6, 127.3)]),
    );
    expect(centroid?.lat).toBeCloseTo(37.3, 10);
    expect(centroid?.lng).toBeCloseTo(127.1, 10);
  });

  it('후보가 없으면 null이다', () => {
    // 화살표를 그릴 기준이 없다. 호출부는 이 단계를 건너뛴다.
    expect(stopCentroid(stop([]))).toBeNull();
  });

  it('같은 좌표만 모여 있으면 그 좌표가 된다', () => {
    const centroid = stopCentroid(stop([place(37.5, 127), place(37.5, 127)]));
    expect(centroid).toEqual({ lat: 37.5, lng: 127 });
  });

  it('음수 좌표에서도 평균이 맞는다', () => {
    const centroid = stopCentroid(stop([place(-10, -20), place(10, 20)]));
    expect(centroid?.lat).toBeCloseTo(0, 10);
    expect(centroid?.lng).toBeCloseTo(0, 10);
  });
});
