import { describe, expect, it } from 'vitest';
import { createStaticProjection } from './staticProjection';
import { sceneCoordinates, sceneViewport } from './sceneViewport';
import type { MapDocument } from './types';

function document(overrides: Partial<MapDocument> = {}): MapDocument {
  return {
    title: '공유 지도',
    center: { lat: 37.4979, lng: 127.0276 },
    zoomLevel: 3,
    stops: [],
    legs: [],
    strokes: [],
    labels: [],
    showCandidateLinks: true,
    showStopArrows: true,
    ...overrides,
  };
}

it('저장 카메라가 강남이어도 신도림 핀 하나를 중심에 둔다', () => {
  const sindorim = { lat: 37.5088, lng: 126.8913 };
  const viewport = sceneViewport(
    document({
      stops: [
        {
          id: 's1',
          candidates: [{ id: 'p1', name: '신도림', location: sindorim, pinColor: '#E24B4A' }],
        },
      ],
    }),
    { width: 800, height: 420 },
  );

  expect(viewport.center).toEqual(sindorim);
  expect(viewport.level).toBe(3);
});

it('핀·메모·손그림·표시 중인 경로 좌표를 모두 모은다', () => {
  const routePoint = { lat: 37.4, lng: 126.9 };
  const result = sceneCoordinates(
    document({
      stops: [
        {
          id: 's1',
          candidates: [
            { id: 'p1', name: '핀', location: { lat: 37.5, lng: 127 }, pinColor: '#E24B4A' },
          ],
        },
        {
          id: 's2',
          candidates: [
            { id: 'p2', name: '도착', location: { lat: 37.51, lng: 127.01 }, pinColor: '#E24B4A' },
          ],
        },
      ],
      strokes: [
        { id: 'line', color: '#000000', width: 4, zoomCreated: 3, path: [{ lat: 37.6, lng: 127.1 }] },
      ],
      labels: [{ id: 'memo', location: { lat: 37.7, lng: 127.2 }, text: '메모', color: '#000', fontSize: 14 }],
      legs: [
        {
          mode: 'walk',
          route: {
            points: [routePoint],
            distanceM: 1,
            durationS: 1,
            fromPlaceId: 'p1',
            toPlaceId: 'p2',
            fetchedAt: '2026-08-06T00:00:00.000Z',
          },
        },
      ],
    }),
  );

  expect(result).toContainEqual(routePoint);
  expect(result).toHaveLength(5);
});

describe('여러 표시의 화면 맞춤', () => {
  it('계산한 레벨에서 모든 좌표가 썸네일 여백 안에 들어온다', () => {
    const points = [
      { lat: 37.5088, lng: 126.8913 },
      { lat: 37.5665, lng: 126.978 },
      { lat: 37.484, lng: 127.032 },
    ];
    const viewport = sceneViewport(
      document({
        strokes: [{ id: 'line', color: '#000', width: 4, zoomCreated: 3, path: points }],
      }),
      { width: 800, height: 420, padding: 56 },
    );
    const project = createStaticProjection({
      center: viewport.center,
      level: viewport.level,
      width: 800,
      height: 420,
    });

    for (const point of points.map(project)) {
      expect(point.x).toBeGreaterThanOrEqual(56);
      expect(point.x).toBeLessThanOrEqual(744);
      expect(point.y).toBeGreaterThanOrEqual(56);
      expect(point.y).toBeLessThanOrEqual(364);
    }
  });
});
