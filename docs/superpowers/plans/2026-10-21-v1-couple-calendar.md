# v1 커플 캘린더 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 커플 연결, 공유 캘린더, 근무 도장, 사람별 알림, 디데이 위젯을 갖춘 iPhone 앱 v1을 무료 환경(무료 Apple ID + Supabase 무료 플랜)에서 동작시킨다.

**Architecture:** SwiftUI 앱과 위젯이 로컬 Swift 패키지 `DateCore`(순수 로직, 시뮬레이터 없이 `swift test`)를 공유한다. 서버는 Supabase(Postgres + RLS + `security definer` RPC + Auth 이메일 OTP + Realtime)이고, 커플 관련 쓰기 중 여러 행을 건드리는 것(가입·합치기·끊기·탈퇴)은 모두 RPC 한 번으로 끝낸다. 앱은 동기화할 때마다 커플 데이터 전체를 받아 `cache.json`을 통째로 바꾼다.

**Tech Stack:** Swift 5.10+/SwiftUI, iOS 17+, Swift Testing, XcodeGen, supabase-swift 2.x, Supabase CLI + Docker(로컬 DB, pgTAP), WidgetKit, UserNotifications, BackgroundTasks.

**Spec:** `docs/01-product-plan.md`, `docs/02-requirements.md`, `docs/03-architecture.md`, `docs/04-data-model.md` (2026-10-21 승인). 요구사항 ID(CPL-xx 등)는 02 문서 기준이다.

## Global Constraints

- 실행 환경: **Mac**(Xcode 16 이상, Docker Desktop, Homebrew). 이 계획은 Windows에서 쓰였고 Windows에서는 빌드할 수 없다.
- 최소 배포 버전 iOS 17.0. 무료 Apple ID(Personal Team) 서명. 유료 전용 capability(iCloud, Push, Associated Domains, Sign in with Apple)는 쓰지 않는다.
- 외부 의존성은 `supabase-swift` 하나뿐이다(앱 타깃만 사용, `DateCore`는 의존성 0). 개발 도구로 XcodeGen과 Supabase CLI를 쓴다.
- 비밀값: 앱에는 Supabase URL과 **anon key만** 넣고, git에서 제외한 `Config/Secrets.xcconfig`로 주입한다. service_role key는 어디에도 쓰지 않는다. 키 값을 채팅에 붙여 넣거나 출력하지 않는다.
- **커밋은 매번 사용자에게 파일 목록과 메시지를 보여주고 승인받은 뒤에 한다**(사용자 전역 규칙). 메시지 형식은 `<type>: <한국어 요약>`이다.
- 코드 주석은 한국어로, 식별자와 파일명은 영어로 쓴다.
- 색 팔레트(키 → hex): `pink #F7C6D3`, `sky #C9E2F5`, `mint #CDEBDD`, `lilac #DCD3F2`, `peach #FAD6C4`, `lemon #FBEAB0`. 배경 `#FFF6F8`, 글자 `#4D4247`.
- 고정 문구(그대로 쓴다):
  - 합치기 경고: `기존에 생성된 기능이 비활성화됩니다. 입력했던 일정도 함께 사라져요.` 버튼: `유지`, `삭제`
  - 잘못된 코드: `접근할 수 없는 링크입니다.`
  - 오프라인 저장: `인터넷 연결 후 저장할 수 있어요`
- 화면 문자열은 String Catalog(`Localizable.xcstrings`)로 관리한다(NFR-04). 색은 Asset Catalog 색 세트로 쓰고 다크 모드 변형을 함께 둔다(NFR-01). 주인 구분에는 색과 함께 글자를 붙인다(NFR-03).
- 디데이: 시작일 당일이 D+1이다.
- 알림 기본값: 모든 분류가 "당일 오전 8시"다. 예약 범위는 14일, 최대 64개다.
- 앱 표시 이름은 아직 정하지 않았다. 표시 이름은 `달콤`(임시), 타깃 이름은 `DateApp`, URL 스킴은 `dateapp`이다. 번들 ID 접두사는 Task 1에서 사용자에게 묻는다.

## Review Focus

1. **같은 초대 코드로 두 사람이 거의 동시에 가입**하면 정확히 한 명만 들어가고, 다른 한 명은 `invalid`가 나와야 한다. → Task 3 `join_race_full` 테스트.
2. **자기 커플의 코드를 자기가 입력**하면 합치기 경고 없이 `invalid`가 나와야 한다(내 커플이 지워지면 안 됨). → Task 3 `peek_own_code_invalid` 테스트.
3. **이미 2명이 찬 커플에 속한 사람이 다른 코드를 열면** `discard_own`으로 상대의 데이터까지 지워지면 안 된다. 상태는 `in_full_couple`이다. → Task 3 `peek_in_full_couple` 테스트.
4. **시간이 있는 근무 유형의 시간을 나중에 바꾸면** 이미 찍은 도장의 알림 시각도 바뀌어야 한다. → Task 6 `shift_time_from_type` 테스트.
5. **알림 시각이 이미 지난 일정**(예: 오늘 08:00이 지난 뒤 오늘 일정을 추가)은 예약하지 않아야 한다. 과거 알림이 즉시 울리면 안 된다. → Task 6 `skips_past_fire_dates` 테스트.

---

## 파일 구조

```
date/
├─ .gitignore
├─ project.yml                         XcodeGen: DateApp(앱), DateWidget(확장), DateCore(로컬 패키지)
├─ Config/Secrets.example.xcconfig     SUPABASE_URL, SUPABASE_ANON_KEY 자리
├─ Config/Secrets.xcconfig             (git 제외) 실제 값
├─ Packages/DateCore/
│   ├─ Package.swift
│   ├─ Sources/DateCore/
│   │   ├─ LocalDate.swift             날짜·시각 값 타입 (Postgres date/time과 문자열 호환)
│   │   ├─ Models.swift                Couple, Member, ShiftType, Event, Anniversary, CoupleSnapshot
│   │   ├─ Palette.swift               PaletteColor, availableColors
│   │   ├─ InviteCode.swift            코드 정규화·표시 형식
│   │   ├─ DDay.swift                  D+N, 다가오는 기념일
│   │   ├─ CalendarLogic.swift         월 그리드, 도장 토글, 상대 변경 감지
│   │   └─ ReminderPlanner.swift       사람별 알림 계획
│   └─ Tests/DateCoreTests/            파일별 테스트
├─ App/
│   ├─ DateApp.swift, RootView.swift, Info.plist
│   ├─ Backend/ SupabaseService.swift, SyncStore.swift, NotificationScheduler.swift, WidgetBridge.swift
│   └─ Features/ Auth/, Onboarding/, Calendar/, Us/
├─ Widget/ DateWidget.swift, Info.plist
└─ supabase/
    ├─ config.toml
    ├─ migrations/20261021000001_v1_schema.sql
    ├─ migrations/20261021000002_v1_couple_rpc.sql
    ├─ migrations/20261021000003_v1_leave_rpc.sql
    └─ tests/ schema_rls.test.sql, couple_rpc.test.sql, leave_rpc.test.sql
```

