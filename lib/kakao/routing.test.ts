import { describe, expect, it } from 'vitest';
import { NoRouteError, parseDriving, parsePath, parseTransit } from './routing';

/** 실제 응답에서 가져온 모양. 강남역 → 역삼역 도보. */
const walkBody = {
  status: 'OK',
  route: {
    legs: [
      {
        properties: { distance: 882, time: 868 },
        steps: [
          {
            path: { points: [[127.0276, 37.4979], [127.0286, 37.4984]] },
            properties: { distance: 142, guidance: '강남역 12번 출구까지 역사 내 이동', time: 128 },
          },
          {
            // 앞 구간의 끝점이 그대로 다시 온다.
            path: { points: [[127.0286, 37.4984], [127.0309, 37.4991]] },
            properties: { distance: 223, guidance: '강남역 12번 출구 진출 후 223m 이동', time: 229 },
          },
        ],
      },
    ],
  },
};

/** 실제 응답 모양. 지하철 경로가 첫 번째로 온다. */
const transitBody = {
  status: 'OK',
  routes: [
    {
      properties: { type: 'SUBWAY', totalDistance: 951, totalTime: 361, transfers: 0 },
      steps: [
        {
          properties: { guidance: '2호선 (강남 > 역삼)', type: 'SUBWAY' },
          path: { points: [[127.028, 37.4980], [127.0364, 37.5006]] },
        },
      ],
    },
    {
      properties: { type: 'BUS', totalDistance: 1397, totalTime: 720 },
      steps: [{ properties: { guidance: '간선 8146', type: 'BUS' }, path: { points: [[1, 1], [2, 2]] } }],
    },
  ],
};

/** Kakao Mobility 자동차 길찾기 응답의 필요한 부분만 남긴 모양. */
const drivingBody = {
  routes: [
    {
      result_code: 0,
      result_msg: '길찾기 성공',
      summary: { distance: 1_842, duration: 428 },
      sections: [
        {
          roads: [
            { vertexes: [127.0276, 37.4979, 127.0286, 37.4984] },
            // 앞 도로 끝점이 다음 도로 첫점으로 다시 온다.
            { vertexes: [127.0286, 37.4984, 127.0309, 37.4991] },
          ],
        },
      ],
    },
  ],
};

describe('parsePath', () => {
  it('구간별로 나뉜 좌표를 한 줄로 잇는다', () => {
    expect(parsePath(walkBody).points).toEqual([
      { lat: 37.4979, lng: 127.0276 },
      { lat: 37.4984, lng: 127.0286 },
      { lat: 37.4991, lng: 127.0309 },
    ]);
  });

  it('이음매의 중복 좌표를 버린다', () => {
    // 구간 경계에서 같은 점이 두 번 오는데, 그대로 두면 길이 계산과 선 그리기에 군더더기다.
    const points = parsePath(walkBody).points;
    expect(points).toHaveLength(3);
  });

  it('거리와 시간을 합산한다', () => {
    expect(parsePath(walkBody)).toMatchObject({ distanceM: 882, durationS: 868 });
  });

  it('x가 경도, y가 위도다', () => {
    // 뒤집으면 경로가 지구 반대편에 그려진다.
    const first = parsePath(walkBody).points[0]!;
    expect(first.lng).toBeGreaterThan(120);
    expect(first.lat).toBeLessThan(90);
  });

  it('좌표가 없으면 상태를 담아 NoRouteError를 던진다', () => {
    // 도보는 거리가 멀면 200에 TOO_FAR_AWAY를 준다. 성공으로 착각하면 안 된다.
    const empty = { status: 'TOO_FAR_AWAY', route: { legs: [], properties: {} } };
    expect(() => parsePath(empty)).toThrowError(NoRouteError);
    try {
      parsePath(empty);
    } catch (error) {
      expect((error as NoRouteError).status).toBe('TOO_FAR_AWAY');
    }
  });

  it('점이 하나뿐이어도 경로로 치지 않는다', () => {
    const single = { status: 'OK', route: { legs: [{ properties: {}, steps: [{ path: { points: [[127, 37]] } }] }] } };
    expect(() => parsePath(single)).toThrowError(NoRouteError);
  });

  it('망가진 응답에도 터지지 않는다', () => {
    expect(() => parsePath(null)).toThrowError(NoRouteError);
    expect(() => parsePath({ route: 'nope' })).toThrowError(NoRouteError);
  });
});

