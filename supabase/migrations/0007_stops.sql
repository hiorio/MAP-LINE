-- 한 단계에 후보 장소를 여러 개 담을 수 있게 한다.
--
-- 지금까지는 "장소 하나 = 번호 하나"였다. 그러면 "2번은 점심인데 어디로 갈지 아직
-- 안 정했다"를 표현할 수 없다. 모임을 짤 때 가장 흔한 상태이고, 후보를 함께 공유해
-- 같이 고르는 것이 이 제품의 쓰임새다.
--
-- 단계 자체에는 속성이 없으므로 별도 테이블을 만들지 않는다. places에 단계 번호를
-- 두고 읽을 때 묶는다. 테이블이 하나 줄고 순서 변경도 정수 갱신으로 끝난다.
--
-- 연결선(segments)은 더 이상 그리지 않는다. 한 단계에 후보가 여럿이면 선이 어느
-- 후보를 가리키는지 알 수 없어 잘못된 정보를 준다. 동선은 손그림으로 그린다.

alter table places
  add column if not exists stop_index int not null default 0;

-- 기존 데이터는 장소 하나가 곧 한 단계였다. 그대로 옮긴다.
update places set stop_index = order_no where stop_index = 0;

create index if not exists places_map_stop_idx on places(map_id, stop_index, order_no);

comment on column places.stop_index is '코스의 몇 번째 단계인가. 같은 값이면 같은 단계의 후보다.';
comment on column places.order_no is '같은 단계 안에서의 후보 순서.';

-- 쓰지 않는 컬럼과 테이블을 정리한다.
alter table places drop column if exists mode_to_next;
drop table if exists segments;

-- ---------------------------------------------------------------------------
-- 읽기: stop_index로 묶어 단계 배열로 돌려준다.
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
-- 쓰기: 단계 배열을 펼쳐 stop_index와 order_no를 매긴다.
-- 업서트와 교차 지도 방어는 0006과 동일하다.
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
