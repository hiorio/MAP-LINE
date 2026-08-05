import { describe, expect, it } from 'vitest';
import {
  dedupeStations,
  stationBaseName,
  centroidOf,
  distanceM,
  rankCandidates,
  searchRadiusM,
  shortlist,
  estimatedDurationS,
  travelWeightedCenter,
  type Leg,
  type Participant,
} from './geometry';

const 강남역 = { lat: 37.4979, lng: 127.0276 };
const 홍대입구역 = { lat: 37.5572, lng: 126.9245 };
const 잠실역 = { lat: 37.5133, lng: 127.1002 };

function person(id: string, location: { lat: number; lng: number }): Participant {
  return { id, location, mode: 'transit' };
}

describe('distanceM', () => {
  it('같은 지점은 0이다', () => {
    expect(distanceM(강남역, 강남역)).toBe(0);
  });

  it('강남역에서 홍대입구역은 약 10km다', () => {
    // 실제 직선거리가 10km 남짓이다. 크게 틀리면 반경 계산이 통째로 어긋난다.
    const d = distanceM(강남역, 홍대입구역);
    expect(d).toBeGreaterThan(9_000);
    expect(d).toBeLessThan(11_500);
  });

  it('방향이 바뀌어도 같다', () => {
    expect(distanceM(강남역, 잠실역)).toBe(distanceM(잠실역, 강남역));
  });
});

describe('centroidOf', () => {
  it('두 지점의 가운데를 낸다', () => {
    expect(centroidOf([{ lat: 0, lng: 0 }, { lat: 2, lng: 4 }])).toEqual({ lat: 1, lng: 2 });
  });

  it('참가자가 없으면 null', () => {
    expect(centroidOf([])).toBeNull();
  });

  it('한 명이면 그 자리다', () => {
    expect(centroidOf([강남역])).toEqual(강남역);
  });
});

describe('searchRadiusM', () => {
  it('다 같은 동네면 최소 반경으로 좁힌다', () => {
    const points = [강남역, { lat: 37.4985, lng: 127.0285 }];
    const center = centroidOf(points)!;
    expect(searchRadiusM(center, points)).toBe(1_000);
  });

  it('멀리 흩어질수록 넓게 본다', () => {
    const points = [강남역, 홍대입구역];
    const center = centroidOf(points)!;
    const radius = searchRadiusM(center, points);
    expect(radius).toBeGreaterThan(1_000);
    expect(radius).toBeLessThanOrEqual(20_000);
  });

  it('카카오 상한인 20km를 넘지 않는다', () => {
    // 서울과 부산. 넘겨 보내면 검색이 통째로 실패한다.
    const points = [강남역, { lat: 35.1151, lng: 129.0403 }];
    const center = centroidOf(points)!;
    expect(searchRadiusM(center, points)).toBe(20_000);
  });
});

describe('stationBaseName / dedupeStations', () => {
  it('노선 이름을 떼어 낸다', () => {
    expect(stationBaseName('이촌역 경의중앙선')).toBe('이촌역');
    expect(stationBaseName('역삼역 2호선')).toBe('역삼역');
    expect(stationBaseName('강남역 신분당선')).toBe('강남역');
  });

  it('노선이 안 붙은 이름은 그대로 둔다', () => {
    expect(stationBaseName('옥수역')).toBe('옥수역');
  });

  it('같은 역은 하나만 남긴다', () => {
    // 카카오는 환승역을 노선마다 따로 준다. 사람 입장에서는 같은 곳이다.
    const places = [
      { name: '이촌역 경의중앙선' },
      { name: '이촌역 4호선' },
      { name: '한남역 경의중앙선' },
    ];
    expect(dedupeStations(places).map((p) => p.name)).toEqual([
      '이촌역 경의중앙선',
      '한남역 경의중앙선',
    ]);
  });

  it('거리순 목록이면 가장 가까운 입구가 남는다', () => {
    const places = [{ name: '옥수역 3호선' }, { name: '옥수역 경의중앙선' }];
    expect(dedupeStations(places).map((p) => p.name)).toEqual(['옥수역 3호선']);
  });
});

