import { randomBytes, randomUUID } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { toWkbPoint } from '@/lib/geo/projection';
import { isUuid } from '@/lib/id';
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

/**
 * 테스트마다 새 id로 문서를 만든다.
 *
 * 고정 id를 여러 테스트가 공유하면 안 된다. 두 번째 지도에 같은 id를 넣으려는 순간
 * `save_map_document`의 교차 지도 방어(`where places.map_id = v_id`)에 걸려 행이
 * 조용히 빠진다. 그건 의도된 동작이고, 그 방어는 아래에서 따로 검증한다.
 */
function makeSample() {
  const ids = {
    stopA: randomUUID(),
    stopB: randomUUID(),
    placeA: randomUUID(),
    placeB: randomUUID(),
    placeC: randomUUID(),
    stroke: randomUUID(),
    label: randomUUID(),
  };

  const document: MapDocument = {
    title: '강남 저녁 코스',
    center: { lat: 37.4979, lng: 127.0276 },
    zoomLevel: 4,
    showCandidateLinks: true,
    showStopArrows: false,
    stops: [
      {
        id: ids.stopA,
        candidates: [
          {
            id: ids.placeA,
            name: '만남의 광장',
            location: { lat: 37.4979, lng: 127.0276 },
            pinColor: '#E24B4A',
          },
        ],
      },
      {
        // 후보가 여러 개인 단계. 어디로 갈지 아직 안 정한 상태를 담는다.
        id: ids.stopB,
        candidates: [
          {
            id: ids.placeB,
            name: '점심 국밥',
            address: '서울 강남구 강남대로 390',
            kakaoPlaceId: '12345',
            location: { lat: 37.499, lng: 127.029 },
            pinColor: '#E24B4A',
          },
          {
            id: ids.placeC,
            name: '2차 카페',
            location: { lat: 37.5005, lng: 127.0311 },
            pinColor: '#E24B4A',
          },
        ],
        // 후보가 여럿이므로 어느 쪽 기준으로 경로를 그릴지 정해 둔다.
        primaryId: ids.placeB,
      },
    ],
    legs: [
      {
        mode: 'walk',
        route: {
          points: [
            { lat: 37.4979, lng: 127.0276 },
            { lat: 37.4984, lng: 127.0283 },
            { lat: 37.499, lng: 127.029 },
          ],
          distanceM: 882,
          durationS: 868,
          fromPlaceId: ids.placeA,
          toPlaceId: ids.placeB,
          fetchedAt: '2026-08-01T00:00:00.000Z',
        },
      },
    ],
    strokes: [
      {
        id: ids.stroke,
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
        id: ids.label,
        text: '여기서 계단으로',
        location: { lat: 37.4982, lng: 127.028 },
        fontSize: 18,
        color: '#2FA35B',
      },
    ],
  };

  return { ids, document };
}

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
    expect(data).toMatchObject({ slug, stops: [], strokes: [], labels: [] });
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
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data } = await read(slug);

    expect(data.title).toBe('강남 저녁 코스');
    expect(data.zoomLevel).toBe(4);
    expect(data.center.lat).toBeCloseTo(37.4979, 6);
    expect(data.center.lng).toBeCloseTo(127.0276, 6);
  });

  it('단계 순서와 단계 안의 후보 순서를 모두 보존한다', async () => {
    // 단계 순서가 곧 핀 번호다. 뒤집히면 지도가 다른 뜻이 된다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data } = await read(slug);

    expect(data.stops).toHaveLength(2);
    expect(data.stops[0].candidates.map((p: { name: string }) => p.name)).toEqual(['만남의 광장']);
    expect(data.stops[1].candidates.map((p: { name: string }) => p.name)).toEqual([
      '점심 국밥',
      '2차 카페',
    ]);
  });

  it('한 단계에 후보를 여러 개 담을 수 있다', async () => {
    // 이 구조가 없으면 "2번은 점심인데 어디로 갈지 아직 안 정했다"를 표현할 수 없다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data } = await read(slug);

    expect(data.stops[1].candidates).toHaveLength(2);
  });

  it('후보의 좌표와 부가 정보를 보존한다', async () => {
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data } = await read(slug);

    const first = data.stops[0].candidates[0];
    expect(first.location.lat).toBeCloseTo(37.4979, 6);
    expect(first.location.lng).toBeCloseTo(127.0276, 6);
    // 지도에서 직접 찍은 핀에는 주소·kakaoPlaceId가 없다. null 키가 섞이면 안 된다.
    expect(first).not.toHaveProperty('address');
    expect(first).not.toHaveProperty('kakaoPlaceId');

    const second = data.stops[1].candidates[0];
    expect(second.address).toBe('서울 강남구 강남대로 390');
    expect(second.kakaoPlaceId).toBe('12345');
  });

  it('획의 좌표 순서와 스타일을 보존한다', async () => {
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
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
    const { document } = makeSample();
    await save(slug, editToken, document);
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
    const { document } = makeSample();
    await save(slug, editToken, {
      ...document,
      strokes: [
        { id: 'x', color: '#000', width: 4, zoomCreated: 3, path: [{ lat: 37.5, lng: 127 }] },
      ],
    });
    const { data } = await read(slug);
    expect(data.strokes).toEqual([]);
  });

  it('다시 저장하면 이전 내용을 남기지 않고 통째로 교체한다', async () => {
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    await save(slug, editToken, { ...document, stops: [], strokes: [], labels: [] });

    const { data } = await read(slug);
    expect(data.stops).toEqual([]);
    expect(data.strokes).toEqual([]);
    expect(data.labels).toEqual([]);
  });

  it('자동 선 설정을 저장하고 되돌려준다', async () => {
    // 만든 사람이 화살표를 껐다면 링크를 받은 사람에게도 꺼져 있어야 한다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data } = await read(slug);

    expect(data.showCandidateLinks).toBe(true);
    expect(data.showStopArrows).toBe(false);
  });

  it('설정이 빠진 문서를 받아도 기존 값을 지우지 않는다', async () => {
    // 예전 버전 클라이언트가 보낸 문서에는 이 필드가 없다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);

    const withoutFlags = { ...document } as Record<string, unknown>;
    delete withoutFlags.showCandidateLinks;
    delete withoutFlags.showStopArrows;
    await save(slug, editToken, withoutFlags as never);

    const { data } = await read(slug);
    expect(data.showStopArrows).toBe(false);
  });
});

