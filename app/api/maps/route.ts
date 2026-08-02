import { randomBytes } from 'node:crypto';
import { NextResponse } from 'next/server';
import { toWkbPoint } from '@/lib/geo/projection';
import { DEFAULT_CENTER, DEFAULT_LEVEL, type LatLng } from '@/lib/map/types';
import { getServiceClient } from '@/lib/supabase/server';
import { createSlug } from '@/lib/slug';

/** 슬러그는 8자라 충돌 확률이 낮지만 0은 아니다. 몇 번 다시 뽑아 본다. */
const SLUG_ATTEMPTS = 5;
const UNIQUE_VIOLATION = '23505';

interface CreateBody {
  title?: unknown;
  center?: unknown;
  zoomLevel?: unknown;
}

export async function POST(request: Request) {
  const supabase = getServiceClient();
  if (!supabase) {
    return NextResponse.json(
      { error: 'Supabase가 설정되지 않았습니다. 로컬 저장으로 진행하세요.' },
      { status: 503 },
    );
  }

  let body: CreateBody = {};
  try {
    body = (await request.json()) as CreateBody;
  } catch {
    // 본문 없이 호출해도 기본값으로 만든다.
  }

  const center = readLatLng(body.center) ?? DEFAULT_CENTER;
  const zoomLevel = readZoom(body.zoomLevel);
  const title = typeof body.title === 'string' ? body.title.slice(0, 100) : '';
  const editToken = randomBytes(16).toString('hex');

  for (let attempt = 0; attempt < SLUG_ATTEMPTS; attempt++) {
    const slug = createSlug();
    const { error } = await supabase.from('maps').insert({
      slug,
      edit_token: editToken,
      center: toWkbPoint(center),
      zoom_level: zoomLevel,
      ...(title ? { title } : {}),
    });

    if (!error) return NextResponse.json({ slug, editToken }, { status: 201 });
    if (error.code !== UNIQUE_VIOLATION) {
      console.error('[api/maps] insert', error);
      return NextResponse.json({ error: '지도를 만들지 못했습니다.' }, { status: 502 });
    }
  }

  return NextResponse.json({ error: '슬러그 생성에 실패했습니다.' }, { status: 503 });
}

function readLatLng(value: unknown): LatLng | null {
  if (typeof value !== 'object' || value === null) return null;
  const { lat, lng } = value as Record<string, unknown>;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

function readZoom(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) return DEFAULT_LEVEL;
  return Math.min(14, Math.max(1, value));
}
