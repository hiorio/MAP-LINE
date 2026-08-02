import { randomBytes } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { toWkbPoint } from '@/lib/geo/projection';
import type { MapDocument } from './types';

/**
 * 실제 Supabase를 대상으로 하는 통합 테스트.
 *
 * 이 프로젝트에서 가장 깨지기 쉬운 코드는 마이그레이션의 PL/pgSQL이다. 순수 함수는
 * 단위 테스트로 덮이지만, PostGIS 왕복·순서 보존·편집 토큰 검증·낙관적 잠금은
 * 실제 DB에 넣어 봐야 알 수 있다. 스키마를 건드린 뒤 이 파일이 통과하는지 보면 된다.
 *
 * 환경 변수가 없으면 통째로 스킵한다. 새로 받은 개발 환경에서 테스트가 빨갛게 뜨는 것보다
 * 조용히 넘어가는 편이 낫다.
 *
 * 만든 지도는 afterAll에서 지운다. 실패해도 남지 않도록 생성 즉시 목록에 기록한다.
 */
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const configured = Boolean(url && key);

const describeIfConfigured = configured ? describe : describe.skip;

/** 테스트 지도임을 알아볼 수 있게 접두어를 붙인다. */
const TEST_SLUG_PREFIX = 'zztest';

let supabase: SupabaseClient;
const createdSlugs: string[] = [];

async function createMap(center = { lat: 37.4979, lng: 127.0276 }, zoom = 3) {
  const slug = `${TEST_SLUG_PREFIX}${randomBytes(3).toString('hex')}`;
  const editToken = randomBytes(16).toString('hex');
  createdSlugs.push(slug);

  const { error } = await supabase.from('maps').insert({
    slug,
    edit_token: editToken,
    center: toWkbPoint(center),
    zoom_level: zoom,
  });
  if (error) throw new Error(`테스트 지도 생성 실패: ${error.message}`);
  return { slug, editToken };
}

function save(slug: string, editToken: string, document: MapDocument, expectedUpdatedAt?: string) {
  return supabase.rpc('save_map_document', {
    p_slug: slug,
    p_edit_token: editToken,
    p_document: document,
    p_expected_updated_at: expectedUpdatedAt ?? null,
  });
}

function read(slug: string) {
  return supabase.rpc('get_map_document', { p_slug: slug });
}

const sampleDocument: MapDocument = {
  title: '강남 저녁 코스',
  center: { lat: 37.4979, lng: 127.0276 },
  zoomLevel: 4,
  places: [
    {
      id: 'client-a',
      name: '만남의 광장',
      location: { lat: 37.4979, lng: 127.0276 },
      pinColor: '#E24B4A',
      modeToNext: 'transit',
    },
    {
      id: 'client-b',
      name: '점심 국밥',
      address: '서울 강남구 강남대로 390',
      kakaoPlaceId: '12345',
      location: { lat: 37.499, lng: 127.029 },
      pinColor: '#E24B4A',
      modeToNext: 'walk',
    },
    {
      id: 'client-c',
      name: '2차 카페',
      location: { lat: 37.5005, lng: 127.0311 },
      pinColor: '#E24B4A',
      modeToNext: 'car',
    },
  ],
  strokes: [
    {
      id: 'client-s1',
      color: '#2D6BE4',
      width: 9,
      zoomCreated: 4,
      path: [
        { lat: 37.4979, lng: 127.0276 },
        { lat: 37.4985, lng: 127.0281 },
        { lat: 37.499, lng: 127.029 },
      ],
    },
  ],
  labels: [
    {
      id: 'client-l1',
      text: '여기서 계단으로',
      location: { lat: 37.4982, lng: 127.028 },
      fontSize: 18,
      color: '#2FA35B',
    },
  ],
};

