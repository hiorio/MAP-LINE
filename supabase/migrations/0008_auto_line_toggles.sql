-- 자동으로 그려지는 선을 끄고 켜는 설정.
--
-- 문서에 담는 이유: 만든 사람이 동선을 손으로 직접 그리고 자동 화살표를 껐다면,
-- 링크를 받은 사람에게도 꺼져 있어야 한다. 편집기 개인 설정으로 두면 공유된 지도가
-- 만든 사람이 의도한 모습과 달라진다.
--
-- 0007 다음에 적용한다.

alter table maps
  add column if not exists show_candidate_links boolean not null default true,
  add column if not exists show_stop_arrows     boolean not null default true;

comment on column maps.show_candidate_links is '같은 단계 후보들을 중간지점과 잇는 점선 표시 여부.';
comment on column maps.show_stop_arrows is '단계 사이 이동 방향 화살표 표시 여부.';

-- ---------------------------------------------------------------------------
-- 읽기: 설정 두 개를 문서에 실어 보낸다. 나머지는 0007과 동일하다.
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
          jsonb_build_object(
            -- 단계 id는 저장하지 않는다. 첫 후보의 id로 안정적으로 되살린다.
            'id', (array_agg(p.id order by p.order_no))[1],
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
          ) as stop
        from places p
        where p.map_id = m.id
        group by p.stop_index
      ) grouped
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

grant execute on function get_map_document(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 쓰기: maps 갱신에 설정 두 개를 더한다.
--
-- coalesce로 감싸 값이 빠진 문서를 받아도 기존 설정을 지우지 않는다. 예전 버전
-- 클라이언트가 보낸 문서에는 이 필드가 없다.
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
      coalesce(candidate->>'pinColor', 'coral')                   as pin_color
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
  insert into places (id, map_id, stop_index, order_no, name, address, kakao_place_id, location, memo, pin_color)
  select id, v_id, stop_index, order_no, name, address, kakao_place_id, location, memo, pin_color
  from parsed
  on conflict (id) do update set
    stop_index     = excluded.stop_index,
    order_no       = excluded.order_no,
    name           = excluded.name,
    address        = excluded.address,
    kakao_place_id = excluded.kakao_place_id,
    location       = excluded.location,
    memo           = excluded.memo,
    pin_color      = excluded.pin_color
  -- 다른 지도의 행을 끌어오지 못하게 막는다.
  where places.map_id = v_id;

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
grant  execute on function save_map_document(text, text, jsonb, timestamptz) to service_role;