v1에는 `categories`, `preferences`, `person_tags`, `date_records`, `photos`, `expenses` 테이블을 만들지 않는다(v2 이후 마이그레이션). 04 문서의 v1 범위는 `couples`, `couple_members`, `invites`, `shift_types`, `events`, `anniversaries`다.

---

### Task 1: 저장소·프로젝트 골격과 무료 서명 확인

**Files:**
- Create: `.gitignore`, `project.yml`, `Config/Secrets.example.xcconfig`, `Packages/DateCore/Package.swift`, `Packages/DateCore/Sources/DateCore/DateCore.swift`(패키지가 빌드되도록 두는 자리 파일. Task 5에서 지운다), `App/DateApp.swift`, `App/RootView.swift`, `App/Info.plist`, `Widget/DateWidget.swift`, `Widget/Info.plist`, `docs/setup.md`

**Interfaces:**
- Produces: 스킴 `DateApp`, 앱 그룹 ID `group.<prefix>.dateapp`(사용 가능할 때), 빌드 설정 `SUPABASE_URL`, `SUPABASE_ANON_KEY` → Info.plist 키 `SupabaseURL`, `SupabaseAnonKey`.

- [ ] **Step 1: 환경 확인.** `xcodebuild -version`(16 이상), `brew --version`, `docker --version`을 실행한다. Xcode가 16보다 낮으면 멈추고 사용자에게 macOS·Mac 모델을 보고한다.
- [ ] **Step 2: 사용자에게 번들 ID 접두사를 묻는다**(예: `com.hong`). 최종 번들 ID는 `<prefix>.dateapp`, 위젯은 `<prefix>.dateapp.widget`이다.
- [ ] **Step 3: 저장소는 이미 있다**(Windows에서 문서를 커밋하고 GitHub에 푸시해 둠. Mac에서는 `git clone`으로 받는다). `.gitignore`에 아래 항목이 모두 있는지 확인하고 없으면 추가한다. 제외 대상: `Config/Secrets.xcconfig`, `*.xcodeproj`(XcodeGen이 생성), `.build/`, `DerivedData/`, `supabase/.temp/`, `.env*`, `.DS_Store`.
- [ ] **Step 4: `brew install xcodegen supabase/tap/supabase`.** 설치 전에 사용자에게 알린다(새 개발 도구 2개).
- [ ] **Step 5: `project.yml`을 쓴다.** 앱 타깃(iOS 17, Swift Testing, URL 스킴 `dateapp`, `UIBackgroundModes: [fetch]`, `BGTaskSchedulerPermittedIdentifiers: [<prefix>.dateapp.refresh]`, 패키지 `supabase-swift` from `2.0.0` → 제품 `Supabase`, 로컬 패키지 `DateCore`), 위젯 확장 타깃(`DateCore`만 의존), 두 타깃 모두 App Groups 엔타이틀먼트 `group.<prefix>.dateapp`. xcconfig 기반 설정은 `Config/Secrets.xcconfig`다.
- [ ] **Step 6: `DateCore` 패키지와 최소 앱·위젯 코드를 쓴다**(빈 화면 `Text("달콤")`, 정적 위젯 1개). 앱 타깃에 `Localizable.xcstrings`와 Asset Catalog 색 세트(팔레트 6색, 배경, 글자. 각각 다크 모드 변형 포함)를 넣는다.
- [ ] **Step 7: 빌드한다.** `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig && xcodegen generate && xcodebuild -scheme DateApp -destination 'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`
- [ ] **Step 8: 무료 서명과 App Groups를 확인한다.** 사용자가 Xcode에서 Team을 Personal Team으로 고르고 실기기에 실행한다. 결과를 `docs/setup.md`에 적는다.
  - App Groups 서명 성공 → **위젯 A안**(Task 12 A).
  - "Personal development teams … do not support the App Groups capability" 오류 → 두 타깃에서 엔타이틀먼트를 빼고 **위젯 B안**(Task 12 B).
- [ ] **Step 9: `docs/setup.md`에 Mac 준비 절차를 적는다**(도구 설치, Secrets 복사, xcodegen, 7일마다 재설치하는 방법).
- [ ] **Step 10: 커밋(승인 후).** `chore: Xcode 프로젝트 골격과 무료 서명 설정`

### Task 2: Supabase v1 스키마와 RLS

**Files:**
- Create: `supabase/config.toml`(`supabase init`), `supabase/migrations/20261021000001_v1_schema.sql`
- Test: `supabase/tests/schema_rls.test.sql`

**Interfaces:**
- Produces: 테이블 `couples`, `couple_members`, `invites`, `shift_types`, `events`, `anniversaries`(04 문서 컬럼 그대로, `deleted_at` 없음). 함수 `public.is_member(p_couple_id uuid) returns boolean`(security definer, stable). 트리거 함수 `public.touch_updated_at()`.

- [ ] **Step 1: `supabase init && supabase start`** → 로컬 API URL과 키가 출력된다(출력된 키를 문서나 채팅에 옮기지 않는다).
- [ ] **Step 2: 실패하는 RLS 테스트를 쓴다.** pgTAP으로 사용자 u1, u2, u3를 `auth.users`에 넣고, u1·u2 커플 C1과 u3 커플 C2를 superuser로 만든 뒤 `set local role authenticated; set local request.jwt.claims = '{"sub":"<u3>"}'`로 바꿔 검증한다.
  - `events_isolated`: u3 시점에서 `select count(*) from events where couple_id = C1` = 0
  - `events_insert_blocked`: u3가 C1에 insert하면 `42501`(RLS 위반)
  - `members_visible_to_partner`: u2 시점에서 C1 멤버 수 = 2
  - `member_update_own_only`: u2가 u1 멤버 행의 nickname을 update하면 0행 변경
  - `invites_hidden`: u1 시점에서 `select count(*) from invites` = 0 (자기 커플 코드라도 직접 조회 불가)
  - `color_unique`: 같은 커플에 같은 color로 두 번째 멤버를 넣으면 `23505`
  - `shift_stamp_unique`: 같은 (owner_member_id, shift_type_id, day)로 두 번째 insert하면 `23505`