describe('parseTransit', () => {
  it('첫 번째 경로만 쓴다', () => {
    // 지하철·버스 대안이 여럿 오는데 첫 번째가 카카오의 추천이다.
    expect(parseTransit(transitBody)).toMatchObject({ distanceM: 951, durationS: 361 });
  });

  it('노선 안내 문구를 배지로 남긴다', () => {
    expect(parseTransit(transitBody).legs).toEqual([
      { type: 'SUBWAY', guidance: '2호선 (강남 > 역삼)', pointCount: 2 },
    ]);
  });

  it('구간마다 좌표가 몇 개인지 남긴다', () => {
    // 이걸 남기지 않으면 어디까지가 지하철이고 어디부터 버스인지 알 수 없어,
    // 사이의 환승 도보를 따로 그릴 수 없다.
    const body = {
      status: 'OK',
      routes: [
        {
          properties: { totalDistance: 3000, totalTime: 1800 },
          steps: [
            {
              properties: { guidance: '9호선', type: 'SUBWAY' },
              path: { points: [[127.0, 37.5], [127.01, 37.51]] },
            },
            {
              properties: { guidance: '간선 143', type: 'BUS' },
              path: { points: [[127.02, 37.52], [127.03, 37.53], [127.04, 37.54]] },
            },
          ],
        },
      ],
    };

    const parsed = parseTransit(body);
    expect(parsed.points).toHaveLength(5);
    expect(parsed.legs?.map((leg) => leg.pointCount)).toEqual([2, 3]);
  });

  it('이음매에서 중복 좌표가 빠져도 개수가 어긋나지 않는다', () => {
    // 앞 구간의 끝점이 다음 구간의 시작점으로 다시 오면 하나를 버린다.
    // 개수를 붙인 좌표만으로 세지 않으면 자를 때 한 칸씩 밀린다.
    const body = {
      status: 'OK',
      routes: [
        {
          properties: { totalDistance: 100, totalTime: 100 },
          steps: [
            {
              properties: { guidance: '9호선', type: 'SUBWAY' },
              path: { points: [[127.0, 37.5], [127.01, 37.51]] },
            },
            {
              properties: { guidance: '간선 143', type: 'BUS' },
              path: { points: [[127.01, 37.51], [127.02, 37.52]] },
            },
          ],
        },
      ],
    };

    const parsed = parseTransit(body);
    expect(parsed.points).toHaveLength(3);
    expect(parsed.legs?.map((leg) => leg.pointCount)).toEqual([2, 1]);
  });

  it('좌표도 함께 담는다', () => {
    expect(parseTransit(transitBody).points).toHaveLength(2);
  });

  it('경로가 하나도 없으면 NoRouteError', () => {
    expect(() => parseTransit({ status: 'NO_RESULT', routes: [] })).toThrowError(NoRouteError);
  });

  it('안내 문구가 없는 구간은 배지를 만들지 않는다', () => {
    const body = {
      status: 'OK',
      routes: [
        {
          properties: { totalDistance: 10, totalTime: 20 },
          steps: [{ properties: {}, path: { points: [[127, 37], [128, 38]] } }],
        },
      ],
    };
    expect(parseTransit(body).legs).toBeUndefined();
  });
});

describe('parseDriving', () => {
  it('도로별 평면 좌표 배열을 하나의 경로로 잇고 중복 이음매를 버린다', () => {
    expect(parseDriving(drivingBody).points).toEqual([
      { lat: 37.4979, lng: 127.0276 },
      { lat: 37.4984, lng: 127.0286 },
      { lat: 37.4991, lng: 127.0309 },
    ]);
  });

  it('요약 거리와 시간을 보존한다', () => {
    expect(parseDriving(drivingBody)).toMatchObject({ distanceM: 1_842, durationS: 428 });
  });

  it('카카오모빌리티 실패 코드를 NoRouteError에 남긴다', () => {
    try {
      parseDriving({ routes: [{ result_code: 103, result_msg: '도착지 도로 탐색 실패' }] });
      throw new Error('예외가 필요하다');
    } catch (error) {
      expect(error).toBeInstanceOf(NoRouteError);
      expect((error as NoRouteError).status).toBe('CAR_103');
    }
  });

  it('성공 응답이어도 그릴 좌표가 없으면 경로로 치지 않는다', () => {
    expect(() =>
      parseDriving({ routes: [{ result_code: 0, summary: {}, sections: [] }] }),
    ).toThrowError(NoRouteError);
  });
});
