-- T12 서버 저장 (설계안 §6.1 "지도 단위 전체 스냅샷 PATCH")
--
-- 0001을 적용한 뒤 이 파일을 이어서 적용한다.
--
-- 여기서 하는 일 세 가지:
--   1) 0001의 RLS 정책에 있던 edit_token 노출 구멍을 막는다
--   2) places에 mode_to_next를 추가한다
--   3) 지도 전체를 한 번에 읽고 쓰는 RPC 두 개를 만든다

-- ---------------------------------------------------------------------------
-- 1) 0001의 보안 구멍 차단
--
-- 0001은 `create policy maps_read on maps for select using (true)`를 걸었다.
-- RLS 정책은 컬럼 단위가 아니므로, 이 정책 아래에서는 anon key로
-- `select edit_token from maps`가 그대로 통한다. 즉 누구나 남의 지도의 편집 토큰을
-- 읽어 편집할 수 있다. maps_public 뷰를 만들어 뒀지만 뷰는 원본 테이블 직접 조회를
-- 막지 못하므로 방어가 되지 않는다.
--
-- 해결: 모든 테이블의 읽기 정책을 없애 기본 거부로 만들고, 읽기는 edit_token을
-- 애초에 반환하지 않는 security definer 함수로만 열어 준다.
-- ---------------------------------------------------------------------------
drop policy if exists maps_read on maps;
drop policy if exists places_read on places;
drop policy if exists strokes_read on strokes;
drop policy if exists labels_read on labels;
drop policy if exists segments_read on segments;

drop view if exists maps_public;

-- ---------------------------------------------------------------------------
-- 2) 이동수단
--
-- 설계안은 segments 테이블에 mode를 두지만, 클라이언트의 유일한 근거는
-- "places 배열 순서 + 각 핀의 다음 구간 이동수단"이다. 두 곳에 나눠 두면 동기화
-- 버그만 생기므로 순서와 함께 places에 둔다.
--
-- segments 테이블은 지우지 않는다. 설계안 §5.1의 style='manual'(사용자가 그린 선으로
-- 연결선을 대체) 과 실제 경로 좌표를 저장할 때 필요해진다. 지금은 비어 있다.
-- ---------------------------------------------------------------------------
alter table places
  add column if not exists mode_to_next text not null default 'walk';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'places_mode_to_next_check'
  ) then
    alter table places
      add constraint places_mode_to_next_check
      check (mode_to_next in ('walk', 'car', 'transit'));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3-a) 읽기
--
-- 지도 하나를 앱이 그대로 쓰는 모양의 JSON으로 반환한다. edit_token은 절대 넣지 않는다.
-- geography → {lat, lng} 변환을 여기서 끝내므로 클라이언트는 PostGIS를 몰라도 된다.
-- ---------------------------------------------------------------------------
create or replace function coords_from_line(g geography)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('lat', st_y(d.geom), 'lng', st_x(d.geom))
      order by d.path[1]
    ),
    '[]'::jsonb
  )
  from st_dumppoints(g::geometry) as d;
$$;

create or replace function get_map_document(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'slug',      m.slug,
    'title',     m.title,
    'center',    jsonb_build_object(
                   'lat', st_y(m.center::geometry),
                   'lng', st_x(m.center::geometry)
                 ),
    'zoomLevel', m.zoom_level,
    'viewCount', m.view_count,
    'updatedAt', m.updated_at,
    'places', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id',           p.id,
          'name',         p.name,
          'address',      p.address,
          'kakaoPlaceId', p.kakao_place_id,
          'memo',         p.memo,
          'pinColor',     p.pin_color,
          'modeToNext',   p.mode_to_next,
          'location', jsonb_build_object(
            'lat', st_y(p.location::geometry),
            'lng', st_x(p.location::geometry)
          )
        ))
        order by p.order_no
      )
      from places p where p.map_id = m.id
    ), '[]'::jsonb),
    'strokes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',          s.id,
          'color',       s.color,
          'width',       s.width,
          'zoomCreated', s.zoom_created,
          'path',        coords_from_line(s.geom)
        )
        order by s.z_index, s.created_at
      )
      from strokes s where s.map_id = m.id
    ), '[]'::jsonb),
    'labels', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',       l.id,
          'text',     l.text,
          'fontSize', l.font_size,
          'color',    l.color,
          'location', jsonb_build_object(
            'lat', st_y(l.location::geometry),
            'lng', st_x(l.location::geometry)
          )
        )
      )
      from labels l where l.map_id = m.id
    ), '[]'::jsonb)
  )
  from maps m
  where m.slug = p_slug;