- [ ] **Step 3: `supabase test db`** → 테이블이 없어서 FAIL
- [ ] **Step 4: 마이그레이션을 쓴다.** 04 문서의 v1 테이블 6개, `check` 제약, `couple_members.user_id unique`, `unique(couple_id, color)`, events 부분 유니크 인덱스 `where shift_type_id is not null`, 인덱스 `(couple_id, day)`, 모든 테이블에 `updated_at` 트리거, 모든 테이블 RLS를 켠다. 정책은 [C] 테이블 전 동작 `is_member(couple_id)`, couples는 select/update만 `is_member(id)`, couple_members는 select `is_member(couple_id)`이고 update는 `user_id = auth.uid()`, invites는 정책 없음(전부 거부)이다. events check: `owner_kind='member'`이면 `owner_member_id is not null`, `shift_type_id is null`이면 `title is not null`.
- [ ] **Step 5: `supabase test db`** → 7개 PASS
- [ ] **Step 6: 커밋(승인 후).** `feat: v1 DB 스키마와 행 단위 보안 정책 추가`

### Task 3: 커플 만들기·초대·가입·합치기 RPC

**Files:**
- Create: `supabase/migrations/20261021000002_v1_couple_rpc.sql`
- Test: `supabase/tests/couple_rpc.test.sql`

**Interfaces:**
- Consumes: Task 2 테이블, `is_member`
- Produces (모두 `security definer`, `set search_path = public`, 호출자는 `auth.uid()`):
  - `create_couple(p_start_date date, p_nickname text, p_color text) returns uuid`: 커플, owner 멤버, 기본 근무 유형 2개(`오전 당직/오전/pink`, `오후 당직/오후/sky`, all_day=true, owner=본인), 초대 코드를 만든다. 이미 멤버이면 `raise exception 'already_in_couple'`.
  - `regenerate_invite() returns text`: 멤버가 1명일 때만 동작한다. 아니면 `'couple_full'`. 기존 코드를 교체한다.
  - `current_invite() returns table(code text, expires_at timestamptz)`: 내 커플의 유효한 코드(멤버 1명일 때만). 앱의 공유 화면용.
  - `peek_invite(p_code text) returns jsonb`: `{"status": "ok"|"invalid"|"has_own_couple"|"in_full_couple", "taken_colors": [...]}`. 판정 순서: 코드 없음·만료·대상 정원 참·**대상이 내 커플** → `invalid`. 내가 2인 커플 소속 → `in_full_couple`. 내가 1인 커플 소속 → `has_own_couple`. 그 외 → `ok`. 데이터는 바꾸지 않는다.
  - `join_couple(p_code text, p_nickname text, p_color text, p_discard_own boolean) returns uuid`: 대상 커플 행을 `for update`로 잠근 뒤 peek와 같은 판정을 다시 한다. `has_own_couple`이면서 `p_discard_own`이 false면 `'has_own_couple'`. true면 내 커플을 delete한다(cascade로 내 초대 코드도 삭제). 멤버(role='partner')를 insert하고(color 충돌 시 `'color_taken'`) 대상 커플의 invites 행을 delete한다. 잘못된 코드면 `'invalid_invite'`, 2인 커플 소속이면 `'in_full_couple'`.
  - 코드 생성: 알파벳 `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`에서 8자, `gen_random_bytes`를 쓴다. 충돌하면 재시도한다. 만료는 `now() + interval '7 days'`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**(pgTAP, 사용자별로 `request.jwt.claims` 전환).
  - `create_makes_owner_and_defaults`: u1 `create_couple('2026-01-01','민수','sky')` → 멤버 1명(owner), shift_types 2개, `current_invite()` 1행
  - `create_twice_fails`: u1이 다시 호출하면 `already_in_couple`
  - `peek_ok`: u2가 u1 코드로 peek → status `ok`, taken_colors `{sky}`
  - `join_closes_invite`: u2 join(…, 'pink', false) → 멤버 2명, u1 시점 `current_invite()` 0행, u3 peek 같은 코드 → `invalid`
  - `join_color_taken`: u2가 'sky'로 join하면 `color_taken`, 멤버 수는 그대로 1
  - `peek_own_code_invalid`: u1이 자기 코드로 peek → `invalid`
  - `merge_flow` (CPL-04b/04c): uA, uB가 각각 커플을 만든다. uA peek(B코드) → `has_own_couple`. uA join(B코드, discard=false) → `has_own_couple` 예외. uA join(B코드, discard=true) → uA는 B 커플 멤버이고, A 커플 행 0개, A 커플 events 0개. uB peek(A의 옛 코드) → `invalid`
  - `peek_in_full_couple`: 2인 커플 소속 u2가 u3의 코드로 peek → `in_full_couple`. join(discard=true) → `in_full_couple` 예외이고 u1·u2 커플은 그대로
  - `join_race_full`: u2 join 성공 뒤 u3가 같은 코드로 join → `invalid_invite`(코드 삭제 + 정원 재확인)
  - `expired_invalid`: superuser로 expires_at을 과거로 바꾸면 peek → `invalid`
- [ ] **Step 2: `supabase test db`** → FAIL(함수 없음)
- [ ] **Step 3: 마이그레이션에 위 함수 5개와 코드 생성 헬퍼를 구현한다.** `revoke execute … from public, anon; grant execute … to authenticated`.
- [ ] **Step 4: `supabase test db`** → 전부 PASS
- [ ] **Step 5: 커밋(승인 후).** `feat: 커플 만들기·초대·합치기 RPC 추가`

### Task 4: 연결 끊기·계정 삭제 RPC

**Files:**
- Create: `supabase/migrations/20261021000003_v1_leave_rpc.sql`
- Test: `supabase/tests/leave_rpc.test.sql`

**Interfaces:**
- Produces:
  - `leave_couple() returns uuid`: 혼자면 커플을 delete하고 null을 반환한다. 둘이면 한 트랜잭션에서 아래를 처리하고 내 새 커플 id를 반환한다(CPL-06, 06a).
    1. 새 커플(start_date null, created_by 나)을 만들고, 내 멤버 행의 couple_id를 새 커플로 바꾸고 role을 owner로 한다.
    2. `created_by_member_id = 나`인 events를 새 커플로 옮긴다.
    3. 옮긴 events가 쓰는 shift_types 중, 남은 events도 쓰는 것은 새 커플에 복사해 옮긴 events가 복사본을 가리키게 한다. 나머지는 통째로 옮긴다.
    4. 두 커플 모두에서 `owner_member_id`가 그 커플 멤버가 아닌 events는 `owner_member_id = created_by_member_id`로 바꾼다. created_by가 null이면 그 커플 남은 멤버로 바꾼다. 남은 근무 유형의 owner도 같은 규칙을 따른다.
    5. 기존 커플의 anniversaries를 delete한다.
    6. 남은 멤버를 owner로 바꾸고 기존 커플에 새 초대 코드를 만든다. 새 커플에도 초대 코드를 만든다.
  - `delete_my_account() returns void`: `leave_couple()` 처리 → 새로 생긴 내 1인 커플 delete → `delete from auth.users where id = auth.uid()`.

