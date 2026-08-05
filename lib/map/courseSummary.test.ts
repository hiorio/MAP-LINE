import { describe, expect, it } from 'vitest';
import { buildSharedCourse, formatDuration, sharedCourseDescription } from './courseSummary';
import type { Place, Stop, StopLeg } from './types';

const place = (id: string, name: string): Place => ({
  id,
  name,
  location: { lat: 37.5, lng: 127 },
  pinColor: '#E24B4A',
});

describe('buildSharedCourse', () => {
  it('한 단계의 모든 후보와 대표를 공유용 목록에 남긴다', () => {
    const stops: Stop[] = [
      { id: 's1', candidates: [place('a', '예식장 A'), place('b', '예식장 B')], primaryId: 'b' },
    ];

    const [step] = buildSharedCourse(stops, []);
    expect(step?.candidates.map((candidate) => candidate.name)).toEqual(['예식장 A', '예식장 B']);
    expect(step?.candidates.map((candidate) => candidate.isPrimary)).toEqual([false, true]);
    expect(step?.primaryPending).toBe(false);
  });

  it('후보가 여럿인데 대표가 없으면 미정으로 표시한다', () => {
    const stops: Stop[] = [
      { id: 's1', candidates: [place('a', '식당 A'), place('b', '식당 B')] },
    ];
    expect(buildSharedCourse(stops, [])[0]?.primaryPending).toBe(true);
  });

  it('다음 단계까지의 이동 방법·시간·노선 안내를 함께 만든다', () => {
    const stops: Stop[] = [
      { id: 's1', candidates: [place('a', '출발')] },
      { id: 's2', candidates: [place('b', '도착')] },
    ];
    const legs: StopLeg[] = [
      {
        mode: 'transit',
        route: {
          points: [],
          distanceM: 1530,
          durationS: 3900,
          fromPlaceId: 'a',
          toPlaceId: 'b',
          fetchedAt: '2026-08-04T00:00:00Z',
          legs: [{ type: 'SUBWAY', guidance: '2호선', pointCount: 2 }],
        },
      },
    ];

    expect(buildSharedCourse(stops, legs)[0]?.nextLeg).toEqual({
      label: '대중교통',
      detail: '1.5km · 1시간 5분',
      guidance: ['2호선'],
    });
  });

  it('현재 대표 후보와 끝점이 다른 옛 경로는 공유 설명에 쓰지 않는다', () => {
    const stops: Stop[] = [
      { id: 's1', candidates: [place('a', '출발')] },
      { id: 's2', candidates: [place('b', '도착')] },
    ];
    const legs: StopLeg[] = [
      {
        mode: 'walk',
        route: {
          points: [],
          distanceM: 100,
          durationS: 60,
          fromPlaceId: 'old-a',
          toPlaceId: 'old-b',
          fetchedAt: '2026-08-04T00:00:00Z',
        },
      },
    ];

    expect(buildSharedCourse(stops, legs)[0]?.nextLeg).toEqual({
      label: '도보',
      guidance: [],
    });
  });
});

describe('formatDuration', () => {
  it('분과 시간을 읽기 쉽게 표시한다', () => {
    expect(formatDuration(900)).toBe('15분');
    expect(formatDuration(3900)).toBe('1시간 5분');
  });
});

describe('sharedCourseDescription', () => {
  it('링크 미리보기에 한 단계의 복수 후보를 모두 드러낸다', () => {
    const stops: Stop[] = [
      { id: 's1', candidates: [place('a', '예식장 A'), place('b', '예식장 B')] },
      { id: 's2', candidates: [place('c', '식당')] },
    ];
    expect(sharedCourseDescription(stops)).toBe('모임 동선: 1단계 예식장 A / 예식장 B → 2단계 식당');
  });
});
