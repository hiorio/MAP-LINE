import type { RoutePath, TravelMode } from './types';

type RouteEndpoint = { id: string; location: { lat: number; lng: number } };

/** 클라이언트가 공용 `/api/route`에서 한 구간을 받아 세션용 RoutePath로 만든다. */
export async function requestRoute(
  mode: Exclude<TravelMode, 'straight'>,
  from: RouteEndpoint,
  to: RouteEndpoint,
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
    return null;
  }
}