describe('shortlist', () => {
  const participants = [person('a', 강남역), person('b', 홍대입구역)];

  it('가장 멀리서 오는 사람이 덜 고생하는 순으로 고른다', () => {
    const candidates = [
      { id: '먼곳', location: { lat: 37.7, lng: 127.5 } },
      { id: '가운데', location: { lat: 37.527, lng: 126.976 } },
      { id: '강남쪽', location: 강남역 },
    ];
    expect(shortlist(candidates, participants, 2).map((c) => c.id)).toEqual(['가운데', '강남쪽']);
  });

  it('요청한 개수만큼만 남긴다', () => {
    // 길찾기는 하루 1,000건이고 참가자 수만큼 곱해 나간다. 여기서 줄이지 않으면 바닥난다.
    const candidates = Array.from({ length: 15 }, (_, i) => ({
      id: String(i),
      location: { lat: 37.5 + i * 0.001, lng: 127.0 },
    }));
    expect(shortlist(candidates, participants, 3)).toHaveLength(3);
  });

  it('후보가 요청보다 적으면 있는 만큼만 준다', () => {
    expect(shortlist([{ id: 'x', location: 강남역 }], participants, 5)).toHaveLength(1);
  });

  it('직선거리가 같아도 걷는 사람의 부담을 더 크게 반영한다', () => {
    const people: Participant[] = [
      { id: 'walk', location: { lat: 0, lng: 0 }, mode: 'walk' },
      { id: 'transit', location: { lat: 0, lng: 0.10 }, mode: 'transit' },
    ];
    const candidates = [
      { id: '도보쪽', location: { lat: 0, lng: 0.02 } },
      { id: '기하중심', location: { lat: 0, lng: 0.05 } },
    ];

    expect(shortlist(candidates, people, 1)[0]?.id).toBe('도보쪽');
  });
});

describe('travelWeightedCenter / estimatedDurationS', () => {
  it('도보 참가자 쪽으로 검색 중심을 당긴다', () => {
    const center = travelWeightedCenter([
      { id: 'a', location: { lat: 0, lng: 0 }, mode: 'walk' },
      { id: 'b', location: { lat: 0, lng: 10 }, mode: 'transit' },
    ]);
    expect(center?.lng).toBe(2);
  });

  it('같은 거리의 예상 시간은 도보가 대중교통보다 길다', () => {
    expect(estimatedDurationS(5_000, 'walk')).toBeGreaterThan(
      estimatedDurationS(5_000, 'transit'),
    );
  });
});

describe('rankCandidates', () => {
  const legs = (...times: (number | undefined)[]): Leg[] =>
    times.map((durationS, i) => ({
      participantId: String(i),
      mode: 'transit' as const,
      ...(durationS === undefined ? {} : { durationS }),
    }));

  it('가장 오래 걸리는 사람이 적게 걸리는 곳이 1등이다', () => {
    // 합계는 A가 낫지만(50 vs 60) A는 한 사람이 40분을 간다. 모임에선 좋은 답이 아니다.
    const ranked = rankCandidates([
      { place: 'A', legs: legs(10 * 60, 40 * 60) },
      { place: 'B', legs: legs(30 * 60, 30 * 60) },
    ]);
    expect(ranked.map((r) => r.place)).toEqual(['B', 'A']);
  });

  it('최댓값이 같으면 합계가 적은 쪽이 앞선다', () => {
    const ranked = rankCandidates([
      { place: '합계큼', legs: legs(30 * 60, 30 * 60) },
      { place: '합계작음', legs: legs(10 * 60, 30 * 60) },
    ]);
    expect(ranked[0]!.place).toBe('합계작음');
  });

  it('공평한 정도를 함께 낸다', () => {
    const [first] = rankCandidates([{ place: 'A', legs: legs(600, 1800) }]);
    expect(first).toMatchObject({ maxDurationS: 1800, totalDurationS: 2400, spreadS: 1200 });
  });

  it('경로를 못 구한 사람이 있으면 뒤로 보내되 버리지 않는다', () => {
    // 도보로 갈 수 없는 거리여도 "여기까지 이만큼 걸린다"는 판단에 도움이 된다.
    const ranked = rankCandidates([
      { place: '일부실패', legs: legs(60, undefined) },
      { place: '완전', legs: legs(3600, 3600) },
    ]);
    expect(ranked.map((r) => r.place)).toEqual(['완전', '일부실패']);
    expect(ranked[1]!.complete).toBe(false);
  });

  it('아무도 못 구했으면 완전하지 않다고 표시한다', () => {
    const [only] = rankCandidates([{ place: 'A', legs: legs(undefined, undefined) }]);
    expect(only!.complete).toBe(false);
    expect(only!.totalDurationS).toBe(0);
  });

  it('한 명이라도 빠지면 편차를 내지 않는다', () => {
    // 남은 사람이 하나면 최대와 최소가 같아 "편차 0분 = 완벽하게 공평"으로 읽힌다.
    // 모르는 것을 0으로 보여 주느니 비워 둔다.
    const [only] = rankCandidates([{ place: 'A', legs: legs(900, undefined) }]);
    expect(only).not.toHaveProperty('spreadS');
  });

  it('모두 구해졌을 때만 편차가 있다', () => {
    const [only] = rankCandidates([{ place: 'A', legs: legs(600, 1800) }]);
    expect(only!.spreadS).toBe(1200);
  });
});
