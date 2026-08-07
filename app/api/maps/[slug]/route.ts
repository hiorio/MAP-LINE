import { NextResponse } from 'next/server';
import { stripNonPersistableRouteCaches } from '@/lib/map/persistencePolicy';
import { getServiceClient } from '@/lib/supabase/server';

/** save_map_document가 raise하는 코드. 0002 마이그레이션 참고. */
const MAP_NOT_FOUND = 'P0002';
const INVALID_EDIT_TOKEN = 'P0001';
const STALE_DOCUMENT = 'P0003';

type Params = { params: Promise<{ slug: string }> };

function unconfigured() {
  return NextResponse.json(
    { error: 'Supabase가 설정되지 않았습니다.' },
    { status: 503 },
  );
}

export async function GET(_request: Request, { params }: Params) {
  const supabase = getServiceClient();
  if (!supabase) return unconfigured();

  const { slug } = await params;
  const { data, error } = await supabase.rpc('get_map_document', { p_slug: slug });

  if (error) {
    console.error('[api/maps/:slug] GET', error);
    return NextResponse.json({ error: '지도를 불러오지 못했습니다.' }, { status: 502 });
  }
  if (!data) {
    return NextResponse.json({ error: '지도를 찾을 수 없습니다.' }, { status: 404 });
  }
  return NextResponse.json(data);
}

export async function PATCH(request: Request, { params }: Params) {
  const supabase = getServiceClient();
  if (!supabase) return unconfigured();

  const { slug } = await params;
  const editToken = request.headers.get('X-Edit-Token');
  if (!editToken) {
    return NextResponse.json({ error: '편집 토큰이 없습니다.' }, { status: 401 });
  }

  let document: unknown;
  let expectedUpdatedAt: string | null = null;
  try {
    const body = (await request.json()) as { document?: unknown; expectedUpdatedAt?: unknown };
    document = body.document;
    if (typeof body.expectedUpdatedAt === 'string') expectedUpdatedAt = body.expectedUpdatedAt;
  } catch {
    return NextResponse.json({ error: '잘못된 요청 본문입니다.' }, { status: 400 });
  }

  if (typeof document !== 'object' || document === null) {
    return NextResponse.json({ error: 'document가 없습니다.' }, { status: 400 });
  }

  const { data, error } = await supabase.rpc('save_map_document', {
    p_slug: slug,
    p_edit_token: editToken,
    p_document: stripNonPersistableRouteCaches(document as Record<string, unknown>),
    p_expected_updated_at: expectedUpdatedAt,
  });

  if (error) {
    if (error.code === MAP_NOT_FOUND) {
      return NextResponse.json({ error: '지도를 찾을 수 없습니다.' }, { status: 404 });
    }
    if (error.code === INVALID_EDIT_TOKEN) {
      return NextResponse.json({ error: '편집 권한이 없습니다.' }, { status: 403 });
    }
    if (error.code === STALE_DOCUMENT) {
      // 다른 탭이 더 최신 내용을 이미 저장했다. 덮어쓰지 않고 알린다.
      return NextResponse.json(
        { error: '다른 곳에서 먼저 저장되었습니다. 새로고침 후 다시 편집하세요.' },
        { status: 409 },
      );
    }
    console.error('[api/maps/:slug] PATCH', error);
    return NextResponse.json({ error: '저장하지 못했습니다.' }, { status: 502 });
  }

  return NextResponse.json(data);
}

export async function DELETE(request: Request, { params }: Params) {
  const supabase = getServiceClient();
  if (!supabase) return unconfigured();

  const { slug } = await params;
  const editToken = request.headers.get('X-Edit-Token');
  if (!editToken) {
    return NextResponse.json({ error: '편집 토큰이 없습니다.' }, { status: 401 });
  }

  // 토큰이 맞는 행만 지운다. 조회 후 삭제로 나누면 그 사이에 바뀔 수 있다.
  const { data, error } = await supabase
    .from('maps')
    .delete()
    .eq('slug', slug)
    .eq('edit_token', editToken)
    .select('slug');

  if (error) {
    console.error('[api/maps/:slug] DELETE', error);
    return NextResponse.json({ error: '삭제하지 못했습니다.' }, { status: 502 });
  }
  if (!data || data.length === 0) {
    return NextResponse.json({ error: '지도가 없거나 편집 권한이 없습니다.' }, { status: 403 });
  }
  return NextResponse.json({ slug, deleted: true });
}
