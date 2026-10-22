-- v1 연결 끊기·계정 삭제 RPC (CPL-06, CPL-06a, CPL-07)
-- 모두 security definer이고 호출자는 auth.uid()다.
-- 멤버·일정·근무 유형을 여러 문장에 걸쳐 옮기므로 복합 외래 키(deferrable)는 커밋 시점에 검사된다.

-- 연결 끊기: 혼자면 커플을 지우고 null, 둘이면 나를 새 1인 커플로 옮기고 그 id를 반환한다
-- 기준은 입력자(created_by)다. 내가 입력한 일정만 내게 오고, 상대가 입력한 일정은 상대에게 남는다
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
  v_c uuid;
  v_sole uuid;
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

  -- 1. 새 커플로 내 멤버 행을 옮긴다
  insert into couples (start_date, created_by) values (null, auth.uid()) returning id into v_new;
  update couple_members set couple_id = v_new, role = 'owner' where id = v_me;

  -- 2. 내가 입력한 일정을 옮긴다 (트리거가 created_by를 유지한다)
  update events set couple_id = v_new where couple_id = v_old and created_by_member_id = v_me;

  -- 3. 옮긴 일정이 쓰는 근무 유형: 남은 일정도 쓰면 복사, 아니면 통째로 옮긴다
  for v_st in select distinct shift_type_id from events where couple_id = v_new and shift_type_id is not null loop
    if exists (select 1 from events where couple_id = v_old and shift_type_id = v_st) then
      insert into shift_types (couple_id, owner_member_id, name, short_label, color, all_day, start_time, end_time, sort_order)
        select v_new, owner_member_id, name, short_label, color, all_day, start_time, end_time, sort_order
        from shift_types where id = v_st
        returning id into v_copy;
      update events set shift_type_id = v_copy where couple_id = v_new and shift_type_id = v_st;
    else
      update shift_types set couple_id = v_new where id = v_st;
    end if;
  end loop;

  -- 4. 두 커플 모두 멤버가 1명이므로, 그 커플 멤버가 아닌 주인은 남은 한 명으로 바꾼다
  --    (그 커플에 남은 일정의 입력자는 그 한 명이거나 null이라 "주인 = 입력자, 없으면 남은 멤버"와 같다)
  foreach v_c in array array[v_old, v_new] loop
    select id into v_sole from couple_members where couple_id = v_c;
    -- 바꾸면 같은 사람·유형·날의 도장이 둘이 되는 경우, 대신 찍은 쪽을 지운다
    delete from events e
      where e.couple_id = v_c and e.owner_member_id <> v_sole and e.shift_type_id is not null
        and exists (select 1 from events d
                    where d.couple_id = v_c and d.owner_member_id = v_sole
                      and d.shift_type_id = e.shift_type_id and d.day = e.day);
    update events set owner_member_id = v_sole where couple_id = v_c and owner_member_id <> v_sole;
    update shift_types set owner_member_id = v_sole where couple_id = v_c and owner_member_id <> v_sole;
  end loop;

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
