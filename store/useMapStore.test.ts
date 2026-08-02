import { beforeEach, describe, expect, it } from 'vitest';
import type { Stroke } from '@/lib/map/types';
import { createLabel, createPlace, placeFromCandidate, useMapStore } from './useMapStore';

function stroke(id: string): Stroke {
  return {
    id,
    path: [
      { lat: 37.5, lng: 127 },
      { lat: 37.51, lng: 127.01 },
    ],
    color: '#E24B4A',
    width: 4,
    zoomCreated: 3,
  };
}

const initial = useMapStore.getState();

beforeEach(() => {
  useMapStore.setState({
    ...initial,
    places: [],
    strokes: [],
    labels: [],
    history: [],
    saveState: 'idle',
  });
});

describe('획 편집과 되돌리기', () => {
  it('획을 추가하면 dirty가 되고 히스토리가 쌓인다', () => {
    useMapStore.getState().addStroke(stroke('a'));

    expect(useMapStore.getState().strokes).toHaveLength(1);
    expect(useMapStore.getState().saveState).toBe('dirty');
    expect(useMapStore.getState().history).toHaveLength(1);
  });

  it('되돌리기는 직전 상태로 돌아간다', () => {
    const store = useMapStore.getState();
    store.addStroke(stroke('a'));
    store.addStroke(stroke('b'));
    useMapStore.getState().undo();

    expect(useMapStore.getState().strokes.map((s) => s.id)).toEqual(['a']);
  });

  it('지우개로 가운데 획을 지운 뒤 되돌리면 그 획이 제자리로 돌아온다', () => {
    // 설계안의 "pop 방식"은 여기서 엉뚱한 획을 되살린다. 스냅샷을 쓰는 이유다.
    const store = useMapStore.getState();
    store.addStroke(stroke('a'));
    store.addStroke(stroke('b'));
    store.addStroke(stroke('c'));

    useMapStore.getState().removeStroke('b');
    expect(useMapStore.getState().strokes.map((s) => s.id)).toEqual(['a', 'c']);

    useMapStore.getState().undo();
    expect(useMapStore.getState().strokes.map((s) => s.id)).toEqual(['a', 'b', 'c']);
  });

  it('히스토리가 비면 되돌리기는 아무 일도 하지 않는다', () => {
    useMapStore.getState().undo();
    expect(useMapStore.getState().strokes).toEqual([]);
  });

  it('히스토리는 50개를 넘지 않는다', () => {
    for (let i = 0; i < 60; i++) useMapStore.getState().addStroke(stroke(`s${i}`));
    expect(useMapStore.getState().history).toHaveLength(50);
  });
});

describe('라벨', () => {
  it('라벨을 추가하고 되돌릴 수 있다', () => {
    const label = createLabel({ lat: 37.5, lng: 127 }, '여기서 계단으로');
    useMapStore.getState().addLabel(label);
    expect(useMapStore.getState().labels).toHaveLength(1);

    useMapStore.getState().undo();
    expect(useMapStore.getState().labels).toHaveLength(0);
  });

  it('생성된 라벨은 고유 id와 기본 스타일을 가진다', () => {
    const a = createLabel({ lat: 37.5, lng: 127 }, 'A');
    const b = createLabel({ lat: 37.5, lng: 127 }, 'B');
    expect(a.id).not.toBe(b.id);
    expect(a.fontSize).toBe(14);
    expect(a.color).toBe('#2C2C2A');
  });
});

describe('전체 지우기', () => {
  it('획과 라벨을 함께 비우고 한 번에 되돌릴 수 있다', () => {
    const store = useMapStore.getState();
    store.addStroke(stroke('a'));
    store.addLabel(createLabel({ lat: 37.5, lng: 127 }, '메모'));

    useMapStore.getState().clearAll();
    expect(useMapStore.getState().strokes).toEqual([]);
    expect(useMapStore.getState().labels).toEqual([]);

    useMapStore.getState().undo();
    expect(useMapStore.getState().strokes).toHaveLength(1);
    expect(useMapStore.getState().labels).toHaveLength(1);
  });

  it('비어 있을 때는 히스토리를 더럽히지 않는다', () => {
    useMapStore.getState().clearAll();
    expect(useMapStore.getState().history).toEqual([]);
    expect(useMapStore.getState().saveState).toBe('idle');
  });
});