describeIfConfigured('식별자 보존', () => {
  it('클라이언트가 만든 id를 그대로 쓴다', async () => {
    // 서버가 새 id를 발급하면 저장할 때마다 같은 핀의 id가 바뀐다. 그러면 특정 후보를
    // 참조하는 기능(댓글, 협업 편집)을 이 위에 올릴 수 없다.
    const { slug, editToken } = await createMap();
    const { ids, document } = makeSample();
    await save(slug, editToken, document);
    const { data } = await read(slug);

    expect(data.stops[0].candidates[0].id).toBe(ids.placeA);
    expect(data.stops[1].candidates.map((p: { id: string }) => p.id)).toEqual([
      ids.placeB,
      ids.placeC,
    ]);
    expect(data.strokes[0].id).toBe(ids.stroke);
    expect(data.labels[0].id).toBe(ids.label);
  });

  it('여러 번 저장해도 id가 바뀌지 않는다', async () => {
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data: first } = await read(slug);

    await save(slug, editToken, { ...document, title: '두 번째 저장' });
    const { data: second } = await read(slug);

    expect(second.stops[1].candidates.map((p: { id: string }) => p.id)).toEqual(
      first.stops[1].candidates.map((p: { id: string }) => p.id),
    );
    expect(second.strokes[0].id).toBe(first.strokes[0].id);
  });

  it('id가 uuid가 아니면 새로 발급해 저장을 살린다', async () => {
    // 예전 클라이언트가 만든 로컬 초안에는 32자 hex id가 남아 있다.
    // 그대로 캐스팅하면 저장 전체가 실패하므로 조용히 대체한다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    const { error } = await save(slug, editToken, {
      ...document,
      stops: [
        {
          id: 'acb5e6900445621ff5dd4f6b8a870983',
          candidates: [
            {
              id: 'acb5e6900445621ff5dd4f6b8a870984',
              name: '옛 초안 핀',
              location: { lat: 37.5, lng: 127 },
              pinColor: '#E24B4A',
            },
          ],
        },
      ],
    });

    expect(error).toBeNull();
    const { data } = await read(slug);
    expect(data.stops).toHaveLength(1);
    expect(isUuid(data.stops[0].candidates[0].id)).toBe(true);
  });

  it('후보 하나를 빼면 그 후보만 사라지고 나머지 id는 유지된다', async () => {
    const { slug, editToken } = await createMap();
    const { ids, document } = makeSample();
    await save(slug, editToken, document);

    await save(slug, editToken, {
      ...document,
      stops: document.stops.map((stop) => ({
        ...stop,
        candidates: stop.candidates.filter((place) => place.id !== ids.placeB),
      })),
    });

    const { data } = await read(slug);
    expect(data.stops[1].candidates.map((p: { id: string }) => p.id)).toEqual([ids.placeC]);
    expect(data.stops[0].candidates[0].id).toBe(ids.placeA);
  });

  it('단계 순서를 바꿔도 id는 그대로고 번호만 재계산된다', async () => {
    const { slug, editToken } = await createMap();
    const { ids, document } = makeSample();
    await save(slug, editToken, document);

    const reversed = [...document.stops].reverse();
    await save(slug, editToken, { ...document, stops: reversed });

    const { data } = await read(slug);
    expect(data.stops[0].candidates.map((p: { id: string }) => p.id)).toEqual([
      ids.placeB,
      ids.placeC,
    ]);
    expect(data.stops[1].candidates[0].id).toBe(ids.placeA);
  });
});

