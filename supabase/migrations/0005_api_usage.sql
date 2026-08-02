-- 카카오 API 사용량 집계
--
-- 기존 카운터는 서버 프로세스 메모리에 있었다. 재배포하면 사라지고, 인스턴스가 여러 개면
-- 각자 따로 세어 합계가 실제보다 적게 나온다. 쿼터를 넘겼는지 판단해야 하는 값이
-- 실제보다 작게 나오는 것은 위험한 방향의 오차다.
--
-- 설계안 §10: 무료 쿼터는 "추후 별도 안내 전까지"라는 단서가 붙어 있고 초과분은 우리가 낸다.

create table if not exists api_usage (
  day        date not null,
  api        text not null,
  call_count int  not null default 0,
  updated_at timestamptz not null default now(),
  primary key (day, api),
  constraint api_usage_api_check check (api in ('search', 'staticmap', 'route'))
);

alter table api_usage enable row level security;
-- 정책을 만들지 않는다 = anon으로는 읽지도 쓰지도 못한다. 서버만 다룬다.

-- ---------------------------------------------------------------------------
-- 호출 1건 기록.
--
-- 카카오 쿼터는 KST 자정에 초기화되므로 날짜도 KST 기준으로 끊는다.
-- 반환값은 오늘 누적 횟수. 호출부가 임계치 판단에 쓴다.
-- ---------------------------------------------------------------------------
create or replace function record_api_call(p_api text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day   date := (now() at time zone 'Asia/Seoul')::date;
  v_count int;
begin
  insert into api_usage (day, api, call_count)
  values (v_day, p_api, 1)
  on conflict (day, api) do update
    set call_count = api_usage.call_count + 1,
        updated_at = now()
  returning call_count into v_count;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 최근 사용량 조회. 운영 중 확인용.
-- ---------------------------------------------------------------------------
create or replace function get_api_usage(p_days int default 7)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('day', day, 'api', api, 'calls', call_count)
      order by day desc, api
    ),
    '[]'::jsonb
  )
  from api_usage
  where day > (now() at time zone 'Asia/Seoul')::date - greatest(p_days, 1);
$$;

revoke execute on function record_api_call(text) from public, anon, authenticated;
revoke execute on function get_api_usage(int)   from public, anon, authenticated;
grant  execute on function record_api_call(text) to service_role;
grant  execute on function get_api_usage(int)    to service_role;
