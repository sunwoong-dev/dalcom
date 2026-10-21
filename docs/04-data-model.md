# 데이터 모델 (테이블 명세)

상태: 승인 (2026-10-21) · 작성일: 2026-10-21 · 개정: 2026-10-21 (Core Data/CloudKit → Supabase Postgres) · 관련 문서: [02-requirements.md](02-requirements.md), [03-architecture.md](03-architecture.md)

> ~~Core Data 엔티티 + CloudKit 자동 미러링(`CD_` 레코드)~~ 2026-10-21 폐기. 사유: 무료 Apple ID에서 CloudKit을 쓸 수 없어서 Supabase로 바꿈(03 문서 참고).

## 0. 공통 규칙

- DB는 Supabase Postgres, 스키마는 `public`이다. 사용자 계정은 Supabase가 관리하는 `auth.users`를 참조한다.
- 모든 테이블은 `id uuid primary key default gen_random_uuid()`, `created_at timestamptz default now()`, `updated_at timestamptz default now()`(트리거로 자동 갱신)를 가진다. 아래 표에서는 생략한다.
- 커플 데이터 테이블에는 모두 `couple_id uuid not null references couples(id) on delete cascade`를 둔다. 아래 표에서는 **[C]** 로 표시한다.
  - 삭제는 실제 삭제다. ~~`deleted_at` 소프트 삭제 + 증분 동기화~~ 2026-10-21 변경. 사유: v1은 전체 동기화를 쓴다(03 §4.2).
- RLS: [C] 테이블은 모두 `is_member(couple_id)`일 때만 select/insert/update/delete를 허용한다(03 §5).
- 날짜만 있는 값은 `date`(기기 시간대 기준 그날)이고, 시각은 `time`, 순간은 `timestamptz`다.
- 열거형은 Postgres `text` + `check` 제약으로 둔다(마이그레이션이 쉬움).

## 1. 관계도

```
auth.users 1 ── 0..1 couple_members * ── 1 couples
                                           │
           ┌───────────┬───────────┬───────┼──────────┬────────────┐
           ▼           ▼           ▼       ▼          ▼            ▼
        invites    shift_types   events  anniversaries categories  date_records
                       │  1         ▲                    │  1        │ 1
                       └──── * ─────┘                    │           ├─ * photos
                                                         │           ├─ * expenses
             couple_members 1 ── * preferences * ── 1 ───┤           └─ * date_record_categories * ── 1 categories
             couple_members 1 ── * person_tags
```

## 2. 테이블

### couples (v1) — 커플 공간

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| start_date | date | null 허용 | 사귄 날. 이날이 D+1 |
| monthly_budget | integer | not null default 0, ≥ 0 | 월 데이트 예산(원). 0이면 미설정 (v2) |
| created_by | uuid | references auth.users on delete set null | 만든 사람 |

RLS: `is_member(id)`. insert는 RPC `create_couple`로만 한다.

### couple_members (v1) — 커플 구성원 겸 프로필

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| couple_id | uuid | not null references couples on delete cascade | |
| user_id | uuid | not null references auth.users on delete cascade, **unique** | 한 사람은 커플 하나에만 속한다 |
| role | text | not null check in ('owner','partner') | 만든 사람 / 들어온 사람 |
| nickname | text | not null, 1~20자 | |
| birthday | date | null 허용 | 생일 자동 기념일에 사용 |
| color | text | not null check in ('pink','sky','mint','lilac','peach','lemon') | 일정 색. CPL-05a |

제약:
- `unique (couple_id, color)`: 상대와 같은 색을 고를 수 없다.
- 커플당 최대 2명은 RPC `join_couple` 안에서 잠금(`for update`)을 걸고 검사한다.

RLS: 같은 커플 멤버끼리 select 가능. update는 자기 행(`user_id = auth.uid()`)만 가능. insert와 delete는 RPC로만 한다.

### invites (v1) — 초대 코드

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| couple_id | uuid | not null references couples on delete cascade, unique | 커플당 유효한 코드 1개 |
| code | text | not null unique, 8자 | 0/O/1/I 제외 대문자+숫자 |
| expires_at | timestamptz | not null default now() + 7 days | |

RLS: 직접 접근 전부 금지. `create_couple`, `regenerate_invite`, `peek_invite`, `join_couple` RPC만 쓴다. 상대가 가입하면 행을 삭제해 링크를 닫는다(CPL-04).

