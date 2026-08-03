import { NextResponse } from 'next/server';
import { MissingRestKeyError } from '@/lib/kakao/localSearch';
import {
  NoMeetingPlaceError,
  NotEnoughParticipantsError,
  findMidpoint,
} from '@/lib/midpoint/findMidpoint';
import { isTravelMode } from '@/lib/map/types';
import type { Participant } from '@/lib/midpoint/geometry';
import { MIDPOINT_LIMIT, checkRateLimit, tooManyRequests } from '@/lib/rateLimit';

/**
 * 여러 곳에서 오는 사람들이 모이기 좋은 자리를 돌려준다.
 *
 * 한 번 부를 때 길찾기가 `참가자 수 × 결선 후보 수`만큼 나간다. 길찾기는 하루
 * 1,000건뿐이라 다른 경로보다 훨씬 빡빡하게 잡는다.
 */
const MAX_PARTICIPANTS = 6;

export async function POST(request: Request) {
  let body: { participants?: unknown };
  try {
    body = (await request.json()) as { participants?: unknown };
  } catch {
    return NextResponse.json({ error: '잘못된 요청 본문입니다.' }, { status: 400 });
  }

  const participants = readParticipants(body.participants);
  if (!participants) {
    return NextResponse.json(
      { error: '참가자 정보가 올바르지 않습니다. 위치와 이동수단이 필요합니다.' },
      { status: 400 },
    );
  }
  if (participants.length > MAX_PARTICIPANTS) {
    // 사람이 늘수록 호출이 선형으로 는다. 여기서 막지 않으면 한 번에 쿼터가 크게 빠진다.
    return NextResponse.json(
      { error: `한 번에 ${MAX_PARTICIPANTS}명까지 계산할 수 있습니다.` },
      { status: 400 },
    );
  }

  const limit = await checkRateLimit(request, MIDPOINT_LIMIT);
  if (!limit.allowed) return tooManyRequests(MIDPOINT_LIMIT);

  try {
    return NextResponse.json(await findMidpoint(participants));
  } catch (cause) {
    if (cause instanceof NotEnoughParticipantsError || cause instanceof NoMeetingPlaceError) {
      return NextResponse.json({ error: cause.message }, { status: 422 });
    }
    if (cause instanceof MissingRestKeyError) {
      return NextResponse.json(
        { error: '서버에 KAKAO_REST_KEY가 설정되지 않았습니다.' },
        { status: 503 },
      );
    }
    console.error('[api/midpoint]', cause);
    return NextResponse.json({ error: '중간지점을 찾지 못했습니다.' }, { status: 502 });
  }
}

/** 하나라도 어긋나면 통째로 거절한다. 반쯤 맞는 참가자 목록으로 계산하면 답이 틀린다. */
function readParticipants(value: unknown): Participant[] | null {
  if (!Array.isArray(value) || value.length < 2) return null;

  const participants: Participant[] = [];
  for (const raw of value) {
    if (typeof raw !== 'object' || raw === null) return null;
    const { id, name, location, mode } = raw as Record<string, unknown>;

    if (typeof id !== 'string' || id.trim() === '') return null;
    if (!isTravelMode(mode) || mode === 'straight') return null;
    if (typeof location !== 'object' || location === null) return null;

    const { lat, lng } = location as Record<string, unknown>;
    if (typeof lat !== 'number' || typeof lng !== 'number') return null;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;

    participants.push({
      id,
      ...(typeof name === 'string' && name.trim() ? { name: name.trim() } : {}),
      location: { lat, lng },
      mode,
    });
  }
  return participants;
}
