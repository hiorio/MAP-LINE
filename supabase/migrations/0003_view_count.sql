-- T13 뷰어 — 조회수 집계
--
-- 설계안 §1.4의 핵심 지표가 "생성된 지도 1개당 평균 조회수"다. 이 값이 1.0 근처면
-- 공유가 일어나지 않는 것이고 제품 가설이 틀린 것이므로, 뷰어를 붙이는 시점부터
-- 세기 시작해야 의미 있는 데이터가 쌓인다.

-- ---------------------------------------------------------------------------
-- updated_at 트리거를 조회수에 둔감하게 만든다.
--
-- 0001의 트리거는 update마다 무조건 updated_at = now()로 덮는다. 그대로 두면
-- 누가 뷰어를 열 때마다 updated_at이 밀려서, 편집기가 들고 있던 값이 낡은 것이 되고
-- 낙관적 잠금이 실제 충돌도 아닌데 409를 뱉는다.
--
-- updated_at은 "내용이 바뀐 시각"이어야 하므로 조회수만 바뀐 경우는 건너뛴다.
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  if (to_jsonb(new) - 'view_count' - 'updated_at')
     = (to_jsonb(old) - 'view_count' - 'updated_at') then
    new.updated_at = old.updated_at;
  else
    new.updated_at = now();
  end if;
  return new;
end;
$$;

create or replace function increment_map_view(p_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update maps set view_count = view_count + 1 where slug = p_slug;
end;
$$;

-- 뷰어는 로그인 없이 열리므로 anon도 호출할 수 있어야 한다.
grant execute on function increment_map_view(text) to anon, authenticated, service_role;
