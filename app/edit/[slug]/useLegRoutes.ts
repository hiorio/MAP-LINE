'use client';

import { useEffect, useRef } from 'react';
import { legEndpoints, legsNeedingRoute } from '@/lib/map/legs';
import type { RoutePath } from '@/lib/map/types';
import { useMapStore } from '@/store/useMapStore';

/**
 * 이동수단을 고른 구간의 실제 경로를 받아 온다.
 *
 * 편집기에서만 돈다. 링크를 받아 보는 쪽은 저장된 경로를 그대로 그리므로 길찾기를
 * 부르지 않는다. 조회할 때마다 부르면 인기 있는 지도 하나가 하루치 쿼터(1,000건)를
 * 다 먹는다.
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

async function requestRoute(
  mode: string,
  from: { id: string; location: { lat: number; lng: number } },
  to: { id: string; location: { lat: number; lng: number } },
): Promise<RoutePath | null> {
  const params = new URLSearchParams({
    mode,
    from_lat: String(from.location.lat),
    from_lng: String(from.location.lng),
    to_lat: String(to.location.lat),
    to_lng: String(to.location.lng),
  });

  try {
    const response = await fetch(`/api/route?${params}`);
    // 422는 "이 수단으로는 갈 수 없다"는 답이다. 도보로 서울에서 부산은 못 간다.
    // 실패가 아니므로 조용히 직선으로 되돌린다.
    if (!response.ok) return null;

    const body = (await response.json()) as {
      points?: unknown;
      distanceM?: unknown;
      durationS?: unknown;
      legs?: RoutePath['legs'];
    };
    if (!Array.isArray(body.points) || body.points.length < 2) return null;

    return {
      points: body.points as RoutePath['points'],
      distanceM: Number(body.distanceM) || 0,
      durationS: Number(body.durationS) || 0,
      ...(body.legs ? { legs: body.legs } : {}),
      fromPlaceId: from.id,
      toPlaceId: to.id,
      fetchedAt: new Date().toISOString(),
    };
  } catch {
    // 네트워크가 끊겨도 편집은 계속돼야 한다. 다음 변경 때 다시 시도한다.
    return null;
  }
}
