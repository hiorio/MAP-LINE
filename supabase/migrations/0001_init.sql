-- MAP-LINE v0.1 초기 스키마 (설계안 §5.1)
-- Supabase SQL Editor 또는 supabase CLI로 적용한다.

create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- 지도 (하나의 공유 단위)
-- ---------------------------------------------------------------------------
create table if not exists maps (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,              -- 8자 nanoid, URL에 노출
  title       text not null default '제목 없는 지도',
  owner_id    uuid references auth.users(id),    -- v1.0부터 사용, MVP는 null
  edit_token  text not null,                     -- 익명 재편집용 (32자 random)
  center      geography(Point, 4326) not null,   -- 초기 뷰 중심
  zoom_level  int not null default 5,            -- 카카오 기준 1(확대)~14(축소)
  view_count  int not null default 0,
  og_image_url text,                             -- 정적 지도 캐시 (§9.1)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint maps_zoom_level_range check (zoom_level between 1 and 14)
);

create index if not exists maps_owner_idx on maps(owner_id) where owner_id is not null;

-- ---------------------------------------------------------------------------
-- 장소 핀
-- ---------------------------------------------------------------------------
create table if not exists places (
  id             uuid primary key default gen_random_uuid(),
  map_id         uuid not null references maps(id) on delete cascade,
  order_no       int not null,
  name           text not null,
  address        text,
  kakao_place_id text,                            -- 재조회용 (좌표/상호는 캐시 취급)
  location       geography(Point, 4326) not null,
  memo           text,
  pin_color      text not null default 'coral',
  created_at     timestamptz not null default now()
);

create index if not exists places_map_order_idx on places(map_id, order_no);

-- ---------------------------------------------------------------------------
-- 손그림 획
-- ---------------------------------------------------------------------------
create table if not exists strokes (
  id           uuid primary key default gen_random_uuid(),
  map_id       uuid not null references maps(id) on delete cascade,
  geom         geography(LineString, 4326) not null,
  color        text not null default '#E24B4A',
  width        int not null default 4,
  zoom_created int not null,                      -- 그린 시점의 줌 레벨
  z_index      int not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists strokes_map_idx on strokes(map_id);

-- ---------------------------------------------------------------------------
-- 텍스트 라벨
-- ---------------------------------------------------------------------------
create table if not exists labels (
  id        uuid primary key default gen_random_uuid(),
  map_id    uuid not null references maps(id) on delete cascade,
  location  geography(Point, 4326) not null,
  text      text not null,
  font_size int not null default 14,
  color     text not null default '#2C2C2A'
);

create index if not exists labels_map_idx on labels(map_id);

-- ---------------------------------------------------------------------------
-- 핀 간 연결선 스타일
-- ---------------------------------------------------------------------------
create table if not exists segments (
  id         uuid primary key default gen_random_uuid(),
  map_id     uuid not null references maps(id) on delete cascade,
  from_place uuid not null references places(id) on delete cascade,
  to_place   uuid not null references places(id) on delete cascade,
  mode       text not null default 'walk',        -- walk | car | transit
  style      text not null default 'auto',        -- auto | manual(사용자 그림으로 대체)
  constraint segments_mode_check check (mode in ('walk', 'car', 'transit')),
  constraint segments_style_check check (style in ('auto', 'manual'))
);

create index if not exists segments_map_idx on segments(map_id);

-- ---------------------------------------------------------------------------
-- updated_at 자동 갱신
-- 스냅샷 PATCH의 낙관적 잠금(If-Match)이 이 값에 의존하므로 트리거로 강제한다.
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists maps_set_updated_at on maps;
create trigger maps_set_updated_at
  before update on maps
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS (설계안 §5.3)
-- 읽기는 누구나. 쓰기 정책은 만들지 않는다 = anon key로는 쓸 수 없다.
-- 모든 쓰기는 Route Handler가 service role로 수행하며 edit_token을 서버에서 검증한다.
-- ---------------------------------------------------------------------------
alter table maps     enable row level security;
alter table places   enable row level security;
alter table strokes  enable row level security;
alter table labels   enable row level security;
alter table segments enable row level security;

drop policy if exists maps_read on maps;
create policy maps_read on maps for select using (true);

drop policy if exists places_read on places;
create policy places_read on places for select using (true);

drop policy if exists strokes_read on strokes;
create policy strokes_read on strokes for select using (true);

drop policy if exists labels_read on labels;
create policy labels_read on labels for select using (true);

drop policy if exists segments_read on segments;
create policy segments_read on segments for select using (true);

-- edit_token은 공개 읽기 대상에서 반드시 제외해야 한다.
-- 컬럼 단위 RLS가 없으므로 뷰어/API는 이 뷰만 조회한다.
create or replace view maps_public as
  select id, slug, title, center, zoom_level, view_count, og_image_url, created_at, updated_at
  from maps;
