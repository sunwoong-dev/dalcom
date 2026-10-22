-- v1 스키마: 커플, 멤버, 초대 코드, 근무 유형, 일정, 기념일 (docs/04-data-model.md)
-- 삭제는 실제 삭제다(deleted_at 없음).

-- updated_at 자동 갱신 트리거 함수
create function public.touch_updated_at() returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 커플 공간
create table public.couples (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  start_date date,
  monthly_budget integer not null default 0 check (monthly_budget >= 0),
  created_by uuid references auth.users on delete set null
);

-- 커플 구성원 겸 프로필 (한 사람은 커플 하나에만 속한다)
create table public.couple_members (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  couple_id uuid not null references public.couples on delete cascade,
  user_id uuid not null unique references auth.users on delete cascade,
  role text not null check (role in ('owner', 'partner')),
  nickname text not null check (char_length(nickname) between 1 and 20),
  birthday date,
  color text not null check (color in ('pink', 'sky', 'mint', 'lilac', 'peach', 'lemon')),
  unique (couple_id, color),
  -- 복합 외래 키 대상: 같은 커플 안의 멤버만 참조하게 한다
  unique (couple_id, id)
);

-- 초대 코드 (커플당 1개, RPC로만 접근)
create table public.invites (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  couple_id uuid not null unique references public.couples on delete cascade,
  code text not null unique check (char_length(code) = 8),
  expires_at timestamptz not null default now() + interval '7 days'
);

-- 근무 도장 종류
create table public.shift_types (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  couple_id uuid not null references public.couples on delete cascade,
  owner_member_id uuid,
  name text not null,
  short_label text not null check (char_length(short_label) between 1 and 3),
  color text not null check (color in ('pink', 'sky', 'mint', 'lilac', 'peach', 'lemon')),
  all_day boolean not null default true,
  start_time time,
  end_time time,
  sort_order smallint not null default 0,
  -- 복합 외래 키 대상: 같은 커플 안의 근무 유형만 참조하게 한다
  unique (couple_id, id),
  -- 다른 커플의 멤버를 가리킬 수 없다. 멤버가 지워지면 owner_member_id만 비운다
  -- deferrable: 연결 끊기 RPC가 한 트랜잭션에서 멤버와 행을 함께 옮긴다
  foreign key (couple_id, owner_member_id) references public.couple_members (couple_id, id)
    on delete set null (owner_member_id) deferrable initially deferred
);

-- 일정과 근무 도장
create table public.events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  couple_id uuid not null references public.couples on delete cascade,
  owner_kind text not null check (owner_kind in ('member', 'together')),
  owner_member_id uuid,
  created_by_member_id uuid,
  shift_type_id uuid,
  title text,
  day date not null,
  end_day date,
  all_day boolean not null default true,
  start_time time,
  end_time time,
  memo text,
  -- 개인 일정은 주인이 있어야 한다
  check (owner_kind <> 'member' or owner_member_id is not null),
  -- 도장이 아니면 제목이 있어야 한다
  check (shift_type_id is not null or title is not null),
  -- 참조는 모두 같은 커플 안으로만 (couple_id는 절대 비우지 않는다)
  foreign key (couple_id, owner_member_id) references public.couple_members (couple_id, id)
    on delete set null (owner_member_id) deferrable initially deferred,
  foreign key (couple_id, created_by_member_id) references public.couple_members (couple_id, id)
    on delete set null (created_by_member_id) deferrable initially deferred,
  foreign key (couple_id, shift_type_id) references public.shift_types (couple_id, id)
    on delete cascade deferrable initially deferred
);

-- 도장 중복 방지: 같은 사람·같은 유형·같은 날은 한 번만
create unique index events_shift_stamp_unique
  on public.events (couple_id, owner_member_id, shift_type_id, day)
  where shift_type_id is not null;
create index events_couple_day_idx on public.events (couple_id, day);
create index events_couple_updated_idx on public.events (couple_id, updated_at);

-- 직접 추가한 기념일
create table public.anniversaries (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  couple_id uuid not null references public.couples on delete cascade,
  title text not null,
  date date not null,
  repeats_yearly boolean not null default true
);

-- 모든 테이블에 updated_at 트리거
create trigger touch_updated_at before update on public.couples
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.couple_members
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.invites
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.shift_types
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.events
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.anniversaries
  for each row execute function public.touch_updated_at();

-- RLS 공용 검사: 지금 사용자가 이 커플의 멤버인가
-- security definer라서 couple_members 정책을 다시 타지 않는다(재귀 방지)
create function public.is_member(p_couple_id uuid) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from couple_members
    where couple_id = p_couple_id and user_id = auth.uid()
  );
$$;

-- 일정 입력자는 로그인한 사용자로 강제한다
-- RPC처럼 auth.uid()가 없는 경우는 넘긴 값을 그대로 둔다
create function public.set_event_created_by() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null then
    new.created_by_member_id := (
      select id from couple_members
      where couple_id = new.couple_id and user_id = auth.uid()
    );
  end if;
  return new;
end;
$$;

create trigger set_event_created_by before insert on public.events
  for each row execute function public.set_event_created_by();

-- 모든 테이블 RLS 켜기
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.invites enable row level security;
alter table public.shift_types enable row level security;
alter table public.events enable row level security;
alter table public.anniversaries enable row level security;

-- couples: 조회·수정만 (생성·삭제는 RPC)
create policy couples_select on public.couples
  for select to authenticated using (public.is_member(id));
create policy couples_update on public.couples
  for update to authenticated using (public.is_member(id)) with check (public.is_member(id));

-- couple_members: 같은 커플끼리 조회, 수정은 자기 행만 (추가·삭제는 RPC)
create policy couple_members_select on public.couple_members
  for select to authenticated using (public.is_member(couple_id));
create policy couple_members_update on public.couple_members
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- 자기 행이라도 couple_id·user_id·role은 못 바꾸게 프로필 컬럼만 수정 허용
revoke update on public.couple_members from anon, authenticated;
grant update (nickname, birthday, color) on public.couple_members to authenticated;

-- invites: 정책 없음 = 직접 접근 전부 거부

-- [C] 테이블: 멤버만 전 동작
create policy shift_types_all on public.shift_types
  for all to authenticated
  using (public.is_member(couple_id)) with check (public.is_member(couple_id));
create policy events_all on public.events
  for all to authenticated
  using (public.is_member(couple_id)) with check (public.is_member(couple_id));
create policy anniversaries_all on public.anniversaries
  for all to authenticated
  using (public.is_member(couple_id)) with check (public.is_member(couple_id));