- [ ] **Step 1: 실패하는 테스트를 쓴다.**
  - `leave_alone_deletes`: 1인 커플에서 leave → couples 0행, 반환 null
  - `leave_keeps_own_events`: u1(민수)과 u2(지은)의 커플. events: e1(u1이 입력, owner u1), e2(u2가 입력, owner u2, 오전 당직 도장), e3(u1이 입력, owner u2, 오후 당직 도장 = 대신 찍음), e4(u2가 입력, together). u1 leave 후:
    - u1 시점 events = {e1, e3}, e3.owner_member_id = u1 멤버, e3의 shift_type은 u1 새 커플 소속
    - u2 시점 events = {e2, e4}, 기존 커플 멤버 1명, `current_invite()` 1행
    - 기존 커플 anniversaries 0행
  - `leave_copies_shared_shift_type`: 위 상황에 e5(u2가 입력, 오후 당직)를 더하면 u1의 e3과 u2의 e5가 서로 다른 shift_type id를 가리킨다
  - `delete_account_removes_user`: u1 delete_my_account → `auth.users`에 u1 없음, u2의 커플과 e2·e4는 남음
- [ ] **Step 2: `supabase test db`** → FAIL
- [ ] **Step 3: 구현한다.** 권한은 Task 3과 같다.
- [ ] **Step 4: `supabase test db`** → 전부 PASS
- [ ] **Step 5: 커밋(승인 후).** `feat: 연결 끊기와 계정 삭제 RPC 추가`

### Task 5: DateCore 모델·팔레트·초대 코드·디데이

**Files:**
- Create: `Packages/DateCore/Sources/DateCore/{LocalDate,Models,Palette,InviteCode,DDay}.swift`
- Delete: `Packages/DateCore/Sources/DateCore/DateCore.swift`
- Test: `Packages/DateCore/Tests/DateCoreTests/{LocalDateTests,PaletteTests,InviteCodeTests,DDayTests}.swift`

