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
    stops: [],
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

  it('글자를 고칠 수 있고 되돌릴 수 있다', () => {
    const label = createLabel({ lat: 37.5, lng: 127 }, '여기서 계단으로');
    useMapStore.getState().addLabel(label);

    useMapStore.getState().updateLabel(label.id, { text: '여기서 엘리베이터로' });
    expect(useMapStore.getState().labels[0]!.text).toBe('여기서 엘리베이터로');

    useMapStore.getState().undo();
    expect(useMapStore.getState().labels[0]!.text).toBe('여기서 계단으로');
  });

  it('위치를 옮길 수 있다', () => {
    const label = createLabel({ lat: 37.5, lng: 127 }, '메모');
    useMapStore.getState().addLabel(label);

    useMapStore.getState().updateLabel(label.id, { location: { lat: 37.6, lng: 127.1 } });
    expect(useMapStore.getState().labels[0]!.location).toEqual({ lat: 37.6, lng: 127.1 });
    // 글자는 건드리지 않는다.
    expect(useMapStore.getState().labels[0]!.text).toBe('메모');
  });

  it('없는 라벨을 고치려 하면 아무 일도 없다', () => {
    useMapStore.getState().addLabel(createLabel({ lat: 37.5, lng: 127 }, '메모'));
    const before = useMapStore.getState().labels;

    useMapStore.getState().updateLabel('없는-id', { text: '바뀜' });
    expect(useMapStore.getState().labels).toBe(before);
    expect(useMapStore.getState().history).toHaveLength(1);
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

describe('단계와 후보', () => {
  const at = (n: number) => ({ lat: 37.5 + n / 1000, lng: 127 + n / 1000 });

  function seedStops(names: string[]) {
    names.forEach((name, i) => useMapStore.getState().addStop([createPlace(at(i), name)]));
  }

  it('담은 순서가 곧 단계 번호다', () => {
    seedStops(['A', 'B', 'C']);
    expect(useMapStore.getState().stops.map((s) => s.candidates[0]!.name)).toEqual(['A', 'B', 'C']);
  });

  it('여러 장소를 한 단계의 후보로 담는다', () => {
    // "2번은 점심인데 어디로 갈지 아직 안 정했다"를 담는 구조다.
    useMapStore.getState().addStop([
      createPlace(at(0), '국밥집'),
      createPlace(at(1), '칼국수집'),
      createPlace(at(2), '냉면집'),
    ]);

    const stops = useMapStore.getState().stops;
    expect(stops).toHaveLength(1);
    expect(stops[0]!.candidates.map((p) => p.name)).toEqual(['국밥집', '칼국수집', '냉면집']);
  });

  it('빈 배열로는 단계를 만들지 않는다', () => {
    useMapStore.getState().addStop([]);
    expect(useMapStore.getState().stops).toEqual([]);
  });

  it('이미 있는 단계에 후보를 더한다', () => {
    seedStops(['A']);
    const stopId = useMapStore.getState().stops[0]!.id;

    useMapStore.getState().addCandidates(stopId, [createPlace(at(5), '후보2')]);
    expect(useMapStore.getState().stops).toHaveLength(1);
    expect(useMapStore.getState().stops[0]!.candidates.map((p) => p.name)).toEqual(['A', '후보2']);
  });

  it('후보 하나만 빼면 단계는 남는다', () => {
    useMapStore.getState().addStop([createPlace(at(0), 'A'), createPlace(at(1), 'B')]);
    const second = useMapStore.getState().stops[0]!.candidates[1]!;

    useMapStore.getState().removeCandidate(second.id);
    expect(useMapStore.getState().stops[0]!.candidates.map((p) => p.name)).toEqual(['A']);
  });

  it('마지막 후보가 빠지면 단계도 사라진다', () => {
    // 후보가 없는 단계는 번호만 비어 보인다.
    seedStops(['A', 'B']);
    const onlyCandidate = useMapStore.getState().stops[0]!.candidates[0]!;

    useMapStore.getState().removeCandidate(onlyCandidate.id);
    expect(useMapStore.getState().stops).toHaveLength(1);
    expect(useMapStore.getState().stops[0]!.candidates[0]!.name).toBe('B');
  });

  it('없는 후보를 빼려 하면 아무 일도 없다', () => {
    seedStops(['A']);
    const before = useMapStore.getState().stops;
    useMapStore.getState().removeCandidate('없는-id');
    expect(useMapStore.getState().stops).toBe(before);
  });

  it('단계를 통째로 지운다', () => {
    seedStops(['A', 'B']);
    useMapStore.getState().removeStop(useMapStore.getState().stops[0]!.id);
    expect(useMapStore.getState().stops.map((s) => s.candidates[0]!.name)).toEqual(['B']);
  });

  it('단계 순서를 바꾼다', () => {
    seedStops(['A', 'B', 'C']);
    useMapStore.getState().moveStop(2, 0);
    expect(useMapStore.getState().stops.map((s) => s.candidates[0]!.name)).toEqual(['C', 'A', 'B']);
  });

  it('범위를 벗어난 이동은 무시한다', () => {
    seedStops(['A', 'B']);
    const before = useMapStore.getState().stops;
    useMapStore.getState().moveStop(0, 5);
    useMapStore.getState().moveStop(-1, 0);
    useMapStore.getState().moveStop(1, 1);
    expect(useMapStore.getState().stops).toBe(before);
  });

  it('순서 변경도 되돌릴 수 있다', () => {
    seedStops(['A', 'B', 'C']);
    useMapStore.getState().moveStop(0, 2);
    expect(useMapStore.getState().stops.map((s) => s.candidates[0]!.name)).toEqual(['B', 'C', 'A']);

    useMapStore.getState().undo();
    expect(useMapStore.getState().stops.map((s) => s.candidates[0]!.name)).toEqual(['A', 'B', 'C']);
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
  });
});

describe('hydrate', () => {
  it('불러온 직후에는 idle이고 히스토리가 비어 있다', () => {
    useMapStore.getState().addStroke(stroke('a'));
    useMapStore.getState().hydrate({ title: '홍대 코스', strokes: [stroke('x')], labels: [], stops: [] });

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
