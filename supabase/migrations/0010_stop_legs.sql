-- 단계 사이 동선을 직선이 아니라 실제 경로로 그릴 수 있게 한다.
--
-- 두 가지가 필요하다.
--
-- 1) 대표 후보(places.is_primary)
--    후보들의 중간지점은 평균 좌표라 건물도 길도 아닌 가상의 점이고, 거기서 길찾기를
--    시작할 수 없다. 그렇다고 첫 후보를 말없이 쓰면 나머지 후보가 동선에서 빠진 것처럼
--    보인다. 어디를 기준으로 그린 경로인지 사람이 정하게 한다.
--    후보가 하나뿐인 단계는 고를 것이 없으므로 지정 없이도 그것이 대표다.
--
-- 2) 구간(stop_legs)
--    한 행이 stops[i] → stops[i+1] 하나에 대응한다. 컬럼이 두 종류로 나뉜다.
--    - mode: 사용자의 의도다. 우리 데이터이므로 언제나 보존한다.
--    - geom/distance_m/duration_s/transit_legs/fetched_at: 카카오에서 받아 온 캐시다.
--      카카오 개발자 운영정책 제5조 20호는 캐시를 금지하지 않지만, 사용자 환경 개선
--      목적일 것과 최신 상태로 유지할 것을 요구한다. 그래서 언제 어떤 두 지점을 기준으로
--      받았는지(from_place_id/to_place_id/fetched_at)를 함께 남겨, 끝점이 바뀌거나
--      오래되면 편집기가 다시 받아 갱신할 수 있게 한다. 버려도 mode는 살아남는다.
--
-- 자동차는 넣지 않는다. 카카오모빌리티의 자동차 길찾기는 결과의 자체 저장이 정책상
-- 막혀 있어, 링크를 나중에 여는 이 제품의 저장 모델과 맞지 않는다.

alter table places
  add column if not exists is_primary boolean not null default false;

comment on column places.is_primary is
  '이 단계의 대표 후보인가. 실제 경로의 출발·도착점이 된다.';

-- 한 단계에 대표가 하나뿐인 것은 unique 인덱스로 막지 않는다.
--
-- 대표를 A에서 B로 옮기면 저장은 후보 전체를 한 문장으로 업서트하는데, 그 안에서
-- B가 A보다 먼저 처리되면 순간적으로 대표가 둘이 되어 제약에 걸린다. 부분 인덱스는
-- deferrable 제약으로 만들 수도 없어 피할 방법이 없다.
-- 대신 save_map_document가 단계마다 primaryId 하나만 보고 is_primary를 정하므로
-- 만들어지는 과정에서 이미 하나임이 보장된다. 읽을 때도 첫 행만 취해 방어한다.

create table if not exists stop_legs (
  map_id          uuid not null references maps(id) on delete cascade,
  from_stop_index int  not null,

  -- 사용자의 의도
  mode text not null default 'straight',

  -- 카카오에서 받아 온 캐시
  from_place_id uuid,
  to_place_id   uuid,
  geom          geography(linestring, 4326),
  distance_m    int,
  duration_s    int,
  transit_legs  jsonb,
  fetched_at    timestamptz,

  primary key (map_id, from_stop_index),
  constraint stop_legs_mode_check check (mode in ('straight', 'walk', 'transit', 'bicycle'))
);

comment on table stop_legs is
  '단계 사이 구간. mode는 사용자 데이터, 나머지는 길찾기 응답 캐시다.';

-- 0002에서 읽기 정책을 전부 없애 기본 거부로 두었다. 새 테이블도 같은 규칙을 따른다.
-- 읽기는 get_map_document(security definer)로만 연다.
alter table stop_legs enable row level security;

