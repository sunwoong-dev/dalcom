-- 연결 끊기·계정 삭제 RPC 검증 (CPL-06, CPL-06a, CPL-07)
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);
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
-- e6 ub 입력·ua 일정(대신 입력)
-- p_extra: e5 ub 입력·ub 오후 당직(다른 날), e7 ub 입력·ua 오전 당직, e8 ua 입력·ua 오후 당직
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
    (c, 'together', null, mb, null, '같이', '2026-11-04', 'e4'),
    (c, 'member', ma, mb, null, '대신 입력', '2026-11-06', 'e6');
  if p_extra then
    insert into events (couple_id, owner_kind, owner_member_id, created_by_member_id, shift_type_id, title, day, memo) values
      (c, 'member', mb, mb, pm, null, '2026-11-05', 'e5'),
      (c, 'member', ma, mb, am, null, '2026-11-02', 'e7'),
      (c, 'member', ma, ma, pm, null, '2026-11-07', 'e8');
  end if;
  insert into anniversaries (couple_id, title, date) values (c, '첫 만남', '2026-02-14');
  return c;
end;
$$;

insert into t values
  ('c1', pg_temp.mk('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2', false)::text),
  ('c2', pg_temp.mk('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a4', true)::text),
  ('c3', pg_temp.mk('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000a6', false)::text);

-- 커플1의 원래 근무 유형 id (끊은 뒤에도 그대로 남아야 한다)
insert into t select 'st1', string_agg(id::text, ',' order by name) from shift_types
  where couple_id = (select v::uuid from t where k = 'c1');

-- ===== leave_alone_deletes: a7 혼자 =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a7","role":"authenticated"}';
insert into t values ('c7', public.create_couple(null, '혼자', 'mint')::text);
-- 혼자인 사람의 끊기는 막는다: 상대가 먼저 끊어 갱신 안 된 화면에서 눌러도 내 데이터가 지워지면 안 된다
select throws_ok($$select public.leave_couple()$$, 'P0001', 'not_connected', 'leave_alone_rejected');
reset role;
select is((select count(*)::int from couples where id = (select v::uuid from t where k = 'c7')),
  1, 'leave_alone_rejected (couple kept)');
-- 혼자 커플은 계정 삭제가 지운다
set local role authenticated;
select lives_ok($$select public.delete_my_account()$$, 'delete_alone_account (runs)');
reset role;
select is((select count(*)::int from couples where id = (select v::uuid from t where k = 'c7')),
  0, 'delete_alone_account (couple gone)');
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000000a7'),
  0, 'delete_alone_account (auth user gone)');

-- 커플이 없으면 끊을 수 없다
set local role authenticated;
select throws_ok($$select public.leave_couple()$$, 'P0001', 'not_in_couple', 'leave_without_couple_fails');

-- together 일정에 주인을 채우면 거부 (상대가 내 연결 끊기를 막지 못하게)
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$update events set owner_member_id = (select id from couple_members where user_id = '00000000-0000-0000-0000-0000000000a1') where memo = 'e4'$$,
  '23514', 'new row for relation "events" violates check constraint "events_together_no_owner"',
  'together_event_rejects_owner');

-- ===== leave_keeps_own_events: 커플1에서 a1이 끊는다 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
set constraints all deferred;
insert into t values ('n1', public.leave_couple()::text);
select lives_ok($$set constraints all immediate$$, 'leave_keeps_own_events (fk hold at commit)');

select is((select string_agg(memo, ',' order by memo) from events), 'e1', 'leave_keeps_own_events (u1 events)');
select is((select couple_id::text from couple_members where user_id = auth.uid()), (select v from t where k = 'n1'),
  'leave_keeps_own_events (u1 in new couple)');
select is((select role from couple_members where user_id = auth.uid()), 'owner', 'leave_keeps_own_events (u1 owner)');
select is((select count(*)::int from public.current_invite()), 1, 'leave_keeps_own_events (u1 invite)');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select is((select string_agg(memo, ',' order by memo) from events), 'e2,e4', 'leave_keeps_own_events (u2 events)');
select is((select count(*)::int from couple_members), 1, 'leave_keeps_own_events (old couple 1 member)');
select is((select role from couple_members where user_id = auth.uid()), 'owner', 'leave_keeps_own_events (u2 owner)');
select is((select count(*)::int from public.current_invite()), 1, 'leave_keeps_own_events (u2 invite)');

reset role;
-- 주인이 상대인 일정은 누가 입력했든 양쪽에서 지운다 (R16)
select is((select count(*)::int from events where memo = 'e3'
           and couple_id in ((select v::uuid from t where k = 'c1'), (select v::uuid from t where k = 'n1'))),
  0, 'leave_keeps_own_events (e3 proxy stamp gone)');
select is((select count(*)::int from events where memo = 'e6'
           and couple_id in ((select v::uuid from t where k = 'c1'), (select v::uuid from t where k = 'n1'))),
  0, 'leave_drops_partner_owned_events');
select is((select count(*)::int from anniversaries where couple_id = (select v::uuid from t where k = 'c1')),
  0, 'leave_keeps_own_events (anniversaries gone)');
select is((select start_date from couples where id = (select v::uuid from t where k = 'n1')), null,
  'leave_keeps_own_events (new couple start_date null)');

-- 남은 사람은 근무 유형을 하나도 잃지 않는다. 끊은 사람은 옮긴 일정이 쓰는 유형만 복사받는다(여기선 없음)
select is(
  (select string_agg(id::text, ',' order by name) from shift_types where couple_id = (select v::uuid from t where k = 'c1')),
  (select v from t where k = 'st1'), 'leave_partner_keeps_all_types (old couple keeps original ids)');
select is(
  (select string_agg(name, ',' order by name) from shift_types where couple_id = (select v::uuid from t where k = 'c1')),
  '오전 당직,오후 당직', 'leave_partner_keeps_all_types (old couple both defaults)');
select is((select count(*)::int from shift_types where couple_id = (select v::uuid from t where k = 'n1')),
  0, 'leave_partner_keeps_all_types (new couple copies only used types)');

-- ===== leave_copies_shared_shift_type: 커플2에서 a3이 끊는다 =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}';
set constraints all deferred;
insert into t values ('n2', public.leave_couple()::text);
select lives_ok($$set constraints all immediate$$, 'leave_copies_shared_shift_type (fk hold at commit)');
reset role;

select isnt(
  (select shift_type_id from events where memo = 'e8' and couple_id = (select v::uuid from t where k = 'n2')),
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
-- 복사본의 주인은 끊은 사람이다
select is(
  (select m.user_id from events e join shift_types s on s.id = e.shift_type_id join couple_members m on m.id = s.owner_member_id
   where e.memo = 'e8' and e.couple_id = (select v::uuid from t where k = 'n2')),
  '00000000-0000-0000-0000-0000000000a3'::uuid, 'leave_copies_shared_shift_type (copy owned by leaver)');
-- e3·e7(대신 찍은 도장)과 e6은 양쪽에서 지워진다
select is(
  (select string_agg(memo, ',' order by memo) from events where couple_id = (select v::uuid from t where k = 'c2')),
  'e2,e4,e5', 'leave_drops_partner_owned_events (c2 remaining)');
select is(
  (select string_agg(memo, ',' order by memo) from events where couple_id = (select v::uuid from t where k = 'n2')),
  'e1,e8', 'leave_drops_partner_owned_events (n2 moved)');

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
