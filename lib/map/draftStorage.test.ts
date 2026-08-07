import { afterEach, describe, expect, it } from 'vitest';
import { loadDraft, saveDraft } from './draftStorage';
import type { MapDocument } from './types';

function documentWithCarRoute(): MapDocument {
  return {
    title: '자동차 여행',
    center: { lat: 37.5, lng: 127 },
    zoomLevel: 4,
    stops: [],
    legs: [
      {
        mode: 'car',
        route: {
          points: [{ lat: 37.5, lng: 127 }, { lat: 37.6, lng: 127.1 }],
          distanceM: 12_000,
          durationS: 1_800,
          fromPlaceId: 'from',
          toPlaceId: 'to',
          fetchedAt: '2026-08-07T00:00:00.000Z',
        },
      },
    ],
    strokes: [],
    labels: [],
    showCandidateLinks: true,
    showStopArrows: true,
  };
}

afterEach(() => {
  Reflect.deleteProperty(globalThis, 'window');
});

describe('draftStorage', () => {
  it('브라우저 초안에는 자동차 모드만 남기고 경로 응답을 저장하지 않는다', () => {
    const values = new Map<string, string>();
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: {
        localStorage: {
          getItem: (key: string) => values.get(key) ?? null,
          setItem: (key: string, value: string) => values.set(key, value),
        },
      },
    });

    const document = documentWithCarRoute();
    saveDraft('car-map', document);

    expect(loadDraft('car-map')?.legs).toEqual([{ mode: 'car' }]);
    expect(document.legs[0]?.route).toBeDefined();
  });
});
