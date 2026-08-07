'use client';

import { useEffect, useRef } from 'react';
import { legEndpoints, legsNeedingRoute } from '@/lib/map/legs';
import { requestRoute } from '@/lib/map/requestRoute';
import { useMapStore } from '@/store/useMapStore';

/**
 * 이동수단을 고른 구간의 실제 경로를 받아 온다.
 *
 * 편집기에서 돈다. 링크를 받아 보는 쪽은 저장 가능한 경로를 그대로 그리고, 영구 저장하지
 * 않는 자동차 경로만 사용자가 동선 상세를 열었을 때 별도로 받는다. 공유 지도를 열 때마다
 * 모든 경로를 다시 부르면 인기 있는 지도 하나가 하루 쿼터를 빠르게 소모한다.
 *
 * 같은 구간을 두 번 부르지 않도록 진행 중인 요청을 기억한다. 저장이 dirty가 되면
 * 이 훅이 다시 도는데, 그때마다 요청을 새로 내면 응답이 오기 전에 겹쳐 나간다.
 */
export function useLegRoutes() {
  const stops = useMapStore((s) => s.stops);
  const legs = useMapStore((s) => s.legs);
  const setLegRoute = useMapStore((s) => s.setLegRoute);
  const inFlight = useRef(new Set<string>());

  useEffect(() => {
    const pending = legsNeedingRoute(stops, legs);
    if (pending.length === 0) return;

    let cancelled = false;

    for (const index of pending) {
      const leg = legs[index];
      const ends = legEndpoints(stops, index);
      if (!leg || !ends || leg.mode === 'straight') continue;

      // 어떤 구간을 어떤 수단으로 부르는지가 같으면 같은 요청이다.
      const token = `${index}:${leg.mode}:${ends.from.id}:${ends.to.id}`;
      if (inFlight.current.has(token)) continue;
      inFlight.current.add(token);

      void requestRoute(leg.mode, ends.from, ends.to)
        .then((route) => {
          if (!cancelled) setLegRoute(index, route);
        })
        .finally(() => {
          inFlight.current.delete(token);
        });
    }

    return () => {
      cancelled = true;
    };
  }, [stops, legs, setLegRoute]);
}
