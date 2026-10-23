-- v1 최종 리뷰 수정: 혼자 남은 사람의 끊기 보호, together 일정의 주인 금지, 함수·테이블 권한 하드닝

-- 1. together 일정에는 주인이 없어야 한다.
--    주인이 채워진 together 일정이 있으면 연결 끊기 3단계가 새 커플 밖의 멤버를 가리켜 커밋 때 롤백된다
--    (상대가 API로 채워 내 연결 끊기와 계정 삭제를 막을 수 있었다)
update public.events set owner_member_id = null
  where owner_kind = 'together' and owner_member_id is not null;
alter table public.events
  add constraint events_together_no_owner check (owner_kind = 'member' or owner_member_id is null);

-- 2. 연결 끊기: 혼자면 막는다.
--    상대가 먼저 끊어 화면이 갱신되지 않은 사람이 "내 일정은 남는다" 안내를 보고 눌러도 데이터가 지워지면 안 된다.
--    혼자 커플을 지우는 일은 delete_my_account가 맡는다
create or replace function public.leave_couple() returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old uuid;
  v_new uuid;
  v_me uuid;
  v_st uuid;
  v_copy uuid;
  v_partner uuid;
begin
  select couple_id into v_old from couple_members where user_id = auth.uid();
  -- 가입·다른 끊기와 겹치지 않게 커플 행을 잠근 뒤 다시 읽는다
  perform 1 from couples where id = v_old for update;
  select id into v_me from couple_members where user_id = auth.uid() and couple_id = v_old;
  if v_me is null then
    raise exception 'not_in_couple';
  end if;

  if (select count(*) from couple_members where couple_id = v_old) = 1 then
    raise exception 'not_connected';
  end if;

  select id into v_partner from couple_members where couple_id = v_old and id <> v_me;

  -- 1. 아무도 갖지 않는 일정을 먼저 지운다: 주인이 입력자가 아닌 개인 일정, 입력자가 없는 일정
  --    (멤버 행을 옮기기 전에 지워 on delete set null·주인 check 경로를 타지 않는다)
  delete from events
    where couple_id = v_old
      and not (created_by_member_id is not null
               and (owner_kind = 'together' or owner_member_id = created_by_member_id));

  -- 2. 새 커플로 내 멤버 행을 옮긴다
  insert into couples (start_date, created_by) values (null, auth.uid()) returning id into v_new;
  update couple_members set couple_id = v_new, role = 'owner' where id = v_me;

  -- 3. 내가 입력한 일정을 옮긴다 (트리거가 created_by를 유지한다)
  update events set couple_id = v_new where couple_id = v_old and created_by_member_id = v_me;

  -- 4. 옮긴 일정이 쓰는 근무 유형은 새 커플에 내 것으로 복사해 가리키게 한다. 기존 커플의 유형은 그대로 남긴다
  for v_st in select distinct shift_type_id from events where couple_id = v_new and shift_type_id is not null loop
    insert into shift_types (couple_id, owner_member_id, name, short_label, color, all_day, start_time, end_time, sort_order)
      select v_new, v_me, name, short_label, color, all_day, start_time, end_time, sort_order
      from shift_types where id = v_st
      returning id into v_copy;
    update events set shift_type_id = v_copy where couple_id = v_new and shift_type_id = v_st;
  end loop;
  -- 기존 커플에서 내가 주인이던 근무 유형은 남은 사람 것이 된다
  update shift_types set owner_member_id = v_partner where couple_id = v_old and owner_member_id = v_me;

  -- 5. 직접 추가한 기념일은 둘 다에게서 지운다
  delete from anniversaries where couple_id = v_old;

  -- 6. 남은 사람은 owner가 되고, 두 커플 모두 새 초대 코드를 받는다
  update couple_members set role = 'owner' where couple_id = v_old;
  insert into invites (couple_id, code, expires_at) values
    (v_old, gen_invite_code(), now() + interval '7 days'),
    (v_new, gen_invite_code(), now() + interval '7 days')
    on conflict (couple_id) do update set code = excluded.code, expires_at = excluded.expires_at;
  return v_new;
end;
$$;

-- 3. 계정 삭제: 혼자면 내 커플을 직접 지우고, 둘이면 연결을 끊고 남은 내 1인 커플을 지운 뒤 로그인 계정을 지운다
create or replace function public.delete_my_account() returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old uuid;
  v_mine uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select couple_id into v_old from couple_members where user_id = auth.uid();
  if v_old is not null then
    -- 끊기·가입과 겹치지 않게 잠근 뒤 인원을 센다
    perform 1 from couples where id = v_old for update;
    if (select count(*) from couple_members where couple_id = v_old) = 1 then
      delete from couples where id = v_old;
    else
      v_mine := leave_couple();
      delete from couples where id = v_mine;
    end if;
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- 4. security definer 함수의 search_path 끝에 pg_temp를 명시한다 (임시 객체가 public보다 먼저 잡히지 않게)
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('alter function %s set search_path = public, pg_temp', r.f);
  end loop;
end $$;

-- 5. 앱 역할이 RLS를 우회하는 TRUNCATE와 쓸 일 없는 TRIGGER·REFERENCES를 갖지 않게 한다
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke truncate, trigger, references on tables from anon, authenticated;
