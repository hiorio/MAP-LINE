-- 단계 사이 이동수단에 자동차를 추가한다.
--
-- 자동차 경로는 Kakao Mobility Directions API에서 실시간으로 받되, 선택한 mode만
-- 저장한다. 제공자의 저장 조건에 따라 도로 좌표·거리·시간은 DB에 남기지 않는다.

alter table stop_legs
  drop constraint if exists stop_legs_mode_check;

alter table stop_legs
  add constraint stop_legs_mode_check
  check (mode in ('straight', 'walk', 'transit', 'bicycle', 'car'));

-- 앱 서버에서도 자동차 route를 제거하지만, 저장 정책은 DB에서도 한 번 더 강제한다.
-- 이후 다른 저장 경로가 생겨도 자동차 도로 좌표·시간이 실수로 남지 않는다.
create or replace function clear_car_route_cache()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.mode = 'car' then
    new.from_place_id := null;
    new.to_place_id := null;
    new.geom := null;
    new.distance_m := null;
    new.duration_s := null;
    new.transit_legs := null;
    new.fetched_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists stop_legs_clear_car_route_cache on stop_legs;
create trigger stop_legs_clear_car_route_cache
before insert or update on stop_legs
for each row execute function clear_car_route_cache();

revoke execute on function clear_car_route_cache() from public, anon, authenticated;
