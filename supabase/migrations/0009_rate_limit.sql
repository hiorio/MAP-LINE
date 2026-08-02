-- 요청 빈도 제한 (설계안 §10 "스팸/악용 지도 생성")
--
-- 막아야 하는 두 가지가 다르다.
--   * 지도 생성: 반복 호출로 DB를 채운다. 우리 저장 공간 문제다.
--   * 검색·공유텍스트 파싱: 호출마다 카카오 쿼터를 태운다. 돈 문제다.
--
-- 고정 창(fixed window) 방식이다. 창이 바뀌는 순간 한도가 초기화되므로 경계에서
-- 최대 2배까지 통과할 수 있지만, 여기서 막으려는 것은 정밀한 균등 분배가 아니라
-- 자동화된 반복 호출이므로 이 정도로 충분하다. 슬라이딩 윈도우는 저장 비용이 크다.

create table if not exists rate_limits (
  bucket       text        not null,
  window_start timestamptz not null,
  hits         int         not null default 0,
  primary key (bucket, window_start)
);

alter table rate_limits enable row level security;
-- 정책을 만들지 않는다 = anon으로는 손댈 수 없다. 서버만 다룬다.

create index if not exists rate_limits_window_idx on rate_limits(window_start);

-- ---------------------------------------------------------------------------
-- 호출 1건을 기록하고 창 안의 누적 횟수를 돌려준다.
--
-- 한도 판단은 호출부가 한다. 이 함수는 세기만 한다 — 경로마다 한도가 다르고,
-- 그 값을 SQL에 박아 두면 바꿀 때마다 마이그레이션을 써야 한다.
-- ---------------------------------------------------------------------------
create or replace function bump_rate_limit(p_bucket text, p_window_seconds int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window timestamptz;
  v_hits   int;
begin
  -- 창의 시작 시각으로 내림한다. 같은 창의 요청은 같은 행에 쌓인다.
  v_window := to_timestamp(
    floor(extract(epoch from now()) / greatest(p_window_seconds, 1)) * greatest(p_window_seconds, 1)
  );

  insert into rate_limits (bucket, window_start, hits)
  values (p_bucket, v_window, 1)
  on conflict (bucket, window_start) do update
    set hits = rate_limits.hits + 1
  returning hits into v_hits;

  -- 지난 창은 쓸모가 없다. 가끔 치워 테이블이 무한정 자라지 않게 한다.
  if random() < 0.01 then
    delete from rate_limits where window_start < now() - interval '1 day';
  end if;

  return v_hits;
end;
$$;

revoke execute on function bump_rate_limit(text, int) from public, anon, authenticated;
grant  execute on function bump_rate_limit(text, int) to service_role;