**Interfaces:**
- Produces:
  - `struct LocalDate: Codable, Hashable, Comparable { year, month, day: Int }`. JSON은 `"yyyy-MM-dd"` 문자열이다. `func adding(days: Int) -> LocalDate`, `static func today(in: Calendar) -> LocalDate`, `func date(hour: Int, minute: Int, in: Calendar) -> Date`
  - `struct LocalTime: Codable, Hashable { hour, minute: Int }`. JSON은 `"HH:mm:ss"`이고 디코딩은 `"HH:mm"`도 허용한다.
  - 모델(모두 `Codable, Identifiable, Hashable`, CodingKeys는 snake_case 컬럼명): `Couple { id, startDate: LocalDate? }`, `Member { id, coupleId, userId, role: String, nickname, birthday: LocalDate?, color: PaletteColor }`, `ShiftType { id, coupleId, ownerMemberId: UUID?, name, shortLabel, color: PaletteColor, allDay: Bool, startTime: LocalTime?, endTime: LocalTime?, sortOrder: Int }`, `enum OwnerKind: String { member, together }`, `Event { id, coupleId, ownerKind, ownerMemberId: UUID?, createdByMemberId: UUID?, shiftTypeId: UUID?, title: String?, day: LocalDate, endDay: LocalDate?, allDay: Bool, startTime: LocalTime?, endTime: LocalTime?, memo: String?, updatedAt: Date }`, `Anniversary { id, coupleId, title, date: LocalDate, repeatsYearly: Bool }`
  - `struct CoupleSnapshot: Codable, Equatable { couple: Couple; members: [Member]; shiftTypes: [ShiftType]; events: [Event]; anniversaries: [Anniversary]; meMemberId: UUID }`
  - `enum PaletteColor: String, Codable, CaseIterable { pink, sky, mint, lilac, peach, lemon }`, `var hex: String`, `static func available(taken: Set<PaletteColor>) -> [PaletteColor]`
  - `enum InviteCode { static func normalize(_ input: String) -> String?; static func display(_ code: String) -> String }`
  - `struct Milestone: Equatable { title: String; date: LocalDate; daysLeft: Int }`, `enum DDay { static func dayNumber(start: LocalDate, today: LocalDate) -> Int; static func upcoming(start: LocalDate?, members: [Member], custom: [Anniversary], today: LocalDate, limit: Int) -> [Milestone] }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**(Swift Testing).
  - `LocalDate` 왕복: `"2026-02-28"` 디코딩 → `adding(days: 1)` → `"2026-03-01"`
  - `Event` 디코딩: snake_case JSON(`owner_kind`, `start_time: "08:30:00"`, `updated_at` ISO8601 소수초 포함) → 필드 일치
  - `PaletteColor.available(taken: [.sky])`는 5개이고 `.sky`가 없다. `PaletteColor.pink.hex == "#F7C6D3"`
  - `InviteCode.normalize("abcd-efgh")` → `"ABCDEFGH"`. `normalize("dateapp://join?code=ABCDEFGH")` → `"ABCDEFGH"`. `normalize("ABCD0FGH")` → nil(0은 알파벳에 없음). `normalize("ABC")` → nil. `display("ABCDEFGH")` → `"ABCD-EFGH"`
  - `DDay.dayNumber(start: 2026-01-01, today: 2026-01-01)` = 1, `today: 2026-04-10` = 100, `today: 2025-12-31` = 0
  - `upcoming(start: 2026-01-01, members: [], custom: [], today: 2026-04-01, limit: 2)` = `[("100일", 2026-04-10, 9), ("200일", 2026-07-19, 109)]`
  - 1주년: `today: 2026-12-01`이면 결과에 `("1주년", 2027-01-01, 31)`이 들어간다
  - 생일: 멤버 지은의 birthday 1998-05-03, today 2026-05-04이면 `("지은 생일", 2027-05-03, 364)`
  - 사용자 기념일: repeatsYearly=false이고 지난 날짜면 제외된다. repeatsYearly=true면 다음 해 날짜로 들어간다
  - 2월 29일 시작·생일은 평년에 2월 28일로 계산한다
  - start nil이면 생일과 사용자 기념일만 나온다
- [ ] **Step 2: `swift test --package-path Packages/DateCore`** → FAIL(컴파일 에러)
- [ ] **Step 3: 구현한다.** 날짜 계산은 `Calendar(identifier: .gregorian)`으로 한다. `upcoming`은 100일 단위(최대 10000일)·N주년·생일·사용자 기념일 중 `date >= today`인 것을 날짜순으로 `limit`개 돌려준다. 같은 날이면 위 순서를 따른다.
- [ ] **Step 4: `swift test --package-path Packages/DateCore`** → PASS
- [ ] **Step 5: 커밋(승인 후).** `feat: DateCore 모델과 디데이 계산 추가`

### Task 6: DateCore 달력 로직과 알림 계획

**Files:**
- Create: `Packages/DateCore/Sources/DateCore/{CalendarLogic,ReminderPlanner}.swift`
- Test: `Packages/DateCore/Tests/DateCoreTests/{CalendarLogicTests,ReminderPlannerTests}.swift`

**Interfaces:**
- Consumes: Task 5 모델
- Produces:
  - `enum CalendarLogic`
    - `static func monthGrid(year: Int, month: Int, firstWeekday: Int = 1) -> [LocalDate?]`: 일요일 시작, 7의 배수 길이, 앞쪽은 nil
    - `enum StampAction: Equatable { case insert, delete(UUID) }`, `static func stampAction(events: [Event], day: LocalDate, ownerMemberId: UUID, shiftTypeId: UUID) -> StampAction`
    - `static func events(on day: LocalDate, in events: [Event]) -> [Event]`: endDay 범위를 포함하고, 하루 종일 일정 먼저, 그다음 시작 시각순
    - `static func partnerChanges(old: CoupleSnapshot?, new: CoupleSnapshot) -> Set<UUID>`: 새로 생겼거나 updatedAt이 바뀐 이벤트 중 `createdByMemberId != new.meMemberId`인 것. old가 nil이면 빈 집합
  - `enum ReminderOption: String, Codable, CaseIterable { none, day8, at, m10, m60, d1, eve21 }`
  - `struct ReminderRules: Codable, Equatable { var mine, partner, together, partnerShift: ReminderOption; static let `default` }`: 기본값은 모두 `.day8`
  - `struct PlannedNotification: Equatable { id: String; fireDate: Date; title: String; body: String }`. id는 이벤트 UUID 문자열이다
  - `enum ReminderPlanner { static func plan(snapshot: CoupleSnapshot, rules: ReminderRules, overrides: [UUID: ReminderOption], now: Date, calendar: Calendar, horizonDays: Int = 14, limit: Int = 64) -> [PlannedNotification] }`

분류 규칙: together → `together`, owner가 나 → `mine`, owner가 상대이고 shiftTypeId가 있음 → `partnerShift`, 그 외 상대 → `partner`. override가 있으면 override를 쓴다.
시각 규칙: 시작 시각은 `event.startTime`이고, 도장 일정이면 `shiftType.startTime`을 쓴다(allDay이면 없음). `day8` = 그날 08:00. `at`/`m10`/`m60` = 시작 시각 기준이고 시작 시각이 없으면 그날 08:00. `d1` = 시작 시각 −24시간, 시작 시각이 없으면 전날 08:00. `eve21` = 전날 21:00.
문구: title = 이벤트 제목(도장이면 shiftType.name). body = `"<오늘|내일> · <닉네임|함께> · <HH:mm 시작|하루 종일>"`. `d1`·`eve21`은 "내일", 나머지는 "오늘"이다.
대상: `day`가 오늘부터 `horizonDays` 안에 있고 `fireDate > now`인 것을 fireDate순으로 정렬해 앞에서 `limit`개.

- [ ] **Step 1: 실패하는 테스트를 쓴다.**
  - `monthGrid(2026, 10)`: 길이 35, 첫 4칸 nil(2026-10-01은 목요일), 5번째 칸 2026-10-01
  - `stampAction`: 같은 (day, owner, shiftType) 이벤트가 있으면 `.delete(id)`, owner만 다르면 `.insert`
  - `events(on:)`: 10-20~10-22 여러 날 일정이 10-21에 포함된다. 하루 종일 일정이 09:00 일정보다 앞이다
  - `partnerChanges`: 상대가 만든 새 이벤트 1개와 내가 만든 새 이벤트 1개 → 상대 것 1개만. 상대 이벤트의 updatedAt만 바뀌어도 포함된다
  - `default_all_day8`: 상대의 하루 종일 일정 2026-10-22 → fireDate 2026-10-22 08:00(Asia/Seoul), body `"오늘 · 지은 · 하루 종일"`
  - `per_person_override`: 같은 이벤트에 override `.none` → 결과 없음
  - `partner_shift_eve21`: 규칙 partnerShift=`.eve21`, 상대 "오전 당직" 도장 10-23 → fireDate 10-22 21:00, title `"오전 당직"`, body `"내일 · 지은 · 하루 종일"`
  - `shift_time_from_type`: 근무 유형 startTime 09:00, allDay=false, 규칙 `.m60` → 08:00. 유형 startTime을 13:00으로 바꾼 snapshot → 12:00
  - `skips_past_fire_dates`: now = 10-21 09:00, 10-21 하루 종일 일정(day8) → 결과 없음
  - `horizon_and_limit`: 30일 동안 매일 일정 → 14일치만. 하루 10개씩 → 64개, 시간순
- [ ] **Step 2: `swift test --package-path Packages/DateCore`** → FAIL
- [ ] **Step 3: 구현한다.**
- [ ] **Step 4: `swift test --package-path Packages/DateCore`** → PASS
- [ ] **Step 5: 커밋(승인 후).** `feat: 달력 로직과 사람별 알림 계획 추가`

### Task 7: 앱 백엔드 계층 (Supabase 연결·동기화·캐시)

**Files:**
- Create: `App/Backend/SupabaseService.swift`, `App/Backend/SyncStore.swift`
- Modify: `App/DateApp.swift`

**Interfaces:**
- Consumes: Task 2~4 RPC, Task 5~6 DateCore
- Produces:
  - `final class SupabaseService`: `static let shared`. Info.plist의 `SupabaseURL`·`SupabaseAnonKey`로 `SupabaseClient`를 만든다.
    - 로그인: `sendOTP(email:) async throws`, `verifyOTP(email:code:) async throws`, `signOut() async throws`, `var currentUserId: UUID?`
    - RPC: `createCouple(start: LocalDate?, nickname: String, color: PaletteColor) async throws -> UUID`, `currentInvite() async throws -> String?`, `regenerateInvite() async throws -> String`, `peekInvite(code:) async throws -> InvitePeek`, `joinCouple(code:nickname:color:discardOwn:) async throws -> UUID`, `leaveCouple() async throws`, `deleteMyAccount() async throws`
    - `fetchSnapshot() async throws -> CoupleSnapshot?`: 내 멤버 행 → 커플 → 나머지 4개 테이블을 전체 조회한다. 멤버가 아니면 nil
    - CRUD: `upsert(_ event: Event)`, `delete(eventId:)`, `upsert(_ shiftType:)`, `delete(shiftTypeId:)`, `upsert(_ anniversary:)`, `delete(anniversaryId:)`, `updateMyProfile(nickname:birthday:color:)`, `updateStartDate(_:)`
    - `struct InvitePeek { enum Status: String { ok, invalid, has_own_couple, in_full_couple }; status; takenColors: Set<PaletteColor> }`
    - `enum BackendError: Error { invalidInvite, hasOwnCouple, inFullCouple, colorTaken, alreadyInCouple, offline, other(String) }`: Postgres 예외 메시지를 이 값으로 바꾼다
  - `@Observable @MainActor final class SyncStore`
    - `private(set) var snapshot: CoupleSnapshot?`, `private(set) var partnerChangedIds: Set<UUID>`, `private(set) var isOnline: Bool`(`NWPathMonitor`)
    - `func refresh() async`: fetchSnapshot → `partnerChanges` 누적 → `cache.json`(Application Support) 저장 → `onSnapshotChanged` 호출
    - `func loadCache()`, `func startRealtime()`/`stopRealtime()`: 내 couple_id 필터로 events·shift_types·anniversaries·couple_members·couples의 변경을 받으면 0.5초 디바운스 후 `refresh()`
    - `func clearPartnerChanges()`
    - `var onSnapshotChanged: ((CoupleSnapshot) -> Void)?`: Task 11, 12가 알림·위젯 갱신을 연결한다
    - 쓰기 래퍼: `isOnline == false`이면 `BackendError.offline`을 던진다. 성공하면 `refresh()`

- [ ] **Step 1: 사용자가 Supabase 프로젝트를 만든다**(supabase.com, 무료, 지역 Northeast Asia (Seoul)). Auth에서 Email OTP를 켜고 Email 템플릿 "Magic Link"를 `{{ .Token }}` 코드가 보이게 바꾼다. URL과 anon key는 사용자가 직접 `Config/Secrets.xcconfig`에 넣는다. 이 단계와 2026-10-30 Data API 변경 공지 확인 결과를 `docs/setup.md`에 적는다.
- [ ] **Step 2: `supabase link --project-ref <ref>` → `supabase db push`** → 마이그레이션 3개 적용
- [ ] **Step 3: SupabaseService와 SyncStore를 구현한다.** 디코딩은 DateCore 모델의 CodingKeys를 쓴다. 날짜 디코딩은 소수초 ISO8601을 허용하도록 설정한다.
- [ ] **Step 4: 빌드한다.** `xcodebuild -scheme DateApp -destination 'generic/platform=iOS Simulator' build` → 성공
- [ ] **Step 5: 확인용 임시 화면에서 원격 왕복을 확인한다.** 시뮬레이터에서 `tmpqa-` 접두사 닉네임으로 OTP 로그인 → createCouple → refresh → snapshot.shiftTypes 2개 → deleteMyAccount → Supabase 대시보드에서 해당 사용자 0명. 잔여 데이터 0건을 보고한다. 임시 화면은 지운다.
- [ ] **Step 6: 커밋(승인 후).** `feat: Supabase 연결과 전체 동기화 저장소 추가`

### Task 8: 로그인과 온보딩 (커플 만들기·초대·합치기)

**Files:**
- Create: `App/Features/Auth/LoginView.swift`, `App/Features/Onboarding/{OnboardingView,CreateCoupleView,JoinCoupleView,ColorPicker,InviteShareView}.swift`
- Modify: `App/RootView.swift`, `App/DateApp.swift`(`.onOpenURL`)

**Interfaces:**
- Consumes: Task 7 `SupabaseService`, `SyncStore`, Task 5 `InviteCode`, `PaletteColor`
- Produces: `RootView`의 상태 분기: 로그인 전 → `LoginView`, 커플 없음 → `OnboardingView`, 커플 있음 → `MainTabView`(Task 9). `@State var pendingInviteCode: String?`(URL로 들어온 코드).

화면 규칙:
- LoginView: 이메일 입력 → "코드 보내기" → 6자리 입력 → 확인. 실패하면 "코드가 맞지 않아요. 다시 확인해 주세요."
- OnboardingView: 버튼 2개 "커플 만들기", "초대 받았어요"
- CreateCoupleView: 사귄 날(DatePicker, 비워 둘 수 있음), 닉네임(1~20자), 색(6색 전부) → createCouple → InviteShareView
- InviteShareView: 코드를 `XXXX-XXXX`로 크게 보여 주고 `ShareLink` 텍스트 `"달콤 초대 코드: XXXX-XXXX\ndateapp://join?code=XXXXXXXX"`를 공유한다. "나중에 할게" → 메인. 우리 탭에서도 다시 열 수 있다(멤버 1명일 때)
- JoinCoupleView: 코드 입력(또는 URL로 미리 채움) → peekInvite
  - `invalid` → 알림창 `접근할 수 없는 링크입니다.`
  - `in_full_couple` → 알림창 `이미 커플이 연결되어 있어요. 연결을 끊은 뒤 다시 시도해 주세요.`
  - `has_own_couple` → 알림창 `기존에 생성된 기능이 비활성화됩니다. 입력했던 일정도 함께 사라져요.` 버튼 `유지`(닫기, 아무것도 안 함) / `삭제`(destructive, discardOwn=true로 진행)
  - `ok` 또는 삭제 선택 → 닉네임 + 색(`PaletteColor.available(taken:)`) → joinCouple → `colorTaken`이면 다시 peek해서 색 목록을 갱신한다
- `.onOpenURL`: `InviteCode.normalize(url.absoluteString)`가 성공하면 로그인 여부와 관계없이 코드를 보관하고, 로그인 후 JoinCoupleView를 연다. 이미 커플이 있으면 우리 탭 위에 시트로 연다

- [ ] **Step 1: 화면들을 구현한다.**
- [ ] **Step 2: 빌드한다** → 성공
- [ ] **Step 3: 시뮬레이터 2대로 확인한다**(iPhone A, B, 서로 다른 `tmpqa-` 이메일).
  - A 커플 만들기 → B 코드로 가입 → 두 기기 모두 메인 탭. A 우리 탭에서 초대 코드가 사라진 것 확인
  - 합치기: C·D 각각 커플 만들기 → C가 D 코드 열기 → 경고 문구 확인 → `유지` → 변화 없음 → 다시 열고 `삭제` → C가 D 커플에 합류 → D가 C의 옛 코드 입력 → `접근할 수 없는 링크입니다.`
  - 시뮬레이터에서 `xcrun simctl openurl booted "dateapp://join?code=<코드>"` → 가입 화면에 코드가 미리 채워짐
  - 끝나면 테스트 계정을 모두 계정 삭제하고 잔여 0건을 보고한다
- [ ] **Step 4: 커밋(승인 후).** `feat: 로그인과 커플 연결 온보딩 화면 추가`

### Task 9: 공유 캘린더 화면

**Files:**
- Create: `App/Features/Calendar/{MainTabView,CalendarView,MonthGridView,DayListView,EventEditorView,EventChip}.swift`

**Interfaces:**
- Consumes: `SyncStore`, `CalendarLogic.monthGrid/events(on:)`, `ReminderOption`(일정별 알림은 Task 11의 `ReminderSettings`. 이 Task에서는 피커 자리만 두고 Task 11에서 연결한다)
- Produces: `MainTabView` 탭 2개 `달력`, `우리`. `EventChip(event:snapshot:)`: 색 표시 규칙(멤버 색 / 함께는 두 멤버 색을 반반 나누고 "함께" 텍스트), 주인 이니셜 텍스트를 함께 써서 색에만 기대지 않는다(NFR-03).

화면 규칙:
- 월 그리드: 칸마다 최대 3개 칩과 "+N". 도장은 `shortLabel` 칩으로 보여 준다. 오늘은 테두리로 표시한다. 좌우 스와이프나 화살표로 달을 넘긴다
- 날짜를 누르면 DayListView(그날 일정, `events(on:)` 순서), "+"를 누르면 EventEditorView
- EventEditorView: 제목, 주인(나 / 상대 닉네임 / 함께. 상대가 없으면 나·함께), 하루 종일 토글, 시작·종료 시각, 여러 날이면 종료일, 메모, "이 일정 알림"(Task 11). 저장과 삭제는 `isOnline == false`일 때 비활성화하고 `인터넷 연결 후 저장할 수 있어요`를 보여 준다
- 상단 배지: `partnerChangedIds`가 비어 있지 않으면 "상대가 바꾼 일정 N개" → 누르면 목록을 보여 주고 `clearPartnerChanges()`
- 당겨서 새로고침 → `refresh()`. scenePhase가 active가 되면 `refresh()` + `startRealtime()`, background가 되면 `stopRealtime()`

- [ ] **Step 1: 구현한다.**
- [ ] **Step 2: 빌드한다** → 성공
- [ ] **Step 3: 시뮬레이터 2대로 확인한다.** A가 "함께" 일정을 추가하면 B 화면에 몇 초 안에 나타나고 반반 색으로 보인다. B가 수정하면 A에 "상대가 바꾼 일정 1개" 배지가 뜬다. 네트워크를 끄면(Mac Wi-Fi 끄기) 저장 버튼이 비활성화되고 문구가 보이고, 기존 일정은 캐시로 보인다. 테스트 데이터를 지우고 잔여 0건을 보고한다.
- [ ] **Step 4: 커밋(승인 후).** `feat: 공유 캘린더 월간·일간·편집 화면 추가`

### Task 10: 근무 도장 모드와 근무 유형 관리

**Files:**
- Create: `App/Features/Calendar/{StampModeBar,ShiftTypeListView,ShiftTypeEditorView,ShiftEventActionsView}.swift`
- Modify: `App/Features/Calendar/CalendarView.swift`

**Interfaces:**
- Consumes: `CalendarLogic.stampAction`, `SyncStore` CRUD

화면 규칙:
- 달력 상단 "도장" 버튼 → 도장 모드. 하단 바에 근무 유형 칩들, "누구 근무"(기본: 유형의 owner, 바꿀 수 있음 SFT-05), "완료"
- 도장 모드에서 날짜를 탭하면 `stampAction`에 따라 insert/delete한다. 결과를 화면에 즉시 반영하고(낙관적), 실패하면 되돌리고 토스트를 띄운다. 달을 넘겨도 모드가 유지된다(SFT-04)
- 근무 유형 관리(우리 탭 → "근무 유형"): 목록, 추가, 수정(이름, 짧은 표시 1~3자, 색, 하루 종일/시작·종료 시각), 삭제(그 유형의 도장도 함께 삭제된다는 확인창)
- 도장 일정을 탭하면(일반 모드) ShiftEventActionsView: "날짜 바꾸기"(DatePicker → `day`만 update, SFT-07), "근무 유형 바꾸기", "삭제"

- [ ] **Step 1: 구현한다.**
- [ ] **Step 2: 빌드한다** → 성공
- [ ] **Step 3: 시뮬레이터로 확인한다.** 오전 당직 도장으로 3일 탭 → 다음 달로 넘겨 2일 탭 → 같은 날을 다시 탭하면 지워짐 → B 기기에 반영됨. 한 도장의 날짜를 바꾸면 B에서 날짜가 옮겨짐. 근무 유형 시간을 09:00으로 바꾸면 B의 일정 목록 시간이 바뀜. 잔여 데이터 0건.
- [ ] **Step 4: 커밋(승인 후).** `feat: 근무 도장 모드와 근무 유형 관리 추가`

### Task 11: 사람별 알림과 백그라운드 새로고침

**Files:**
- Create: `App/Backend/NotificationScheduler.swift`, `App/Features/Us/ReminderSettingsView.swift`
- Modify: `App/DateApp.swift`, `App/Features/Calendar/EventEditorView.swift`, `App/Features/Calendar/ShiftEventActionsView.swift`

**Interfaces:**
- Consumes: `ReminderPlanner.plan`, `SyncStore.onSnapshotChanged`
- Produces:
  - `enum ReminderSettings`: UserDefaults 키 `reminder.rules`(JSON `ReminderRules`), `reminder.overrides`(JSON `[String: ReminderOption]`). `static var rules`, `static func override(for: UUID) -> ReminderOption?`, `static func setOverride(_:for:)`, `static func pruneOverrides(keeping: Set<UUID>)`
  - `enum NotificationScheduler { static func requestAuthorization() async; static func reschedule(snapshot: CoupleSnapshot) async }`: 대기 중인 요청을 모두 지우고 plan 결과를 `UNCalendarNotificationTrigger`로 등록한다
  - BG 작업 `<prefix>.dateapp.refresh`: `SyncStore.refresh()` → reschedule → 다음 요청은 `earliestBeginDate = now + 4시간`

규칙:
- 첫 커플 진입 시 알림 권한을 요청한다
- 우리 탭 → "알림": 내 일정 / 상대 일정 / 함께 일정 / 상대 근무 도장마다 피커(없음, 당일 오전 8시, 정시, 10분 전, 1시간 전, 하루 전, 전날 밤 9시). 바꾸면 즉시 reschedule
- 일정 편집 화면과 도장 액션 화면의 "이 일정 알림": "기본 규칙 따르기" + 위 7개 옵션. 이 설정은 이 기기에만 저장된다고 안내 문구를 붙인다
- snapshot이 바뀔 때마다 reschedule하고 `pruneOverrides`를 실행한다

- [ ] **Step 1: 구현한다.**
- [ ] **Step 2: 빌드한다** → 성공
- [ ] **Step 3: 시뮬레이터에서 확인한다.** 규칙 partner=`정시`, 상대가 3분 뒤 시작하는 일정을 추가하면 내 기기에 정시 알림이 뜬다. 같은 일정의 상대 기기 override를 `없음`으로 하면 상대는 알림이 없고 나는 그대로 받는다. Xcode Debug → Simulate Background Fetch로 BG 작업이 refresh를 호출하는지 로그로 확인한다.
- [ ] **Step 4: 커밋(승인 후).** `feat: 사람별 알림 설정과 백그라운드 새로고침 추가`

### Task 12: 우리 탭(디데이·기념일·프로필·연결 끊기)과 위젯

**Files:**
- Create: `App/Features/Us/{UsView,AnniversaryEditorView,ProfileEditorView,DisconnectView}.swift`, `App/Backend/WidgetBridge.swift`
- Modify: `Widget/DateWidget.swift`

**Interfaces:**
- Consumes: `DDay`, `PaletteColor.available`, `SupabaseService.leaveCouple/deleteMyAccount`, `SyncStore.onSnapshotChanged`
- Produces:
  - `struct WidgetSnapshot: Codable { startDate: LocalDate?; upcoming: [Milestone] }`(Milestone에 Codable을 추가한다), `struct WidgetStyle: Codable { anniversary: String /* "start" 또는 Anniversary id */; background: String /* pink|sky|lemon|photo */; textColorHex: String; fontStyle: String /* rounded|serif */ }`
  - `enum WidgetBridge { static func write(snapshot: CoupleSnapshot); static func write(style: WidgetStyle, photo: UIImage?) }`

UsView 규칙:
- 상단에 큰 "D+N"(start 없으면 "사귄 날을 입력해 주세요")과 다가오는 기념일 5개(`DDay.upcoming`)
- 사귄 날 수정, 기념일 추가·삭제(제목, 날짜, 매년 반복)
- 내 프로필: 닉네임, 생일, 색(상대 색 제외)
- 초대 코드 보기(멤버 1명일 때), 근무 유형(Task 10), 알림(Task 11), 위젯 꾸미기
- 연결 끊기: 확인 화면 문구 `연결을 끊으면 내가 입력한 달력 일정만 남아요. 상대가 입력한 일정과 기념일은 사라져요.` → `leaveCouple()` → refresh
- 계정 삭제: 확인 문구 `계정을 삭제하면 내가 입력한 모든 일정이 사라지고 되돌릴 수 없어요.` → `deleteMyAccount()` → signOut → 로그인 화면

위젯 규칙 (Task 1 Step 8 결과에 따라):
- **A안(App Groups 가능)**: `WidgetBridge`가 `group.<prefix>.dateapp` UserDefaults의 `widget.snapshot`, `widget.style`과 컨테이너 파일 `widget-bg.jpg`(짧은 변 600px로 축소)를 쓰고 `WidgetCenter.shared.reloadAllTimelines()`를 호출한다. 위젯은 이 값을 읽는다
- **B안(불가)**: `AppIntentConfiguration`에 `startDate`(날짜), `title`(문자열, 기본 "우리"), `background`(pink/sky/lemon) 파라미터를 두고 위젯 편집 화면에서 직접 고른다. 사진 배경은 B안에서 제공하지 않는다고 `docs/setup.md`에 적는다
- 공통: 홈 화면 `.systemSmall`, `.systemMedium`(D+N, 제목, medium은 다음 기념일 1개 추가)과 잠금 화면 `.accessoryRectangular`, `.accessoryCircular`(D+N과 기념일 이름만, 꾸미기는 적용하지 않음). 타임라인은 오늘부터 7일치 자정 엔트리이고 policy는 `.atEnd`다
- 위젯 날짜 계산은 `DDay`를 그대로 쓴다

- [ ] **Step 1: 구현한다.**
- [ ] **Step 2: 빌드한다** → 성공
- [ ] **Step 3: 시뮬레이터로 확인한다.**
  - 연결 끊기: A·B 커플에서 A가 일정 2개(그중 하나는 B 도장 대신 찍기), B가 일정 2개, 기념일 1개를 만든다 → A가 연결 끊기 → A에는 자기가 입력한 2개만, B에는 B의 2개만 보이고 기념일은 없음, B에는 초대 코드가 생김
  - 위젯: 홈 화면에 small, medium 위젯과 잠금 화면 위젯을 추가해 D+N이 앱과 같은지 확인한다. 시뮬레이터 날짜를 다음 날로 바꾸면 숫자가 1 오르는지 확인한다(A안이면 배경 색·사진 바꾸기도 확인)
  - 계정 삭제 후 테스트 계정과 데이터 잔여 0건을 보고한다
- [ ] **Step 4: 커밋(승인 후).** `feat: 우리 탭과 디데이 위젯 추가`

### Task 13: 실기기 2대 최종 확인과 v1 정리

**Files:**
- Create: `docs/v1-device-checklist.md`

- [ ] **Step 1: 체크리스트 문서를 쓴다.** Task 8~12의 확인 항목을 실기기 기준으로 다시 묶는다. 항목마다 "누르는 순서 → 기대 문구"를 적는다.
- [ ] **Step 2: 사용자가 두 폰(본인, 여자친구)에 Xcode로 설치하고 체크리스트를 진행한다.** 상대 폰은 확인이 필요할 때만 설치한다는 결정을 따른다. 결과(통과·실패·미확인)를 문서에 적는다.
- [ ] **Step 3: 전체 테스트를 다시 돌린다.** `swift test --package-path Packages/DateCore` + `supabase test db` → 전부 PASS
- [ ] **Step 4: 커밋(승인 후).** `docs: v1 실기기 확인 결과 기록`
