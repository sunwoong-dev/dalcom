# 인수인계 (Windows → Mac)

갱신: 2026-10-23. 브랜치 `feat/v1-core`(main 37c7648에서 분기). 계획: `docs/superpowers/plans/2026-10-21-v1-couple-calendar.md`.

## 한눈에

| Task | 내용 | 상태 |
|---|---|---|
| 1 | 저장소·프로젝트 골격 | 파일 작성 완료. **Mac 단계(빌드·서명)는 미확인** |
| 2 | Supabase 스키마와 RLS | 완료 |
| 3 | 커플 만들기·초대·가입·합치기 RPC | 완료 |
| 4 | 연결 끊기·계정 삭제 RPC | 완료 |
| 5 | DateCore 모델·팔레트·초대 코드·디데이 | 완료 |
| 6 | DateCore 달력 로직·알림 계획 | 완료 |
| 최종 리뷰 | 1~6 전체 리뷰와 수정 | 완료 (마이그레이션 000004) |
| 7~13 | 앱 백엔드, 로그인, 달력, 도장, 알림, 우리 탭·위젯, 실기기 확인 | **미착수. Mac에서 진행** |

검증된 것(Windows): DateCore `swift test` 20/20(Docker `swift:6.0`, Linux), pgTAP 84/84(로컬 Supabase).
검증 안 된 것: Mac/Darwin Foundation 동작, Xcode 빌드, 서명, App Groups, 실기기 실행, 운영 Supabase에서의 `delete_my_account`.

## Mac에서 제일 먼저 할 일 (순서대로)

1. `docs/setup.md`의 1~3번을 따라 도구 설치, `Config/Secrets.xcconfig` 준비, `xcodegen generate`.
2. `swift test --package-path Packages/DateCore` → 20/20인지 확인. 시간대·날짜 테스트가 Linux와 다르게 나오면 테스트 값을 바꾸지 말고 구현 차이를 찾는다.
3. `xcodebuild -scheme DateApp -destination 'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`. 실패하면 `project.yml`, Info.plist, Asset Catalog, String Catalog를 고친다(손으로 쓴 파일이라 첫 검증이다).
4. 실기기에서 무료 서명과 App Groups가 되는지 확인한다. 결과에 따라 위젯 방식(A안/B안)이 정해진다. 결과는 `docs/setup.md` 끝 "확인 결과"에 적는다.
5. (선택) 서버 확인: Docker Desktop을 켜고 `npx supabase@2.121.0 start`, `npx supabase@2.121.0 migration up --local`, `npx supabase@2.121.0 test db` → 84/84.
6. 위가 끝나면 계획의 **Task 7**부터 이어간다. Task 7~13의 상세는 계획 파일에 있다.

## 이미 내린 결정 (다시 묻지 않는다)

- 번들 ID: 앱 `com.sunwoong.dalcom`, 위젯 `com.sunwoong.dalcom.widget`, 앱 그룹 `group.com.sunwoong.dalcom`, 백그라운드 작업 `com.sunwoong.dalcom.refresh`. 타깃 이름 `DateApp`, URL 스킴 `dateapp`, 표시 이름 `달콤`(임시).
- Supabase CLI는 `npx supabase@2.121.0`으로만 쓴다(Windows·Mac 동일 버전). brew는 xcodegen에만 쓴다.
- 서버: 커플 관련 여러 행 쓰기(가입·합치기·끊기·탈퇴)는 RPC 한 번으로 끝낸다. 일정 간 참조는 같은 커플 안으로만 허용하는 복합 외래 키(deferrable)다.
- 이벤트 날짜: PostgREST가 `updated_at`을 마이크로초 6자리 + `+00:00`으로 보낸다. `Event` 디코더가 소수초 0~6자리를 받는다(R6).
- 알림: 예약 범위는 오늘부터 14일(오늘 포함), 최대 64개. 기본값은 모든 분류가 "당일 오전 8시"(R7).
- 디데이: 시작일 당일이 D+1.
- 연결 끊기 규칙(R16, 사용자 결정 2026-10-22): 끊으면 각자 "자기가 입력했고 주인이 자기이거나 같이"인 일정만 갖는다. 주인이 상대인 일정은 누가 입력했든 지운다. 직접 추가한 기념일은 둘 다에게서 지운다. 근무 유형은 쓰는 것만 새 커플에 복사하고 기존 커플은 그대로 둔다(R15). 시작일은 남은 쪽이 유지한다.
- 최종 리뷰 결정 R18: `leave_couple()`은 **혼자일 때 `not_connected` 예외**를 낸다(이전에는 커플을 지우고 null 반환). 상대가 먼저 끊어서 화면이 갱신 안 된 상태에서 눌러도 내 데이터가 지워지면 안 되기 때문이다. 혼자 커플을 지우는 건 `delete_my_account()`가 직접 한다. **Task 12(연결 끊기 UI)는 `not_connected`를 받으면 서버 상태를 새로 읽어 화면을 바꿔야 한다.**
- `together` 일정에는 `owner_member_id`를 넣을 수 없다(CHECK `events_together_no_owner`). 앱은 "함께" 일정을 만들 때 주인을 비워 보낸다.

## 출시 전에 할 일 (미룬 항목)

- 초대 코드 무차별 대입 방지: `peek_invite`/`join_couple`에 호출 제한이 없다(코드 32^8, 초당 500회로도 코드 하나에 약 25일). 사용자별 시도 기록 테이블과 시간당 N회 제한을 추가한다. 운영 Supabase에서 이메일 확인이 켜져 있는지도 본다(로컬 `config.toml`은 꺼져 있음).
- `couples.id`/`created_by`를 멤버가 바꿀 수 있다 → 컬럼 단위 권한으로 좁힌다.
- 앱 밖(대시보드)에서 사용자를 지우면 `owner_kind='member'` CHECK 때문에 실패한다. 앱 경로(`delete_my_account`)는 영향 없다.
- DateCore: `DDay.upcoming`, `ReminderPlanner.plan`에 음수 `limit`을 넘기면 트랩이 난다(`prefix(max(limit, 0))`). `InviteCode.normalize`가 `code=XXXX&src=y`처럼 ASCII가 더 붙은 입력에서 nil이 된다.
- 테스트 공백: `join_race_full`이 순차 실행이다(동시성 미검증). 끊는 사람이 입력한 "함께" 일정이 옮겨지는 경우가 없다.
- 운영 Supabase에 마이그레이션을 올릴 때 `delete_my_account`가 `auth.users` 삭제 권한이 있는지 확인한다.

## 마이그레이션·테스트

- `supabase/migrations/20261021000001~4`: 스키마·RLS / 커플 RPC / 끊기·삭제 RPC / 하드닝.
- `supabase/tests/`: `schema_rls`, `couple_rpc`, `leave_rpc`, `hardening` (pgTAP, 합계 84개).
- DB 스키마나 RPC를 바꾸면 새 마이그레이션 파일을 추가하고(기존 파일은 고치지 않는다), 테스트를 먼저 실패시킨 뒤 통과시킨다.