describe('장소와 순서', () => {
  const at = (n: number) => ({ lat: 37.5 + n / 1000, lng: 127 + n / 1000 });

  function seed(names: string[]) {
    names.forEach((name, i) => useMapStore.getState().addPlace(createPlace(at(i), name)));
  }

  it('담은 순서가 곧 핀 번호다', () => {
    seed(['A', 'B', 'C']);
    expect(useMapStore.getState().places.map((p) => p.name)).toEqual(['A', 'B', 'C']);
  });

  it('위아래로 옮기면 배열 순서가 바뀐다', () => {
    seed(['A', 'B', 'C']);
    useMapStore.getState().movePlace(2, 0);
    expect(useMapStore.getState().places.map((p) => p.name)).toEqual(['C', 'A', 'B']);

    useMapStore.getState().movePlace(0, 1);
    expect(useMapStore.getState().places.map((p) => p.name)).toEqual(['A', 'C', 'B']);
  });

  it('범위를 벗어난 이동은 무시한다', () => {
    seed(['A', 'B']);
    const before = useMapStore.getState().places;
    useMapStore.getState().movePlace(0, 5);
    useMapStore.getState().movePlace(-1, 0);
    useMapStore.getState().movePlace(1, 1);
    expect(useMapStore.getState().places).toBe(before);
  });

  it('순서 변경도 되돌릴 수 있다', () => {
    seed(['A', 'B', 'C']);
    useMapStore.getState().movePlace(0, 2);
    expect(useMapStore.getState().places.map((p) => p.name)).toEqual(['B', 'C', 'A']);

    useMapStore.getState().undo();
    expect(useMapStore.getState().places.map((p) => p.name)).toEqual(['A', 'B', 'C']);
  });

  it('이동수단은 핀별로 바꾼다', () => {
    seed(['A', 'B']);
    const first = useMapStore.getState().places[0]!;
    expect(first.modeToNext).toBe('walk');

    useMapStore.getState().updatePlace(first.id, { modeToNext: 'transit' });
    expect(useMapStore.getState().places[0]!.modeToNext).toBe('transit');
    expect(useMapStore.getState().places[1]!.modeToNext).toBe('walk');
  });

  it('지도에서 직접 찍은 핀에는 kakaoPlaceId가 없다', () => {
    const place = createPlace(at(0), '여기 골목');
    expect(place.kakaoPlaceId).toBeUndefined();
    expect(place.address).toBeUndefined();
  });

  it('검색 결과는 도로명 주소를 우선해서 담는다', () => {
    const place = placeFromCandidate({
      kakaoPlaceId: '123',
      name: '스타벅스 강남대로점',
      address: '서울 강남구 역삼동 825-20',
      roadAddress: '서울 강남구 강남대로 390',
      location: { lat: 37.4979, lng: 127.0276 },
    });
    expect(place.kakaoPlaceId).toBe('123');
    expect(place.address).toBe('서울 강남구 강남대로 390');
    expect(place.location).toEqual({ lat: 37.4979, lng: 127.0276 });
  });
});

describe('hydrate', () => {
  it('불러온 직후에는 idle이고 히스토리가 비어 있다', () => {
    useMapStore.getState().addStroke(stroke('a'));
    useMapStore.getState().hydrate({ title: '홍대 코스', strokes: [stroke('x')], labels: [] });

    const state = useMapStore.getState();
    expect(state.title).toBe('홍대 코스');
    expect(state.strokes.map((s) => s.id)).toEqual(['x']);
    expect(state.history).toEqual([]);
    // 불러오자마자 저장이 돌면 안 된다.
    expect(state.saveState).toBe('idle');
  });

  it('빈 문서로 hydrate하면 초기 상태가 된다', () => {
    useMapStore.getState().addStroke(stroke('a'));
    useMapStore.getState().hydrate({});
    expect(useMapStore.getState().strokes).toEqual([]);
    expect(useMapStore.getState().title).toBe('');
  });
});