describeIfConfigured('교차 지도 방어', () => {
  it('다른 지도에 속한 id를 보내도 그 행을 끌어오지 못한다', async () => {
    // uuid 충돌은 사실상 없지만 일부러 남의 지도 행 id를 보낼 수는 있다.
    const victim = await createMap();
    const { ids, document } = makeSample();
    await save(victim.slug, victim.editToken, document);

    const attacker = await createMap();
    const { document: attackerDoc } = makeSample();
    await save(attacker.slug, attacker.editToken, {
      ...attackerDoc,
      stops: [
        {
          id: randomUUID(),
          candidates: [
            {
              id: ids.placeA, // 피해자 지도의 후보 id
              name: '가로챈 핀',
              location: { lat: 37.6, lng: 127.1 },
              pinColor: '#E24B4A',
            },
          ],
        },
      ],
    });

    // 피해자 지도는 그대로여야 한다.
    const { data: victimData } = await read(victim.slug);
    expect(victimData.stops[0].candidates[0].id).toBe(ids.placeA);
    expect(victimData.stops[0].candidates[0].name).toBe('만남의 광장');

    // 공격자 지도에는 그 후보가 들어가지 않는다.
    const { data: attackerData } = await read(attacker.slug);
    expect(attackerData.stops).toEqual([]);
  });
});