$$;

-- 뷰어는 로그인 없이 열려야 하므로 읽기 함수는 anon에게도 연다.
grant execute on function get_map_document(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3-b) 쓰기
--
-- 설계안 §6.1대로 변경분이 아니라 지도 전체를 통째로 교체한다. 자식 행을 지우고
-- 다시 넣으므로 한 트랜잭션 안에서 끝나야 하고, 그래서 함수로 만든다.
--
-- p_expected_updated_at은 낙관적 잠금이다. 같은 편집 토큰으로 두 탭을 열어 두면
-- 나중 저장이 앞선 저장을 통째로 덮어쓰기 때문에 필요하다. null이면 검사를 건너뛴다.
-- ---------------------------------------------------------------------------
create or replace function save_map_document(
  p_slug                text,
  p_edit_token          text,
  p_document            jsonb,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id         uuid;
  v_token      text;
  v_updated_at timestamptz;
begin
  select id, edit_token, updated_at
    into v_id, v_token, v_updated_at
    from maps where slug = p_slug
    for update;

  if not found then
    raise exception 'MAP_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_token is distinct from p_edit_token then
    raise exception 'INVALID_EDIT_TOKEN' using errcode = 'P0001';
  end if;

  if p_expected_updated_at is not null and v_updated_at > p_expected_updated_at then
    raise exception 'STALE_DOCUMENT' using errcode = 'P0003';
  end if;

  update maps set
    title      = coalesce(nullif(p_document->>'title', ''), title),
    center     = st_setsrid(st_makepoint(
                   (p_document->'center'->>'lng')::float8,
                   (p_document->'center'->>'lat')::float8
                 ), 4326)::geography,
    zoom_level = coalesce((p_document->>'zoomLevel')::int, zoom_level)
  where id = v_id;

  -- 스냅샷 교체. segments는 places FK에 걸려 함께 지워진다.
  delete from places  where map_id = v_id;
  delete from strokes where map_id = v_id;
  delete from labels  where map_id = v_id;

  insert into places (map_id, order_no, name, address, kakao_place_id, location, memo, pin_color, mode_to_next)
  select
    v_id,
    (t.ord - 1)::int,
    t.item->>'name',
    t.item->>'address',
    t.item->>'kakaoPlaceId',
    st_setsrid(st_makepoint(
      (t.item->'location'->>'lng')::float8,
      (t.item->'location'->>'lat')::float8
    ), 4326)::geography,
    t.item->>'memo',
    coalesce(t.item->>'pinColor', 'coral'),
    coalesce(t.item->>'modeToNext', 'walk')
  from jsonb_array_elements(coalesce(p_document->'places', '[]'::jsonb))
       with ordinality as t(item, ord)
  where t.item->'location' is not null;

  -- LineString은 점이 2개 이상이어야 한다. RDP가 보장하지만 방어한다.
  insert into strokes (map_id, geom, color, width, zoom_created, z_index)
  select
    v_id,
    st_setsrid(st_makeline(array(
      select st_makepoint((pt->>'lng')::float8, (pt->>'lat')::float8)
      from jsonb_array_elements(t.item->'path') as pt
    )), 4326)::geography,
    coalesce(t.item->>'color', '#E24B4A'),
    coalesce((t.item->>'width')::int, 4),
    coalesce((t.item->>'zoomCreated')::int, 3),
    (t.ord - 1)::int
  from jsonb_array_elements(coalesce(p_document->'strokes', '[]'::jsonb))
       with ordinality as t(item, ord)
  where jsonb_array_length(coalesce(t.item->'path', '[]'::jsonb)) >= 2;

  insert into labels (map_id, location, text, font_size, color)
  select
    v_id,
    st_setsrid(st_makepoint(
      (item->'location'->>'lng')::float8,
      (item->'location'->>'lat')::float8
    ), 4326)::geography,
    item->>'text',
    coalesce((item->>'fontSize')::int, 14),
    coalesce(item->>'color', '#2C2C2A')
  from jsonb_array_elements(coalesce(p_document->'labels', '[]'::jsonb)) as item
  where item->'location' is not null and coalesce(item->>'text', '') <> '';

  return get_map_document(p_slug);
end;
$$;

-- 쓰기는 Route Handler(service role)만 호출한다. 편집 토큰 검증이 서버 안에 있어야
-- 브라우저에서 토큰을 바꿔 가며 시도하는 것을 막을 수 있다.
revoke execute on function save_map_document(text, text, jsonb, timestamptz) from public, anon, authenticated;
grant  execute on function save_map_document(text, text, jsonb, timestamptz) to service_role;
