-- v1 연결 끊기·계정 삭제 RPC (CPL-06, CPL-06a, CPL-07)
-- 모두 security definer이고 호출자는 auth.uid()다.
-- 멤버·일정·근무 유형을 여러 문장에 걸쳐 옮기므로 복합 외래 키(deferrable)는 커밋 시점에 검사된다.

-- 연결 끊기: 혼자면 커플을 지우고 null, 둘이면 나를 새 1인 커플로 옮기고 그 id를 반환한다
-- 각자 "자기가 입력했고 주인이 자기이거나 같이인" 일정만 갖는다 (CPL-06a, R16)
-- 주인이 상대인 일정은 누가 입력했든 지운다
create function public.leave_couple() returns uuid
language plpgsql
security definer
set search_path = public
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
    -- 마지막 멤버: 커플째 지운다(멤버·일정·근무 유형·기념일·초대 코드는 cascade)
    delete from couples where id = v_old;
    return null;
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

-- 계정 삭제: 연결을 끊고(커플이 있으면) 남은 내 1인 커플을 지운 뒤 로그인 계정을 지운다
create function public.delete_my_account() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mine uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if exists (select 1 from couple_members where user_id = auth.uid()) then
    v_mine := leave_couple();
    if v_mine is not null then
      delete from couples where id = v_mine;
    end if;
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.leave_couple() from public, anon;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.leave_couple() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
