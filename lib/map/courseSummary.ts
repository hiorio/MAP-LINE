import {
  formatDistance,
  formatDuration,
  travelModeLabel,
  type LatLng,
  type Stop,
  type StopLeg,
} from './types';
import { drawableRoute } from './legs';

export { formatDuration } from './types';

export interface SharedCourseCandidate {
  id: string;
  name: string;
  address?: string;
  memo?: string;
  location: LatLng;
  isPrimary: boolean;
}

export interface SharedCourseLeg {
  label: string;
  detail?: string;
  guidance: string[];
}

export interface SharedCourseStep {
  id: string;
  number: number;
  candidates: SharedCourseCandidate[];
  primaryPending: boolean;
  nextLeg?: SharedCourseLeg;
}

/** 공유 화면이 편집 상태 없이도 모임 순서·후보·이동 방법을 읽을 수 있는 모양으로 만든다. */
export function buildSharedCourse(
  stops: readonly Stop[],
  legs: readonly StopLeg[],
): SharedCourseStep[] {
  return stops.map((stop, index) => {
    const primaryExists = stop.candidates.some((place) => place.id === stop.primaryId);
    const primaryPending = stop.candidates.length > 1 && !primaryExists;
    const leg = legs[index];
    const route = drawableRoute(stops, index, leg);

    return {
      id: stop.id,
      number: index + 1,
      candidates: stop.candidates.map((place) => ({
        id: place.id,
        name: place.name,
        ...(place.address ? { address: place.address } : {}),
        ...(place.memo ? { memo: place.memo } : {}),
        location: place.location,
        isPrimary: stop.candidates.length === 1 || stop.primaryId === place.id,
      })),
      primaryPending,
      ...(leg
        ? {
            nextLeg: {
              label: travelModeLabel(leg.mode),
              ...(route
                ? {
                    detail: `${formatDistance(route.distanceM)} · ${formatDuration(route.durationS)}`,
                  }
                : {}),
              guidance: route?.legs?.map((item) => item.guidance) ?? [],
            },
          }
        : {}),
    };
  });
}

/** 카카오톡 같은 링크 미리보기에서도 첫 후보만 확정 장소처럼 보이지 않게 한다. */
export function sharedCourseDescription(stops: readonly Stop[]): string {
  if (stops.length === 0) return '손으로 그린 지도를 확인해 보세요.';

  const stages = stops.slice(0, 3).map((stop, index) => {
    const visible = stop.candidates.slice(0, 3).map((place) => place.name);
    const more = stop.candidates.length - visible.length;
    return `${index + 1}단계 ${visible.join(' / ')}${more > 0 ? ` 외 ${more}곳` : ''}`;
  });
  const remaining = stops.length - stages.length;
  return `모임 동선: ${stages.join(' → ')}${remaining > 0 ? ` 외 ${remaining}단계` : ''}`;
}