-- ---------------------------------------------------------------------------
-- 읽기
-- ---------------------------------------------------------------------------
create or replace function get_map_document(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'slug',        m.slug,
    'title',       m.title,
    'center',      jsonb_build_object(
                     'lat', st_y(m.center::geometry),
                     'lng', st_x(m.center::geometry)
                   ),
    'zoomLevel',   m.zoom_level,
    'viewCount',   m.view_count,
    'updatedAt',   m.updated_at,
    'ogImageUrl',  m.og_image_url,
    'ogUpdatedAt', m.og_updated_at,
    'showCandidateLinks', m.show_candidate_links,
    'showStopArrows',     m.show_stop_arrows,
    'stops', coalesce((
      select jsonb_agg(grouped.stop order by grouped.stop_index)
      from (
        select
          p.stop_index,
          jsonb_strip_nulls(jsonb_build_object(
            -- 단계 id는 저장하지 않는다. 첫 후보의 id로 안정적으로 되살린다.
            'id', (array_agg(p.id order by p.order_no))[1],
            -- 대표를 안 정했으면 키 자체가 빠진다. "아직 안 정함"이 뜻을 갖는 상태다.
            'primaryId', (array_agg(p.id) filter (where p.is_primary))[1],
            'candidates', jsonb_agg(
              jsonb_strip_nulls(jsonb_build_object(
                'id',           p.id,
                'name',         p.name,
                'address',      p.address,
                'kakaoPlaceId', p.kakao_place_id,
                'memo',         p.memo,
                'pinColor',     p.pin_color,
                'location', jsonb_build_object(
                  'lat', st_y(p.location::geometry),
                  'lng', st_x(p.location::geometry)
                )
              ))
              order by p.order_no
            )
          )) as stop
        from places p
        where p.map_id = m.id
        group by p.stop_index
      ) grouped
    ), '[]'::jsonb),
    -- 구간은 단계 배열과 자리로 대응해야 한다. 저장된 행만 모으면 중간이 비었을 때
    -- 배열이 앞으로 밀려 엉뚱한 구간에 모드가 붙는다. 단계 수만큼 자리를 만들어 채운다.
    'legs', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'mode', coalesce(l.mode, 'straight'),
          'route', case
            when l.geom is null or l.fetched_at is null then null
            else jsonb_strip_nulls(jsonb_build_object(
              'points',      coords_from_line(l.geom),
              'distanceM',   l.distance_m,
              'durationS',   l.duration_s,
              'legs',        l.transit_legs,
              'fromPlaceId', l.from_place_id,
              'toPlaceId',   l.to_place_id,
              'fetchedAt',   l.fetched_at
            ))
          end
        )) order by slot.i
      )
      from generate_series(
        0,
        (select count(distinct p.stop_index) from places p where p.map_id = m.id)::int - 2
      ) as slot(i)
      left join stop_legs l on l.map_id = m.id and l.from_stop_index = slot.i
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

