-- 커플 만들기·초대·가입·합치기 RPC 검증
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);
-- 복합 외래 키는 deferrable이라 위반을 문장 단위로 잡으려고 즉시 검사로 바꾼다
set constraints all immediate;

-- 준비: 사용자 6명 (u1~u4, 합치기용 uA·uB), 아무도 커플이 없다
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'u1@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'u2@test.local'),
  ('00000000-0000-0000-0000-0000000000a3', 'u3@test.local'),
  ('00000000-0000-0000-0000-0000000000a4', 'u4@test.local'),
  ('00000000-0000-0000-0000-0000000000a5', 'ua@test.local'),
  ('00000000-0000-0000-0000-0000000000a6', 'ub@test.local');

-- RPC 결과(커플 id, 초대 코드)를 사용자 전환 사이에 들고 다니는 표
create temp table t (k text primary key, v text);
grant all on t to authenticated;

-- ===== u1: 커플 만들기 =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

insert into t values ('c1', public.create_couple('2026-01-01', '민수', 'sky')::text);
insert into t select 'code1', code from public.current_invite();

select is(
  (select count(*)::int from couple_members
   where couple_id = (select v::uuid from t where k = 'c1') and user_id = auth.uid() and role = 'owner'),
  1, 'create_makes_owner_and_defaults (owner)');
select is(
  (select count(*)::int from couple_members where couple_id = (select v::uuid from t where k = 'c1')),
  1, 'create_makes_owner_and_defaults (members 1)');
select is(
  (select string_agg(s.name || '/' || s.short_label || '/' || s.color || '/' || s.all_day, ',' order by s.sort_order)
   from shift_types s join couple_members m on m.id = s.owner_member_id
   where s.couple_id = (select v::uuid from t where k = 'c1') and m.user_id = auth.uid()),
  '오전 당직/오전/pink/true,오후 당직/오후/sky/true', 'create_makes_owner_and_defaults (shift_types)');
select is((select count(*)::int from public.current_invite()), 1, 'create_makes_owner_and_defaults (invite)');
select matches((select v from t where k = 'code1'), '^[A-HJ-NP-Z2-9]{8}$', 'create_makes_owner_and_defaults (code format)');

select throws_ok(
  $$select public.create_couple('2026-01-01', '민수', 'sky')$$,
  'P0001', 'already_in_couple', 'create_twice_fails');

-- ===== u2: 코드 열기 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';

select is(
  public.peek_invite((select v from t where k = 'code1')),
  '{"status": "ok", "taken_colors": ["sky"]}'::jsonb, 'peek_ok');

select throws_ok(
  $$select public.join_couple((select v from t where k = 'code1'), '두리', 'sky', false)$$,
  'P0001', 'color_taken', 'join_color_taken (error)');

reset role;
select is(
  (select count(*)::int from couple_members where couple_id = (select v::uuid from t where k = 'c1')),
  1, 'join_color_taken (members still 1)');
set local role authenticated;

-- ===== u1: 자기 코드 열기 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  public.peek_invite((select v from t where k = 'code1')),
  '{"status": "invalid", "taken_colors": []}'::jsonb, 'peek_own_code_invalid');

-- ===== u2: 가입 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';

insert into t values ('j2', public.join_couple((select v from t where k = 'code1'), '두리', 'pink', false)::text);
select is(
  (select count(*)::int from couple_members where couple_id = (select v::uuid from t where k = 'c1')),
  2, 'join_closes_invite (members 2)');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is((select count(*)::int from public.current_invite()), 0, 'join_closes_invite (no current_invite)');

-- ===== u3: 이미 쓰인 코드 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select is(
  public.peek_invite((select v from t where k = 'code1'))->>'status',
  'invalid', 'join_closes_invite (peek invalid)');
select throws_ok(
  $$select public.join_couple((select v from t where k = 'code1'), '세찌', 'mint', false)$$,
  'P0001', 'invalid_invite', 'join_race_full');

