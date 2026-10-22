-- v1 스키마의 행 단위 보안(RLS)과 유니크 제약 검증
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

-- 준비: 사용자 4명, u1·u2 커플 C1, u3 커플 C2, u4는 커플 없음 (superuser로 만든다)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'u1@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'u2@test.local'),
  ('00000000-0000-0000-0000-0000000000a3', 'u3@test.local'),
  ('00000000-0000-0000-0000-0000000000a4', 'u4@test.local');  -- 커플 없는 사용자(color_unique용)

insert into couples (id, created_by) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a3');

insert into couple_members (id, couple_id, user_id, role, nickname, color) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'owner', '하나', 'pink'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'partner', '두리', 'sky'),
  ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a3', 'owner', '세찌', 'mint');

insert into invites (couple_id, code) values
  ('00000000-0000-0000-0000-0000000000c1', 'ABCDEFGH');

insert into shift_types (id, couple_id, owner_member_id, name, short_label, color) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', '오전 당직', '오전', 'pink');

insert into events (couple_id, owner_kind, owner_member_id, title, day) values
  ('00000000-0000-0000-0000-0000000000c1', 'together', null, '데이트', '2026-10-21');

-- u3 시점
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}';

select is(
  (select count(*)::int from events where couple_id = '00000000-0000-0000-0000-0000000000c1'),
  0, 'events_isolated');

select throws_ok(
  $$insert into events (couple_id, owner_kind, title, day)
    values ('00000000-0000-0000-0000-0000000000c1', 'together', '침입', '2026-10-22')$$,
  '42501', null, 'events_insert_blocked');

-- u2 시점
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';

select is(
  (select count(*)::int from couple_members where couple_id = '00000000-0000-0000-0000-0000000000c1'),
  2, 'members_visible_to_partner');

with u as (
  update couple_members set nickname = '바꿈'
  where id = '00000000-0000-0000-0000-0000000000b1' returning 1)
select is((select count(*)::int from u), 0, 'member_update_own_only');

-- u1 시점
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is((select count(*)::int from invites), 0, 'invites_hidden');

-- 유니크 제약은 superuser로 확인
reset role;

select throws_ok(
  $$insert into couple_members (couple_id, user_id, role, nickname, color)
    values ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a4', 'partner', '중복', 'mint')$$,
  '23505', null, 'color_unique');

insert into events (couple_id, owner_kind, owner_member_id, shift_type_id, day) values
  ('00000000-0000-0000-0000-0000000000c1', 'member', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000d1', '2026-10-23');

select throws_ok(
  $$insert into events (couple_id, owner_kind, owner_member_id, shift_type_id, day)
    values ('00000000-0000-0000-0000-0000000000c1', 'member', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000d1', '2026-10-23')$$,
  '23505', null, 'shift_stamp_unique');

select * from finish();
rollback;
