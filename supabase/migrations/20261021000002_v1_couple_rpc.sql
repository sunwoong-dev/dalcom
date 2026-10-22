-- v1 커플 RPC: 만들기, 초대 코드, 코드 열기(peek), 가입·합치기 (CPL-03..CPL-05a)
-- 모두 security definer이고 호출자는 auth.uid()다.

-- 초대 코드 생성 헬퍼 (Task 4도 쓴다)
-- 알파벳 32자라 바이트 % 32에 치우침이 없다. 이미 있는 코드와 겹치면 다시 뽑는다
create function public.gen_invite_code() returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
begin
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
    end loop;
    exit when not exists (select 1 from invites where code = v_code);
  end loop;
  return v_code;
end;
$$;

-- 코드 판정 (peek_invite와 join_couple이 같은 규칙을 쓴다, 클라이언트 비공개)
-- 순서: 코드 없음·만료·대상 정원 참·대상이 내 커플 → invalid,
--       내가 2인 커플 → in_full_couple, 내가 1인 커플 → has_own_couple, 그 외 → ok
create function public.invite_status(p_code text, out status text, out target_couple_id uuid, out my_couple_id uuid)
language plpgsql
volatile
set search_path = public
as $$
declare
  v_expires timestamptz;
begin
  select i.couple_id, i.expires_at into target_couple_id, v_expires
    from invites i where i.code = p_code;
  select m.couple_id into my_couple_id from couple_members m where m.user_id = auth.uid();

  if target_couple_id is null
     or v_expires <= now()
     or (select count(*) from couple_members where couple_id = target_couple_id) >= 2
     or target_couple_id = my_couple_id then
    status := 'invalid';
  elsif my_couple_id is not null
     and (select count(*) from couple_members where couple_id = my_couple_id) >= 2 then
    status := 'in_full_couple';
  elsif my_couple_id is not null then
    status := 'has_own_couple';
  else
    status := 'ok';
  end if;
end;
$$;

-- 커플 만들기: 커플, owner 멤버, 기본 근무 유형 2개, 초대 코드
create function public.create_couple(p_start_date date, p_nickname text, p_color text) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple uuid;
  v_member uuid;
begin
  if exists (select 1 from couple_members where user_id = auth.uid()) then
    raise exception 'already_in_couple';
  end if;

  insert into couples (start_date, created_by) values (p_start_date, auth.uid())
    returning id into v_couple;
  insert into couple_members (couple_id, user_id, role, nickname, color)
    values (v_couple, auth.uid(), 'owner', p_nickname, p_color)
    returning id into v_member;
  insert into shift_types (couple_id, owner_member_id, name, short_label, color, all_day, sort_order) values
    (v_couple, v_member, '오전 당직', '오전', 'pink', true, 0),
    (v_couple, v_member, '오후 당직', '오후', 'sky', true, 1);
  insert into invites (couple_id, code, expires_at)
    values (v_couple, gen_invite_code(), now() + interval '7 days');
  return v_couple;
end;
$$;

-- 초대 코드 다시 만들기 (멤버 1명일 때만)
create function public.regenerate_invite() returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple uuid;
  v_code text;
begin
  select couple_id into v_couple from couple_members where user_id = auth.uid();
  -- 가입과 겹치지 않게 커플 행을 잠근 뒤 인원을 센다
  perform 1 from couples where id = v_couple for update;
  if v_couple is null or (select count(*) from couple_members where couple_id = v_couple) <> 1 then
    raise exception 'couple_full';
  end if;

  v_code := gen_invite_code();
  insert into invites (couple_id, code, expires_at)
    values (v_couple, v_code, now() + interval '7 days')
    on conflict (couple_id) do update set code = excluded.code, expires_at = excluded.expires_at;
  return v_code;
end;
$$;

-- 내 커플의 유효한 초대 코드 (멤버 1명일 때만, 공유 화면용)
create function public.current_invite() returns table (code text, expires_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select i.code, i.expires_at
  from invites i
  join couple_members m on m.couple_id = i.couple_id and m.user_id = auth.uid()
  where i.expires_at > now()
    and (select count(*) from couple_members c where c.couple_id = i.couple_id) = 1;
$$;

-- 코드 열기: 상태와 이미 쓰인 색. 데이터는 바꾸지 않는다
-- 색은 가입할 수 있는 상태(ok, has_own_couple)에서만 알려 준다
create function public.peek_invite(p_code text) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v record;
begin
  v := invite_status(p_code);
  return jsonb_build_object(
    'status', v.status,
    'taken_colors', case when v.status in ('ok', 'has_own_couple') then
      coalesce((select jsonb_agg(color order by color) from couple_members where couple_id = v.target_couple_id), '[]'::jsonb)
    else '[]'::jsonb end);
end;
$$;

-- 가입·합치기: 대상 커플을 잠그고 다시 판정한 뒤 partner로 넣고 코드를 지운다
create function public.join_couple(p_code text, p_nickname text, p_color text, p_discard_own boolean) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v record;
begin
  -- 같은 코드로 동시에 가입하면 여기서 줄을 선다. 뒤 사람은 다음 문장에서 지워진 코드를 본다
  perform 1 from couples where id = (select couple_id from invites where code = p_code) for update;
  v := invite_status(p_code);

  if v.status = 'invalid' then
    raise exception 'invalid_invite';
  elsif v.status = 'in_full_couple' then
    raise exception 'in_full_couple';
  elsif v.status = 'has_own_couple' then
    if not p_discard_own then
      raise exception 'has_own_couple';
    end if;
    -- 내 1인 커플을 지운다(멤버·일정·근무 유형·초대 코드는 cascade)
    delete from couples where id = v.my_couple_id;
  end if;

  begin
    insert into couple_members (couple_id, user_id, role, nickname, color)
      values (v.target_couple_id, auth.uid(), 'partner', p_nickname, p_color);
  exception when unique_violation then
    raise exception 'color_taken';
  end;
  delete from invites where couple_id = v.target_couple_id;
  return v.target_couple_id;
end;
$$;

-- 권한: RPC는 로그인 사용자만, 헬퍼는 아무도 직접 못 부른다
revoke execute on function public.gen_invite_code() from public, anon, authenticated;
revoke execute on function public.invite_status(text) from public, anon, authenticated;
revoke execute on function public.create_couple(date, text, text) from public, anon;
revoke execute on function public.regenerate_invite() from public, anon;
revoke execute on function public.current_invite() from public, anon;
revoke execute on function public.peek_invite(text) from public, anon;
revoke execute on function public.join_couple(text, text, text, boolean) from public, anon;
grant execute on function public.create_couple(date, text, text) to authenticated;
grant execute on function public.regenerate_invite() to authenticated;
grant execute on function public.current_invite() to authenticated;
grant execute on function public.peek_invite(text) to authenticated;
grant execute on function public.join_couple(text, text, text, boolean) to authenticated;