-- u3 커플 만들기 + 코드 다시 만들기
insert into t values ('c3', public.create_couple('2026-02-01', '세찌', 'mint')::text);
insert into t select 'code3', code from public.current_invite();
insert into t values ('code3b', public.regenerate_invite());
select isnt((select v from t where k = 'code3b'), (select v from t where k = 'code3'), 'regenerate_replaces (new code)');
select is((select code from public.current_invite()), (select v from t where k = 'code3b'), 'regenerate_replaces (current)');

-- ===== u2(2인 커플 소속): 다른 코드 열기 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select throws_ok($$select public.regenerate_invite()$$, 'P0001', 'couple_full', 'regenerate_full_fails');

select is(
  public.peek_invite((select v from t where k = 'code3b'))->>'status',
  'in_full_couple', 'peek_in_full_couple (status)');
select throws_ok(
  $$select public.join_couple((select v from t where k = 'code3b'), '두리', 'lemon', true)$$,
  'P0001', 'in_full_couple', 'peek_in_full_couple (join error)');

reset role;
select is(
  (select count(*)::int from couple_members where couple_id = (select v::uuid from t where k = 'c1')),
  2, 'peek_in_full_couple (u1·u2 couple intact)');
select is(
  (select count(*)::int from couple_members where couple_id = (select v::uuid from t where k = 'c3')),
  1, 'peek_in_full_couple (u3 couple intact)');
set local role authenticated;

-- ===== 합치기: uA·uB가 각자 커플을 만든다 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}';
insert into t values ('cA', public.create_couple('2026-03-01', '에이', 'pink')::text);
insert into t select 'codeA', code from public.current_invite();
-- A 커플에 uA 개인 일정 하나 (합치면 사라져야 한다)
insert into events (couple_id, owner_kind, owner_member_id, title, day) values (
  (select v::uuid from t where k = 'cA'), 'member',
  (select id from couple_members where user_id = auth.uid()), 'A 일정', '2026-10-30');
select is(
  (select count(*)::int from events where couple_id = (select v::uuid from t where k = 'cA')),
  1, 'merge_flow (A event before)');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a6","role":"authenticated"}';
insert into t values ('cB', public.create_couple('2026-04-01', '비', 'sky')::text);
insert into t select 'codeB', code from public.current_invite();

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}';
select is(
  public.peek_invite((select v from t where k = 'codeB')),
  '{"status": "has_own_couple", "taken_colors": ["sky"]}'::jsonb, 'merge_flow (peek has_own_couple)');
select throws_ok(
  $$select public.join_couple((select v from t where k = 'codeB'), '에이', 'pink', false)$$,
  'P0001', 'has_own_couple', 'merge_flow (discard=false error)');
select is(
  public.join_couple((select v from t where k = 'codeB'), '에이', 'pink', true)::text,
  (select v from t where k = 'cB'), 'merge_flow (join returns B)');

reset role;
select is(
  (select count(*)::int from couples where id = (select v::uuid from t where k = 'cA')),
  0, 'merge_flow (A couple gone)');
select is(
  (select count(*)::int from events where couple_id = (select v::uuid from t where k = 'cA')),
  0, 'merge_flow (A events gone)');
set local role authenticated;

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a6","role":"authenticated"}';
select is(
  public.peek_invite((select v from t where k = 'codeA'))->>'status',
  'invalid', 'merge_flow (old A code invalid)');

-- ===== 만료 =====
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}';
select is(
  public.peek_invite((select v from t where k = 'code3b'))->>'status',
  'ok', 'expired_invalid (ok before expiry)');

reset role;
update invites set expires_at = now() - interval '1 minute'
  where code = (select v from t where k = 'code3b');
set local role authenticated;

select is(
  public.peek_invite((select v from t where k = 'code3b'))->>'status',
  'invalid', 'expired_invalid');

select * from finish();
rollback;
