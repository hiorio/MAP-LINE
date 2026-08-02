-- 저장을 "전체 삭제 후 재삽입"에서 업서트로 바꾼다.
--
-- 기존 방식의 문제:
--   1) 클라이언트가 만든 id가 버려지고 매번 새 uuid가 발급됐다. 저장할 때마다 같은 핀의
--      id가 바뀌므로 핀에 댓글을 달거나 특정 획을 참조하는 기능을 만들 수 없고,
--      협업 편집(v1.0)은 이 구조 위에 올릴 수 없다.
--   2) 획이 50개인 지도는 자동 저장이 돌 때마다 50행을 지우고 50행을 다시 넣었다.
--      편집 중에는 2초마다 반복된다.
--
-- 바뀐 방식: 클라이언트 id를 그대로 기본키로 쓰고, 페이로드에 없는 행만 지운 뒤
-- 나머지는 `on conflict do update`로 갱신한다. 안 바뀐 행은 건드리지 않는다.
--
-- 전제: 클라이언트 id가 uuid 형식이어야 한다. `lib/id.ts`가 보장하고, 아니면
-- safe_uuid가 새 uuid를 발급해 넘어간다(예전 로컬 초안 호환).

-- ---------------------------------------------------------------------------
-- uuid가 아니면 새로 발급한다.
--
-- 예전 클라이언트가 만든 로컬 초안에는 32자 hex나 timestamp 형식 id가 남아 있다.
-- 그대로 캐스팅하면 저장 전체가 실패하므로 조용히 새 id를 준다.
-- ---------------------------------------------------------------------------
create or replace function safe_uuid(p_value text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_value::uuid;
exception when others then
  return gen_random_uuid();
end;
$$;

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

  -- 핀 --------------------------------------------------------------------
  -- 데이터 변경 CTE로 "사라진 행 삭제"와 "업서트"를 한 문장에 담는다.
  -- 페이로드가 비면 not in (빈 집합)이 모두 참이 되어 전부 지워진다. 의도한 동작이다.
  with parsed as (
    select
      safe_uuid(t.item->>'id')                                    as id,
      (t.ord - 1)::int                                            as order_no,
      t.item->>'name'                                             as name,
      t.item->>'address'                                          as address,
      t.item->>'kakaoPlaceId'                                     as kakao_place_id,
      st_setsrid(st_makepoint(
        (t.item->'location'->>'lng')::float8,
        (t.item->'location'->>'lat')::float8
      ), 4326)::geography                                         as location,
      t.item->>'memo'                                             as memo,
      coalesce(t.item->>'pinColor', 'coral')                      as pin_color,
      coalesce(t.item->>'modeToNext', 'walk')                     as mode_to_next
    from jsonb_array_elements(coalesce(p_document->'places', '[]'::jsonb))
         with ordinality as t(item, ord)
    where t.item->'location' is not null
  ),
  removed as (
    delete from places
     where map_id = v_id and id not in (select id from parsed)
  )
  insert into places (id, map_id, order_no, name, address, kakao_place_id, location, memo, pin_color, mode_to_next)
  select id, v_id, order_no, name, address, kakao_place_id, location, memo, pin_color, mode_to_next
  from parsed
  on conflict (id) do update set
    order_no       = excluded.order_no,
    name           = excluded.name,
    address        = excluded.address,
    kakao_place_id = excluded.kakao_place_id,
    location       = excluded.location,
    memo           = excluded.memo,
    pin_color      = excluded.pin_color,
    mode_to_next   = excluded.mode_to_next
  -- 다른 지도의 행을 끌어오지 못하게 막는다. uuid 충돌은 사실상 없지만 일부러 보낼 수는 있다.
  where places.map_id = v_id;

  -- 획 ----------------------------------------------------------------------
  -- LineString은 점이 2개 이상이어야 한다. RDP가 보장하지만 방어한다.
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
