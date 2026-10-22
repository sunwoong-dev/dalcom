-- 연결 끊기·계정 삭제 RPC 검증 (CPL-06, CPL-06a, CPL-07)
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);
-- 복합 외래 키는 deferrable이라 위반을 문장 단위로 잡으려고 즉시 검사로 바꾼다
-- RPC 호출 동안만 deferred로 두고, 호출 뒤 immediate로 돌려 커밋 시점 검사를 대신한다
set constraints all immediate;

-- 준비: 사용자 7명 (커플1 a1·a2, 커플2 a3·a4, 커플3 a5·a6, 혼자 a7)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'u1@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'u2@test.local'),
  ('00000000-0000-0000-0000-0000000000a3', 'u3@test.local'),
  ('00000000-0000-0000-0000-0000000000a4', 'u4@test.local'),
  ('00000000-0000-0000-0000-0000000000a5', 'u5@test.local'),
  ('00000000-0000-0000-0000-0000000000a6', 'u6@test.local'),
  ('00000000-0000-0000-0000-0000000000a7', 'u7@test.local');

create temp table t (k text primary key, v text);
grant all on t to authenticated;

-- 픽스처: ua(민수, sky)가 커플을 만들고 ub(지은, pink)가 가입한 뒤 일정을 넣는다
-- 일정 이름은 memo에 둔다. 입력자를 직접 정하려고 JWT를 비운 채(postgres) insert 한다
-- e1 ua 입력·ua 일정 / e2 ub 입력·ub 오전 당직 / e3 ua 입력·ub 오후 당직(대신 찍음) / e4 ub 입력·같이
-- p_extra: e5 ub 입력·ub 오후 당직(다른 날), e7 ub 입력·ua 오전 당직(e2와 같은 날)
create function pg_temp.mk(ua uuid, ub uuid, p_extra boolean) returns uuid
language plpgsql as $$
declare
  c uuid; ma uuid; mb uuid; am uuid; pm uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  c := public.create_couple('2026-01-01', '민수', 'sky');
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  perform public.join_couple((select code from invites where couple_id = c), '지은', 'pink', false);
  perform set_config('request.jwt.claims', '', true);

  select id into ma from couple_members where user_id = ua;
  select id into mb from couple_members where user_id = ub;
  select id into am from shift_types where couple_id = c and name = '오전 당직';
  select id into pm from shift_types where couple_id = c and name = '오후 당직';

  insert into events (couple_id, owner_kind, owner_member_id, created_by_member_id, shift_type_id, title, day, memo) values
    (c, 'member', ma, ma, null, '민수 일정', '2026-11-01', 'e1'),
    (c, 'member', mb, mb, am, null, '2026-11-02', 'e2'),
    (c, 'member', mb, ma, pm, null, '2026-11-03', 'e3'),
    (c, 'together', null, mb, null, '같이', '2026-11-04', 'e4');
  if p_extra then
    insert into events (couple_id, owner_kind, owner_member_id, created_by_member_id, shift_type_id, title, day, memo) values
      (c, 'member', mb, mb, pm, null, '2026-11-05', 'e5'),
      (c, 'member', ma, mb, am, null, '2026-11-02', 'e7');
  end if;
  insert into anniversaries (couple_id, title, date) values (c, '첫 만남', '2026-02-14');
  return c;
end;
$$;

insert into t values
  ('c1', pg_temp.mk('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2', false)::text),
  ('c2', pg_temp.mk('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a4', true)::text),
  ('c3', pg_temp.mk('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000a6', false)::text);

-- ===== leave_alone_deletes: a7 혼자 =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a7","role":"authenticated"}';
insert into t values ('c7', public.create_couple(null, '혼자', 'mint')::text);
select is(public.leave_couple(), null, 'leave_alone_deletes (returns null)');
reset role;
select is((select count(*)::int from couples where id = (select v::uuid from t where k = 'c7')),
  0, 'leave_alone_deletes (couple gone)');

-- 커플이 없으면 끊을 수 없다
set local role authenticated;
select throws_ok($$select public.leave_couple()$$, 'P0001', 'not_in_couple', 'leave_without_couple_fails');

-- ===== leave_keeps_own_events: 커플1에서 a1이 끊는다 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
set constraints all deferred;
insert into t values ('n1', public.leave_couple()::text);
select lives_ok($$set constraints all immediate$$, 'leave_keeps_own_events (fk hold at commit)');