-- ---------------------------------------------------------------------------
-- 쓰기: 기존 저장에 대표 후보와 구간을 더한다.
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
    zoom_level = coalesce((p_document->>'zoomLevel')::int, zoom_level),
    show_candidate_links = coalesce((p_document->>'showCandidateLinks')::boolean, show_candidate_links),
    show_stop_arrows     = coalesce((p_document->>'showStopArrows')::boolean, show_stop_arrows)
  where id = v_id;

  -- 단계 --------------------------------------------------------------------
  with parsed as (
    select
      safe_uuid(candidate->>'id')                                 as id,
      (stop.ord - 1)::int                                         as stop_index,
      (candidate_ord.ord - 1)::int                                as order_no,
      candidate->>'name'                                          as name,
      candidate->>'address'                                       as address,
      candidate->>'kakaoPlaceId'                                  as kakao_place_id,
      st_setsrid(st_makepoint(
        (candidate->'location'->>'lng')::float8,
        (candidate->'location'->>'lat')::float8
      ), 4326)::geography                                         as location,
      candidate->>'memo'                                          as memo,
      coalesce(candidate->>'pinColor', 'coral')                   as pin_color,
      -- 대표가 없으면 primaryId가 null이고, null = null은 참이 아니므로 전부 false가 된다.
      (stop.item->>'primaryId') is not null
        and candidate->>'id' = stop.item->>'primaryId'            as is_primary
    from jsonb_array_elements(coalesce(p_document->'stops', '[]'::jsonb))
         with ordinality as stop(item, ord)
    cross join lateral jsonb_array_elements(
      coalesce(stop.item->'candidates', '[]'::jsonb)
    ) with ordinality as candidate_ord(candidate, ord)
    where candidate->'location' is not null
  ),
  removed as (
    delete from places
     where map_id = v_id and id not in (select id from parsed)
  )
  insert into places (id, map_id, stop_index, order_no, name, address, kakao_place_id, location, memo, pin_color, is_primary)
  select id, v_id, stop_index, order_no, name, address, kakao_place_id, location, memo, pin_color, is_primary
  from parsed
  on conflict (id) do update set
    stop_index     = excluded.stop_index,
    order_no       = excluded.order_no,
    name           = excluded.name,
    address        = excluded.address,
    kakao_place_id = excluded.kakao_place_id,
    location       = excluded.location,
    memo           = excluded.memo,
    pin_color      = excluded.pin_color,
    is_primary     = excluded.is_primary
  -- 다른 지도의 행을 끌어오지 못하게 막는다.
  where places.map_id = v_id;

  -- 구간 --------------------------------------------------------------------
  with parsed as (
    select
      (t.ord - 1)::int                                     as from_stop_index,
      coalesce(t.item->>'mode', 'straight')                as mode,
      safe_uuid(t.item->'route'->>'fromPlaceId')           as from_place_id,
      safe_uuid(t.item->'route'->>'toPlaceId')             as to_place_id,
      case
        when jsonb_array_length(coalesce(t.item->'route'->'points', '[]'::jsonb)) >= 2
        then st_setsrid(st_makeline(array(
               select st_makepoint((pt->>'lng')::float8, (pt->>'lat')::float8)
               from jsonb_array_elements(t.item->'route'->'points') as pt
             )), 4326)::geography
      end                                                  as geom,
      (t.item->'route'->>'distanceM')::int                 as distance_m,
      (t.item->'route'->>'durationS')::int                 as duration_s,
      t.item->'route'->'legs'                              as transit_legs,
      (t.item->'route'->>'fetchedAt')::timestamptz         as fetched_at
    from jsonb_array_elements(coalesce(p_document->'legs', '[]'::jsonb))
         with ordinality as t(item, ord)
  ),
  removed as (
    delete from stop_legs
     where map_id = v_id and from_stop_index not in (select from_stop_index from parsed)
  )
  insert into stop_legs (map_id, from_stop_index, mode, from_place_id, to_place_id, geom, distance_m, duration_s, transit_legs, fetched_at)
  select v_id, from_stop_index, mode, from_place_id, to_place_id, geom, distance_m, duration_s, transit_legs, fetched_at
  from parsed
  on conflict (map_id, from_stop_index) do update set
    mode          = excluded.mode,
    from_place_id = excluded.from_place_id,
    to_place_id   = excluded.to_place_id,
    geom          = excluded.geom,
    distance_m    = excluded.distance_m,
    duration_s    = excluded.duration_s,
    transit_legs  = excluded.transit_legs,
    fetched_at    = excluded.fetched_at;

  -- 획 ----------------------------------------------------------------------
  with parsed as (
    select
      safe_uuid(t.item->>'id')                    as id,
      st_setsrid(st_makeline(array(
        select st_makepoint((pt->>'lng')::float8, (pt->>'lat')::float8)
        from jsonb_array_elements(t.item->'path') as pt
      )), 4326)::geography                        as geom,
      coalesce(t.item->>'color', '#E24B4A')       as color,
      coalesce((t.item->>'width')::int, 4)        as width,
      coalesce((t.item->>'zoomCreated')::int, 3)  as zoom_created,
      (t.ord - 1)::int                            as z_index
    from jsonb_array_elements(coalesce(p_document->'strokes', '[]'::jsonb))
         with ordinality as t(item, ord)
    where jsonb_array_length(coalesce(t.item->'path', '[]'::jsonb)) >= 2
  ),
  removed as (
    delete from strokes
     where map_id = v_id and id not in (select id from parsed)
  )
  insert into strokes (id, map_id, geom, color, width, zoom_created, z_index)
  select id, v_id, geom, color, width, zoom_created, z_index
  from parsed
  on conflict (id) do update set
    geom         = excluded.geom,
    color        = excluded.color,
    width        = excluded.width,
    zoom_created = excluded.zoom_created,
    z_index      = excluded.z_index
  where strokes.map_id = v_id;

  -- 라벨 --------------------------------------------------------------------
  with parsed as (
    select
      safe_uuid(item->>'id')                    as id,
      st_setsrid(st_makepoint(
        (item->'location'->>'lng')::float8,
        (item->'location'->>'lat')::float8
      ), 4326)::geography                       as location,
      item->>'text'                             as text,
      coalesce((item->>'fontSize')::int, 14)    as font_size,
      coalesce(item->>'color', '#2C2C2A')       as color
    from jsonb_array_elements(coalesce(p_document->'labels', '[]'::jsonb)) as item
    where item->'location' is not null and coalesce(item->>'text', '') <> ''
  ),
  removed as (
    delete from labels
     where map_id = v_id and id not in (select id from parsed)
  )
  insert into labels (id, map_id, location, text, font_size, color)
  select id, v_id, location, text, font_size, color
  from parsed
  on conflict (id) do update set
    location  = excluded.location,
    text      = excluded.text,
    font_size = excluded.font_size,
    color     = excluded.color
  where labels.map_id = v_id;

  return get_map_document(p_slug);
end;
$$;

revoke execute on function save_map_document(text, text, jsonb, timestamptz) from public, anon, authenticated;
