import { pxPerDegreeLat, pxPerDegreeLng } from './staticProjection';
import { drawableRoute } from './legs';
import type { LatLng, MapDocument } from './types';

type VisibleScene = Pick<
  MapDocument,
  'center' | 'zoomLevel' | 'stops' | 'legs' | 'strokes' | 'labels' | 'showStopArrows'
>;

export interface SceneViewportOptions {
  width: number;
  height: number;
  padding?: number;
  minLevel?: number;
  maxLevel?: number;
}

export interface SceneViewport {
  center: LatLng;
  level: number;
  coordinates: LatLng[];
}

/** 공유 화면에 실제로 그리는 모든 좌표를 모은다. */
export function sceneCoordinates(document: VisibleScene): LatLng[] {
  const coordinates: LatLng[] = [];
  const add = (coord: LatLng) => {
    if (
      Number.isFinite(coord.lat) &&
      Number.isFinite(coord.lng) &&
      Math.abs(coord.lat) <= 90 &&
      Math.abs(coord.lng) <= 180
    ) {
      coordinates.push(coord);
    }
  };

  for (const stop of document.stops) {
    for (const place of stop.candidates) add(place.location);
  }
  for (const stroke of document.strokes) {
    for (const point of stroke.path) add(point);
  }
  for (const label of document.labels) add(label.location);

  // 경로 표시를 끈 지도 때문에 화면이 불필요하게 멀어지지 않게 한다.
  if (document.showStopArrows) {
    for (const [index, leg] of document.legs.entries()) {
      for (const point of drawableRoute(document.stops, index, leg)?.points ?? []) add(point);
    }
  }

  return coordinates;
}

/**
 * 핀·메모·손그림·경로가 여백 안에 함께 들어오는 중심과 레벨을 계산한다.
 *
 * 표시가 하나도 없을 때만 저장된 카메라를 그대로 쓴다. 표시가 있다면 저장 당시 카메라가
 * 강남에 남아 있어도 실제 장면을 우선한다.
 */
export function sceneViewport(
  document: VisibleScene,
  { width, height, padding = 56, minLevel = 3, maxLevel = 15 }: SceneViewportOptions,
): SceneViewport {
  const coordinates = sceneCoordinates(document);
  const fallbackLevel = clampLevel(document.zoomLevel, 1, maxLevel);
  if (coordinates.length === 0) {
    return { center: document.center, level: fallbackLevel, coordinates };
  }

  let minLat = coordinates[0]!.lat;
  let maxLat = coordinates[0]!.lat;
  let minLng = coordinates[0]!.lng;
  let maxLng = coordinates[0]!.lng;
  for (const point of coordinates.slice(1)) {
    minLat = Math.min(minLat, point.lat);
    maxLat = Math.max(maxLat, point.lat);
    minLng = Math.min(minLng, point.lng);
    maxLng = Math.max(maxLng, point.lng);
  }
  const center = { lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2 };

  if (coordinates.length === 1) {
    return {
      center,
      level: Math.max(clampLevel(minLevel, 1, maxLevel), fallbackLevel),
      coordinates,
    };
  }

  const usableWidth = Math.max(1, width - Math.min(width - 1, padding * 2));
  const usableHeight = Math.max(1, height - Math.min(height - 1, padding * 2));
  const firstLevel = clampLevel(minLevel, 1, maxLevel);
  let level = firstLevel;

  for (; level < maxLevel; level += 1) {
    const spanX = (maxLng - minLng) * pxPerDegreeLng(level, center.lat);
    const spanY = (maxLat - minLat) * pxPerDegreeLat(level);
    if (spanX <= usableWidth && spanY <= usableHeight) break;
  }

  return { center, level, coordinates };
}

function clampLevel(level: number, min: number, max: number): number {
  if (!Number.isFinite(level)) return Math.min(max, Math.max(min, 3));
  return Math.min(max, Math.max(min, Math.round(level)));
}