### shift_types (v1) [C] — 근무 도장 종류

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| owner_member_id | uuid | references couple_members on delete set null | 주로 쓰는 사람(도장 기본 주인) |
| name | text | not null | 예: 오전 당직 |
| short_label | text | not null, 1~3자 | 달력 칸 표시. 예: 오전 |
| color | text | not null | 팔레트 키 |
| all_day | boolean | not null default true | |
| start_time | time | null 허용 | all_day=false일 때 |
| end_time | time | null 허용 | |
| sort_order | smallint | not null default 0 | |

기본 행: `create_couple`이 "오전 당직/오전", "오후 당직/오후"를 시간 없이 만든다(SFT-02).

### events (v1) [C] — 일정과 근무 도장

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| owner_kind | text | not null check in ('member','together') | |
| owner_member_id | uuid | references couple_members on delete set null | owner_kind='member'일 때 필수(check) |
| created_by_member_id | uuid | references couple_members on delete set null | 입력한 사람 |
| shift_type_id | uuid | references shift_types on delete cascade, null 허용 | 근무 도장이면 설정 |
| title | text | null 허용 | 도장이면 null이고 shift_types.name을 표시한다. 일반 일정은 not null(check) |
| day | date | not null | 시작 날짜 |
| end_day | date | null 허용 | 여러 날 일정의 마지막 날 |
| all_day | boolean | not null default true | |
| start_time, end_time | time | null 허용 | |
| memo | text | null 허용 | |

규칙:
- 알림 설정은 이 테이블에 없다. 사람마다 다르게 정하므로 기기에만 저장한다(§4, 02 CAL-06).
- 도장 일정의 시간·색·이름은 매번 `shift_types`에서 읽는다. 유형을 고치면 이미 찍은 도장에도 반영된다.
- 당직 날짜 바꾸기(SFT-07)는 `day`만 update한다.
- 도장 중복 방지: 부분 유니크 인덱스 `unique (owner_member_id, shift_type_id, day) where shift_type_id is not null`. 도장 토글(SFT-03)은 행이 있으면 삭제하고, 없으면 insert한다.

인덱스: `(couple_id, day)`, `(couple_id, updated_at)`.

### anniversaries (v1) [C] — 직접 추가한 기념일

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| title | text | not null | |
| date | date | not null | |
| repeats_yearly | boolean | not null default true | |

100일 단위, 매년 기념일, 생일은 저장하지 않고 `couples.start_date`와 `couple_members.birthday`로 계산한다.

### categories (v1 시드, v2~v3 사용) [C] — 활동·음식 종류

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| kind | text | not null check in ('activity','food') | |
| name | text | not null | 예: 방탈출, 떡볶이 |
| emoji | text | null 허용 | |
| place | text | not null default 'any' check in ('any','indoor','outdoor') | |
| cost_level | smallint | not null default 2 check 1~3 | |
| seed_key | text | null 허용 | 기본 제공 항목 키(예: `activity.escape_room`). `unique (couple_id, seed_key)` |
| is_hidden | boolean | not null default false | |

시드: `create_couple`이 기본 목록을 넣는다. 목록 초안은 개발 착수 시 정한다(활동 약 30개, 음식 약 40개).

### preferences (v3) [C] — 좋아요·싫어요

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| member_id | uuid | not null references couple_members on delete cascade | |
| category_id | uuid | not null references categories on delete cascade | |
| value | smallint | not null check in (1,-1) | 상관없음이면 행 삭제(실제 삭제) |

`unique (member_id, category_id)`. update는 본인 행만 가능.

### person_tags (v3) [C] — 취미·특기

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| member_id | uuid | not null references couple_members on delete cascade | |
| kind | text | not null check in ('hobby','skill') | |
| text | text | not null, 1~20자 | |

### date_records (v2) [C] — 데이트 기록

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| day | date | not null | |
| title | text | null 허용 | |
| place_name | text | null 허용 | 직접 입력하는 글자. 검색·지도 없음 |
| memo | text | null 허용 | |
| rating | smallint | null 허용, check 1~5 | 커플 공용 별점 |
| created_by_member_id | uuid | references couple_members on delete set null | |
| event_id | uuid | references events on delete set null, null 허용 | "함께" 일정에서 만든 경우(REC-06) |

### date_record_categories (v2) [C] — 기록의 한 일·먹은 것 (다대다)

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| record_id | uuid | not null references date_records on delete cascade | |
| category_id | uuid | not null references categories on delete cascade | 활동/음식 구분은 categories.kind로 한다 |

`unique (record_id, category_id)`. 이 테이블은 소프트 삭제 대신 기록 저장 시 통째로 교체한다. 동기화는 부모 기록의 `updated_at`을 기준으로 한다.