select is((select string_agg(memo, ',' order by memo) from events), 'e1,e3', 'leave_keeps_own_events (u1 events)');
select is((select couple_id::text from couple_members where user_id = auth.uid()), (select v from t where k = 'n1'),
  'leave_keeps_own_events (u1 in new couple)');
select is((select role from couple_members where user_id = auth.uid()), 'owner', 'leave_keeps_own_events (u1 owner)');
select is((select owner_member_id from events where memo = 'e3'),
  (select id from couple_members where user_id = auth.uid()), 'leave_keeps_own_events (e3 owner = u1)');
select is((select count(*)::int from public.current_invite()), 1, 'leave_keeps_own_events (u1 invite)');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select is((select string_agg(memo, ',' order by memo) from events), 'e2,e4', 'leave_keeps_own_events (u2 events)');
select is((select count(*)::int from couple_members), 1, 'leave_keeps_own_events (old couple 1 member)');
select is((select role from couple_members where user_id = auth.uid()), 'owner', 'leave_keeps_own_events (u2 owner)');
select is((select count(*)::int from public.current_invite()), 1, 'leave_keeps_own_events (u2 invite)');

reset role;
select is((select s.couple_id::text from events e join shift_types s on s.id = e.shift_type_id where e.memo = 'e3'
           and e.couple_id = (select v::uuid from t where k = 'n1')),
  (select v from t where k = 'n1'), 'leave_keeps_own_events (e3 shift_type in new couple)');
select is((select count(*)::int from anniversaries where couple_id = (select v::uuid from t where k = 'c1')),
  0, 'leave_keeps_own_events (anniversaries gone)');
select is((select start_date from couples where id = (select v::uuid from t where k = 'n1')), null,
  'leave_keeps_own_events (new couple start_date null)');

-- ===== leave_copies_shared_shift_type: 커플2에서 a3이 끊는다 =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}';
set constraints all deferred;
insert into t values ('n2', public.leave_couple()::text);
select lives_ok($$set constraints all immediate$$, 'leave_copies_shared_shift_type (fk hold at commit)');
reset role;

select isnt(
  (select shift_type_id from events where memo = 'e3' and couple_id = (select v::uuid from t where k = 'n2')),
  (select shift_type_id from events where memo = 'e5' and couple_id = (select v::uuid from t where k = 'c2')),
  'leave_copies_shared_shift_type');
select is(
  (select s.name || '/' || s.couple_id::text from events e join shift_types s on s.id = e.shift_type_id
   where e.memo = 'e5' and e.couple_id = (select v::uuid from t where k = 'c2')),
  '오후 당직/' || (select v from t where k = 'c2'), 'leave_copies_shared_shift_type (e5 keeps original)');
-- 남은 근무 유형의 주인(원래 a3)은 남은 멤버 a4로 바뀐다
select is(
  (select count(*)::int from shift_types s join couple_members m on m.id = s.owner_member_id
   where s.couple_id = (select v::uuid from t where k = 'c2') and m.user_id = '00000000-0000-0000-0000-0000000000a4'),
  2, 'leave_copies_shared_shift_type (old shift_types owned by u4)');
-- e7(a4가 a3 오전 당직을 대신 찍음)은 a4에게 남는데 e2와 같은 도장이 되어 하나로 합쳐진다
select is(
  (select string_agg(memo, ',' order by memo) from events where couple_id = (select v::uuid from t where k = 'c2')),
  'e2,e4,e5', 'leave_dedupes_collided_stamp');

-- ===== delete_account_removes_user: 커플3에서 a5가 계정을 지운다 =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}';
set constraints all deferred;
select lives_ok($$select public.delete_my_account()$$, 'delete_account_removes_user (runs)');
select lives_ok($$set constraints all immediate$$, 'delete_account_removes_user (fk hold at commit)');
reset role;

select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000000a5'),
  0, 'delete_account_removes_user (auth user gone)');
select is(
  (select string_agg(memo, ',' order by memo) from events where couple_id = (select v::uuid from t where k = 'c3')),
  'e2,e4', 'delete_account_removes_user (u6 couple and events remain)');
select is((select count(*)::int from couples c where not exists (select 1 from couple_members m where m.couple_id = c.id)),
  0, 'delete_account_removes_user (no empty couple left)');

select * from finish();
rollback;
