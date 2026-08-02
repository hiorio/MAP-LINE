-- T14 OG 썸네일 캐시
--
-- 설계안 §9.1: 정적 지도는 일 1,000건 무료, 초과 시 건당 2원. 매 조회마다 호출하면
-- 인기 지도 하나가 하루 쿼터를 다 먹는다. 생성한 이미지는 Storage에 두고 재사용한다.
--
-- 언제 다시 만드는가: og_updated_at < updated_at 일 때만. 즉 지도 내용이 바뀐 뒤
-- 누군가 실제로 썸네일을 요청했을 때 한 번. 편집 중 2초마다 도는 자동 저장은
-- updated_at만 밀 뿐 카카오를 호출하지 않는다.

alter table maps
  add column if not exists og_updated_at timestamptz;

comment on column maps.og_image_url is
  'Supabase Storage에 캐시된 OG 썸네일 공개 URL. 없으면 아직 생성 전.';
comment on column maps.og_updated_at is
  '썸네일을 만든 시각. updated_at보다 이르면 내용이 바뀐 것이므로 다시 만든다.';

-- ---------------------------------------------------------------------------
-- updated_at 트리거가 썸네일 컬럼도 무시하게 한다.
--
-- 0003은 view_count만 예외로 뒀다. 그대로 두면 썸네일 URL을 기록하는 순간
-- updated_at이 now()로 밀리고, 그러면 다시 og_updated_at < updated_at이 되어
-- 다음 요청에서 또 만들고, 또 밀리는 무한 재생성이 된다. 카카오 쿼터가 그대로 날아간다.
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
declare
  ignored text[] := array['view_count', 'updated_at', 'og_image_url', 'og_updated_at'];
begin
  if (to_jsonb(new) - ignored) = (to_jsonb(old) - ignored) then
    new.updated_at = old.updated_at;
  else
    new.updated_at = now();
  end if;
  return new;
end;
$$;

-- 썸네일 URL을 기록한다. 내용 변경이 아니므로 updated_at은 위 트리거가 보존한다.
create or replace function set_map_og_image(p_slug text, p_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update maps
     set og_image_url = p_url,
         og_updated_at = now()
   where slug = p_slug;
end;
$$;

revoke execute on function set_map_og_image(text, text) from public, anon, authenticated;
grant execute on function set_map_og_image(text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 읽기 함수에 썸네일 상태를 추가한다.
-- 나머지는 0002와 동일하다. edit_token은 여전히 반환하지 않는다.
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

grant execute on function get_map_document(text) to anon, authenticated, service_role;