describeIfConfigured('편집 권한과 낙관적 잠금', () => {
  it('편집 토큰이 틀리면 저장을 거부한다', async () => {
    const { slug } = await createMap();
    const { document } = makeSample();
    const { error } = await save(slug, 'wrong-token', document);
    expect(error?.message).toContain('INVALID_EDIT_TOKEN');
  });

  it('없는 지도에 저장하면 실패한다', async () => {
    const { document } = makeSample();
    const { error } = await save('zztest-missing', 'any', document);
    expect(error?.message).toContain('MAP_NOT_FOUND');
  });

  it('오래된 updatedAt으로 저장하면 거부한다', async () => {
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);

    const { error } = await save(slug, editToken, document, '2020-01-01T00:00:00Z');
    expect(error?.message).toContain('STALE_DOCUMENT');
  });

  it('최신 updatedAt이면 저장을 허용한다', async () => {
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data: current } = await read(slug);

    const { error } = await save(slug, editToken, document, current.updatedAt);
    expect(error).toBeNull();
  });
});

describeIfConfigured('updated_at 트리거', () => {
  it('조회수가 올라도 updated_at은 그대로다', async () => {
    // 밀리면 편집기가 들고 있던 값이 낡은 것이 되어, 충돌이 아닌데도 409가 난다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data: before } = await read(slug);

    await supabase.rpc('increment_map_view', { p_slug: slug });
    const { data: after } = await read(slug);

    expect(after.viewCount).toBe(before.viewCount + 1);
    expect(after.updatedAt).toBe(before.updatedAt);
  });

  it('썸네일 URL을 기록해도 updated_at은 그대로다', async () => {
    // 밀리면 og_updated_at < updated_at 이 영원히 참이 되어 썸네일이 무한 재생성된다.
    const { slug, editToken } = await createMap();
    const { document } = makeSample();
    await save(slug, editToken, document);
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
    const { document } = makeSample();
    await save(slug, editToken, document);
    const { data: before } = await read(slug);

    await new Promise((resolve) => setTimeout(resolve, 1100));
    await save(slug, editToken, { ...document, title: '바뀐 제목' });
    const { data: after } = await read(slug);

    expect(after.title).toBe('바뀐 제목');
    expect(new Date(after.updatedAt).getTime()).toBeGreaterThan(
      new Date(before.updatedAt).getTime(),
    );
  });

  describe('대표 후보와 구간', () => {
    it('대표 후보를 왕복시킨다', async () => {
      const { slug, editToken } = await createMap();
      const { ids, document } = makeSample();
      await save(slug, editToken, document);
      const { data } = await read(slug);

      expect(data.stops[1].primaryId).toBe(ids.placeB);
    });

    it('대표를 안 정한 단계에는 primaryId 키가 없다', async () => {
      // "아직 안 정함"이 뜻을 갖는 상태다. 첫 후보를 말없이 대표로 삼으면 안 된다.
      const { slug, editToken } = await createMap();
      const { document } = makeSample();
      await save(slug, editToken, document);
      const { data } = await read(slug);

      expect(data.stops[0]).not.toHaveProperty('primaryId');
    });

    it('대표를 다른 후보로 옮길 수 있다', async () => {
      // 같은 단계 안에서 대표가 이동하면 업서트 도중 순간적으로 둘이 된다.
      // unique 인덱스를 걸면 여기서 저장이 통째로 실패한다.
      const { slug, editToken } = await createMap();
      const { ids, document } = makeSample();
      await save(slug, editToken, document);

      const moved = {
        ...document,
        stops: document.stops.map((stop, i) =>
          i === 1 ? { ...stop, primaryId: ids.placeC } : stop,
        ),
      };
      const { error } = await save(slug, editToken, moved);
      expect(error).toBeNull();

      const { data } = await read(slug);
      expect(data.stops[1].primaryId).toBe(ids.placeC);
    });

    it('구간의 모드와 경로를 왕복시킨다', async () => {
      const { slug, editToken } = await createMap();
      const { ids, document } = makeSample();
      await save(slug, editToken, document);
      const { data } = await read(slug);

      expect(data.legs).toHaveLength(1);
      expect(data.legs[0].mode).toBe('walk');
      expect(data.legs[0].route).toMatchObject({
        distanceM: 882,
        durationS: 868,
        fromPlaceId: ids.placeA,
        toPlaceId: ids.placeB,
      });
      expect(data.legs[0].route.points).toEqual(document.legs[0]!.route!.points);
    });

    it('구간 배열 길이는 단계 수보다 하나 적다', async () => {
      // 자리로 대응해야 한다. 중간이 비어도 배열이 앞으로 밀리면 안 된다.
      const { slug, editToken } = await createMap();
      const { document } = makeSample();
      await save(slug, editToken, { ...document, legs: [] });
      const { data } = await read(slug);

      expect(data.legs).toHaveLength(document.stops.length - 1);
      expect(data.legs[0].mode).toBe('straight');
      expect(data.legs[0]).not.toHaveProperty('route');
    });

    it('단계가 하나면 구간은 없다', async () => {
      const { slug, editToken } = await createMap();
      const { document } = makeSample();
      await save(slug, editToken, {
        ...document,
        stops: document.stops.slice(0, 1),
        legs: [],
      });
      const { data } = await read(slug);

      expect(data.legs).toEqual([]);
    });

    it('경로 없이 모드만 저장할 수 있다', async () => {
      // 길찾기가 실패해도 사용자가 고른 수단은 남아야 한다.
      const { slug, editToken } = await createMap();
      const { document } = makeSample();
      await save(slug, editToken, { ...document, legs: [{ mode: 'transit' }] });
      const { data } = await read(slug);

      expect(data.legs[0].mode).toBe('transit');
      expect(data.legs[0]).not.toHaveProperty('route');
    });

    it('자동차 모드는 남기되 외부 길찾기 결과는 DB에 저장하지 않는다', async () => {
      const { slug, editToken } = await createMap();
      const { ids, document } = makeSample();
      await save(slug, editToken, {
        ...document,
        legs: [
          {
            mode: 'car',
            route: {
              points: [
                { lat: 37.4979, lng: 127.0276 },
                { lat: 37.499, lng: 127.029 },
              ],
              distanceM: 1_842,
              durationS: 428,
              fromPlaceId: ids.placeA,
              toPlaceId: ids.placeB,
              fetchedAt: '2026-08-07T00:00:00.000Z',
            },
          },
        ],
      });
      const { data } = await read(slug);

      expect(data.legs[0].mode).toBe('car');
      expect(data.legs[0]).not.toHaveProperty('route');
    });

    it('대중교통 구간 배지를 왕복시킨다', async () => {
      const { slug, editToken } = await createMap();
      const { ids, document } = makeSample();
      await save(slug, editToken, {
        ...document,
        legs: [
          {
            mode: 'transit',
            route: {
              points: [
                { lat: 37.4979, lng: 127.0276 },
                { lat: 37.499, lng: 127.029 },
              ],
              distanceM: 951,
              durationS: 361,
              legs: [{ type: 'SUBWAY', guidance: '2호선 (강남 > 역삼)' }],
              fromPlaceId: ids.placeA,
              toPlaceId: ids.placeB,
              fetchedAt: '2026-08-01T00:00:00.000Z',
            },
          },
        ],
      });
      const { data } = await read(slug);

      expect(data.legs[0].route.legs).toEqual([
        { type: 'SUBWAY', guidance: '2호선 (강남 > 역삼)' },
      ]);
    });

    it('구간이 사라지면 저장된 행도 지워진다', async () => {
      const { slug, editToken } = await createMap();
      const { document } = makeSample();
      await save(slug, editToken, document);

      // 단계를 하나로 줄이면 구간이 남을 자리가 없다.
      await save(slug, editToken, { ...document, stops: document.stops.slice(0, 1), legs: [] });
      const { count } = await supabase
        .from('stop_legs')
        .select('*', { count: 'exact', head: true })
        .eq('map_id', (await supabase.from('maps').select('id').eq('slug', slug).single()).data!.id);

      expect(count).toBe(0);
    });
  });
});