### photos (v2) [C]

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| record_id | uuid | not null references date_records on delete cascade | |
| storage_path | text | not null | `photos/<couple_id>/<record_id>/<id>.jpg`, 긴 변 2048px |
| thumb_path | text | not null | 같은 위치의 `<id>_t.jpg`, 긴 변 400px |
| kind | text | not null check in ('together','member','food','other') | |
| subject_member_id | uuid | references couple_members on delete set null | kind='member'일 때 찍힌 사람 |
| uploaded_by_member_id | uuid | references couple_members on delete set null | |
| taken_at | timestamptz | null 허용 | EXIF 촬영 시각 |
| sort_order | smallint | not null default 0 | |

업로드 순서: Storage에 파일 2개를 올린 뒤 행을 insert한다. insert가 실패하면 올린 파일을 지운다.

### expenses (v2) [C]

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| record_id | uuid | not null references date_records on delete cascade | |
| amount | integer | not null check ≥ 0 | 원 단위 |
| kind | text | not null check in ('meal','cafe','activity','transport','gift','other') | |
| payer_kind | text | not null check in ('member','split','shared') | 한 사람 / 반반 / 공동 |
| payer_member_id | uuid | references couple_members on delete set null | payer_kind='member'일 때 |
| memo | text | null 허용 | |

통계의 월 집계는 `date_records.day`를 기준으로 한다.

## 3. RPC 함수 (security definer, 03 §4.1·§5)

| 함수 | 하는 일 |
|---|---|
| `is_member(couple_id) → bool` | RLS 공용 검사 |
| `create_couple(start_date, nickname, color) → couple_id` | 이미 커플이 있으면 에러. 커플, 멤버(owner), 기본 근무 유형, 카테고리 시드, 초대 코드를 만든다 |
| `regenerate_invite() → code` | 멤버가 1명일 때만 새 코드를 만든다(기존 코드 교체) |
| `peek_invite(code) → {status, taken_colors}` | status: 'ok' / 'invalid'(없음·만료·정원 참) / 'has_own_couple'. 아무것도 바꾸지 않는다 |
| `join_couple(code, nickname, color, discard_own) → couple_id` | 03 §4.1-6. 내 커플 삭제(옵션) → 정원 재확인 → 멤버 추가 → 초대 코드 삭제. 삭제된 내 커플의 사진 경로 목록을 돌려준다 |
| `leave_couple() → photo_paths[]` | 연결 끊기(CPL-06). 한 트랜잭션에서: ① 새 커플을 만들고 내 멤버 행을 옮긴다(시작일은 비움). ② `created_by_member_id = 나`인 events와, 그 일정이 쓰는 shift_types를 새 커플로 옮긴다. 남은 사람도 쓰는 근무 유형이면 복사한다. ③ 기존 커플의 date_records(사진·비용·카테고리 연결 포함)와 anniversaries를 삭제한다. ④ 남은 사람에게 owner를 주고 새 초대 코드를 만든다. ⑤ 두 커플 모두 기본 카테고리 시드를 유지한다. 삭제한 사진 경로 목록을 돌려준다. 혼자일 때는 커플 전체를 삭제한다 |
| `delete_my_account() → photo_paths[]` | CPL-07. `leave_couple` 처리 후 `auth.users`에서 자신을 삭제한다 |

## 4. 기기에만 저장하는 데이터

| 위치 | 키 | 내용 |
|---|---|---|
| Keychain | (SDK 관리) | Supabase 세션 |
| 앱 캐시 파일 | `cache.json` | 마지막으로 동기화한 커플 데이터, `last_synced_at` |
| 앱 UserDefaults | `reminder.rules` | `{ mine, partner, together, partnerShift }`. 값: `"none"`, `"day8"`(당일 08:00, 기본값), `"at"`, `"m10"`, `"m60"`, `"d1"`, `"eve21"` (CAL-06a) |
| 앱 UserDefaults | `reminder.overrides` | `{ "<event id>": 위와 같은 값 }`. 일정별 예외 (CAL-06b). 삭제된 일정의 키는 동기화 때 정리 |
| App Group UserDefaults (가능할 때) | `widget.style` | `{ anniversary, background: pink/sky/lemon/photo, textColor, fontStyle }` |
| 〃 | `widget.snapshot` | `{ startDate, upcoming: [{title, date}] }` |
| App Group 컨테이너 | `widget-bg.jpg` | 위젯 배경 사진 |

위젯 꾸미기 설정은 기기마다 따로 저장하고 서버에는 올리지 않는다(DDY-06).