beforeAll(() => {
  if (!configured) return;
  supabase = createClient(url!, key!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
});

afterAll(async () => {
  if (!configured || createdSlugs.length === 0) return;
  await supabase.from('maps').delete().in('slug', createdSlugs);
});

describeIfConfigured('save_map_document / get_map_document 왕복', () => {
  it('빈 지도는 빈 배열들을 돌려준다', async () => {
    const { slug } = await createMap();
    const { data, error } = await read(slug);

    expect(error).toBeNull();
    expect(data).toMatchObject({ slug, places: [], strokes: [], labels: [] });
  });

  it('없는 슬러그는 null을 돌려준다', async () => {
    const { data } = await read('zztest-does-not-exist');
    expect(data).toBeNull();
  });

  it('편집 토큰을 반환하지 않는다', async () => {
    // RLS를 잠근 뒤 읽기는 이 함수로만 열려 있다. 여기서 토큰이 새면 누구나 남의 지도를 고친다.
    const { slug } = await createMap();
    const { data } = await read(slug);
    expect(JSON.stringify(data)).not.toContain('edit_token');
    expect(data).not.toHaveProperty('editToken');
  });

  it('제목·중심·줌을 저장하고 되돌려준다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data } = await read(slug);

    expect(data.title).toBe('강남 저녁 코스');
    expect(data.zoomLevel).toBe(4);
    expect(data.center.lat).toBeCloseTo(37.4979, 6);
    expect(data.center.lng).toBeCloseTo(127.0276, 6);
  });

  it('핀의 순서를 배열 순서 그대로 보존한다', async () => {
    // 순서가 곧 핀 번호이자 연결선 방향이다. 뒤집히면 지도가 다른 뜻이 된다.
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data } = await read(slug);

    expect(data.places.map((p: { name: string }) => p.name)).toEqual([
      '만남의 광장',
      '점심 국밥',
      '2차 카페',
    ]);
  });

  it('핀의 좌표와 부가 정보를 보존한다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data } = await read(slug);

    const [first, second] = data.places;
    expect(first.location.lat).toBeCloseTo(37.4979, 6);
    expect(first.location.lng).toBeCloseTo(127.0276, 6);
    expect(first.modeToNext).toBe('transit');
    // 지도에서 직접 찍은 핀에는 주소·kakaoPlaceId가 없다. null 키가 섞이면 안 된다.
    expect(first).not.toHaveProperty('address');
    expect(first).not.toHaveProperty('kakaoPlaceId');

    expect(second.address).toBe('서울 강남구 강남대로 390');
    expect(second.kakaoPlaceId).toBe('12345');
  });

  it('획의 좌표 순서와 스타일을 보존한다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data } = await read(slug);

    const stroke = data.strokes[0];
    expect(stroke.color).toBe('#2D6BE4');
    expect(stroke.width).toBe(9);
    expect(stroke.zoomCreated).toBe(4);
    expect(stroke.path).toHaveLength(3);
    // LineString의 점 순서가 뒤집히면 그림이 거꾸로 그려진다.
    expect(stroke.path[0].lat).toBeCloseTo(37.4979, 6);
    expect(stroke.path[2].lat).toBeCloseTo(37.499, 6);
  });

  it('라벨의 글자·크기·색을 보존한다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data } = await read(slug);

    expect(data.labels[0]).toMatchObject({
      text: '여기서 계단으로',
      fontSize: 18,
      color: '#2FA35B',
    });
  });

  it('점이 2개 미만인 획은 버린다', async () => {
    // geography(LineString)은 점 2개 이상을 요구한다. 통과시키면 저장 자체가 실패한다.
    const { slug, editToken } = await createMap();
    await save(slug, editToken, {
      ...sampleDocument,
      strokes: [
        { id: 'x', color: '#000', width: 4, zoomCreated: 3, path: [{ lat: 37.5, lng: 127 }] },
      ],
    });
    const { data } = await read(slug);
    expect(data.strokes).toEqual([]);
  });

  it('다시 저장하면 이전 내용을 남기지 않고 통째로 교체한다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    await save(slug, editToken, { ...sampleDocument, places: [], strokes: [], labels: [] });

    const { data } = await read(slug);
    expect(data.places).toEqual([]);
    expect(data.strokes).toEqual([]);
    expect(data.labels).toEqual([]);
  });
});

describeIfConfigured('편집 권한과 낙관적 잠금', () => {
  it('편집 토큰이 틀리면 저장을 거부한다', async () => {
    const { slug } = await createMap();
    const { error } = await save(slug, 'wrong-token', sampleDocument);
    expect(error?.message).toContain('INVALID_EDIT_TOKEN');
  });

  it('없는 지도에 저장하면 실패한다', async () => {
    const { error } = await save('zztest-missing', 'any', sampleDocument);
    expect(error?.message).toContain('MAP_NOT_FOUND');
  });

  it('오래된 updatedAt으로 저장하면 거부한다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);

    const { error } = await save(slug, editToken, sampleDocument, '2020-01-01T00:00:00Z');
    expect(error?.message).toContain('STALE_DOCUMENT');
  });

  it('최신 updatedAt이면 저장을 허용한다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data: current } = await read(slug);

    const { error } = await save(slug, editToken, sampleDocument, current.updatedAt);
    expect(error).toBeNull();
  });
});

describeIfConfigured('updated_at 트리거', () => {
  it('조회수가 올라도 updated_at은 그대로다', async () => {
    // 밀리면 편집기가 들고 있던 값이 낡은 것이 되어, 충돌이 아닌데도 409가 난다.
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data: before } = await read(slug);

    await supabase.rpc('increment_map_view', { p_slug: slug });
    const { data: after } = await read(slug);

    expect(after.viewCount).toBe(before.viewCount + 1);
    expect(after.updatedAt).toBe(before.updatedAt);
  });

  it('썸네일 URL을 기록해도 updated_at은 그대로다', async () => {
    // 밀리면 og_updated_at < updated_at 이 영원히 참이 되어 썸네일이 무한 재생성된다.
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data: before } = await read(slug);

    await supabase.rpc('set_map_og_image', { p_slug: slug, p_url: 'https://example.com/x.png' });
    const { data: after } = await read(slug);

    expect(after.ogImageUrl).toBe('https://example.com/x.png');
    expect(after.updatedAt).toBe(before.updatedAt);
    expect(new Date(after.ogUpdatedAt).getTime()).toBeGreaterThanOrEqual(
      new Date(after.updatedAt).getTime(),
    );
  });

  it('내용이 바뀌면 updated_at이 갱신된다', async () => {
    const { slug, editToken } = await createMap();
    await save(slug, editToken, sampleDocument);
    const { data: before } = await read(slug);

    await new Promise((resolve) => setTimeout(resolve, 1100));
    await save(slug, editToken, { ...sampleDocument, title: '바뀐 제목' });
    const { data: after } = await read(slug);

    expect(after.title).toBe('바뀐 제목');
    expect(new Date(after.updatedAt).getTime()).toBeGreaterThan(
      new Date(before.updatedAt).getTime(),
    );
  });
});
