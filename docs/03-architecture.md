# 시스템 아키텍처

상태: 승인 (2026-10-21) · 작성일: 2026-10-21 · 개정: 2026-10-21 (CloudKit → Supabase, 무료 개발 결정에 따름) · 관련 문서: [02-requirements.md](02-requirements.md), [04-data-model.md](04-data-model.md)

> ~~CloudKit 공유 DB + Core Data 미러링~~ 2026-10-21 폐기. 사유: 무료 Apple ID(Personal Team)에서는 iCloud/CloudKit과 Push Notifications capability를 쓸 수 없어서 비용 0원으로 시작하기로 하면서 바꿈.

## 1. 한 장 요약

```
 [남자친구 iPhone]                       [여자친구 iPhone]
 ┌───────────────────┐                  ┌───────────────────┐
 │ SwiftUI 앱         │                  │ SwiftUI 앱         │
 │  └ 로컬 캐시(JSON) │                  │  └ 로컬 캐시(JSON) │
 │ Widget Extension   │                  │ Widget Extension   │
 └─────────┬─────────┘                  └─────────┬─────────┘
           │ HTTPS (supabase-swift)               │
           ▼                                      ▼
 ┌────────────────────────────────────────────────────────┐
 │ Supabase (무료 플랜)                                     │
 │  Auth: 이메일 OTP 로그인                                 │
 │  Postgres: 테이블 + RLS(커플 멤버만 접근) + RPC 함수      │
 │  Storage: 비공개 버킷 photos/<couple_id>/...             │
 │  Realtime: 앱이 켜져 있을 때 변경 즉시 반영               │
 └────────────────────────────────────────────────────────┘
```

- 개발자가 직접 운영하는 서버 코드는 없다. Supabase가 DB, 로그인, 파일 저장을 제공하고, 권한은 Postgres RLS(행 단위 보안)와 DB 함수로 처리한다.
- 앱은 Supabase를 기준 데이터(source of truth)로 보고, 마지막으로 받은 데이터를 기기에 캐시해서 오프라인일 때 보여 준다.

## 2. 기술 선택

| 영역 | 선택 | 이유 | 고려한 대안 |
|---|---|---|---|
| UI | SwiftUI, iOS 17+ | 개발자의 Swift 경험. `@Observable` 사용 | UIKit, Flutter, RN |
| 백엔드 | **Supabase 무료 플랜** | 무료로 DB·로그인·파일 저장·실시간을 한 번에 제공한다. 공식 Swift SDK(`supabase-swift`)가 있다. Postgres라서 나중에 옮기기 쉽다 | Firebase(무료 플랜 Storage는 작성 시점 기준 Blaze 요금제가 필요하다고 알려짐, 확인 안 함), CloudKit(유료 계정 필요) |
| 로그인 | Supabase Auth 이메일 OTP(6자리 코드) | 무료이고 비밀번호가 없다 | Sign in with Apple(유료 계정 필요, 유료 전환 후 추가 검토) |
| 의존성 | `supabase-swift` 1개 | 그 외에는 Apple 프레임워크만 쓴다 | — |
| 로컬 캐시 | Codable 모델을 JSON 파일로 저장 | 데이터가 작다(일정 수백 건). 캐시는 화면 표시용일 뿐이라 DB 엔진이 필요 없다 | SwiftData(v2에서 데이터가 커지면 검토) |
| 알림 | `UserNotifications` 로컬 알림 | 무료 계정은 서버 푸시를 못 쓴다. 동기화한 상대 일정으로 내 기기에서 알림을 예약한다 | APNs(유료) |
| 백그라운드 동기화 | `BGAppRefreshTask` | 앱을 안 열어도 가끔 데이터를 받아 와서 알림을 다시 예약한다. 실행 시점은 iOS가 정한다 | — |
| 위젯 | WidgetKit | | |
| 추천 | 순수 Swift 함수(기기 안에서 계산) | 서버가 필요 없다 | LLM(v3 이후) |

### 2.1 무료 환경의 제약과 대응

| 제약 | 대응 |
|---|---|
| 무료 Apple ID로 설치한 앱은 7일 뒤 만료된다 | 개발자가 Mac에 연결해 다시 설치한다. 상대 폰은 확인이 필요할 때만 설치한다 **[결정]** |
| 서버 푸시 불가 | 앱이 켜져 있으면 Realtime으로 즉시 반영한다. 꺼져 있으면 백그라운드 새로고침과 앱 실행 시 동기화한다(4.2) |
| Universal Link(Associated Domains) 불가 | 초대는 **초대 코드**와 커스텀 URL 스킴 링크 `dateapp://join?code=XXXX`를 함께 보낸다(4.1) **[제안]**. 카카오톡이 커스텀 스킴을 링크로 인식하지 않으면 코드를 붙여넣는다 |
| App Groups 사용 가능 여부 **미확인** | 개발 첫날 Xcode에서 확인한다. 안 되면 위젯은 위젯 설정(AppIntent) 화면에서 시작일을 직접 고르는 방식으로 대체한다 |
| Supabase 무료: DB 500MB, Storage 1GB, 월 전송량 약 5GB(출처마다 다름), **7일 동안 요청이 없으면 프로젝트 일시정지** | 사진은 압축하고 썸네일을 캐시한다(REC-04). 1GB면 2048px 사진 약 2,000장. 둘이 매일 쓰면 정지되지 않는다. 정지되면 대시보드에서 복구한다 |
| Supabase 기본 메일 발송은 시간당 발송 수 제한이 매우 낮다 | 2명이면 충분하다. 공개 출시 때 외부 SMTP를 붙인다 |
| 2026-10-30부터 무료 프로젝트의 Data API에 변경이 있다는 3자 보도 **미확인** | 프로젝트를 만들 때 Supabase 공지를 확인한다 |

### 2.2 유료 전환 시 (공개 출시 단계)
- Apple Developer Program 가입 → TestFlight, App Store, 서버 푸시, Sign in with Apple, Universal Link.
- Supabase는 그대로 쓴다. 사용자가 늘면 Pro 플랜을 검토한다.
- 서버 푸시는 Supabase Edge Function + APNs로 추가한다.

## 3. 앱 구성

```
DateApp/                     (Xcode 프로젝트, 이름 미정)
├─ App/                      앱 진입점, 루트 탭, URL 스킴 처리
├─ Backend/                  Supabase 클라이언트, 저장소(Repository), 캐시, 동기화
├─ Features/
│   ├─ Auth/                 이메일 OTP 로그인
│   ├─ Couple/               온보딩, 초대 코드, 프로필·색, 연결 끊기·삭제
│   ├─ Calendar/             월간 달력, 일정 편집, 도장 모드
│   ├─ DDay/                 기념일 계산, 위젯 꾸미기
│   ├─ Records/   (v2)
│   ├─ Stats/     (v2)
│   └─ Recommend/ (v3)
├─ Shared/                   색 토큰, 공용 뷰, 날짜 유틸 (위젯과 공유)
└─ Widget/
```

폴더 구조는 시작점이다. 기능이 작을 때는 더 합쳐도 된다. 탭은 v1 기준으로 달력 / 우리(디데이·프로필·설정) 2개다.

## 4. 핵심 흐름

### 4.1 로그인, 커플 만들기, 초대
1. 이메일을 입력하면 6자리 코드가 오고, 코드를 넣으면 로그인된다. 세션은 Keychain에 저장된다(SDK 기본 동작).
2. 첫 화면은 "커플 만들기"와 "초대 받았어요" 두 버튼이다.
3. **커플 만들기**: RPC `create_couple(start_date, nickname, color)`를 호출한다. 커플, 내 멤버 행, 기본 근무 유형 2개, 초대 코드 1개를 한 트랜잭션에서 만든다. 혼자서도 모든 v1 기능을 쓸 수 있다(CPL-04a).
4. 초대 보내기: 공유 시트로 "초대 코드 XXXX-XXXX / dateapp://join?code=XXXXXXXX" 텍스트를 보낸다.
5. **초대 받았어요**(또는 링크 열기): 코드를 넣으면 RPC `peek_invite(code)`를 호출한다.
   - 코드가 없거나, 만료됐거나, 이미 2명이면 → "접근할 수 없는 링크입니다." (CPL-04c)
   - 내 커플이 이미 있으면 → "기존에 생성된 기능이 비활성화됩니다. 입력했던 일정도 함께 사라져요." + [유지] / [삭제] (CPL-04b)
   - 그 외에는 상대가 쓴 색을 뺀 팔레트를 받아 내 색을 고른다(CPL-05a).
6. RPC `join_couple(code, nickname, color, discard_own)`를 호출한다. 이 함수가 한 트랜잭션에서 다음을 처리한다.
   - `discard_own`이 true이고 내가 내 커플의 유일한 멤버이면, 내 커플을 통째로 삭제한다. 그 커플의 초대 코드와 사진 파일 경로 목록도 함께 지운다. 파일 삭제는 앱이 이어서 Storage API로 한다.
   - 대상 커플의 멤버가 1명인지 다시 확인한다(동시 가입 방지, `for update` 잠금).
   - 멤버를 추가한다.
   - 대상 커플의 **초대 코드를 삭제한다**. 수락 즉시 링크가 닫힌다(CPL-04).
7. A가 [삭제]로 B 커플에 들어간 뒤 B가 A의 옛 코드를 열면, 코드가 이미 지워졌으므로 5번 첫 줄에 따라 "접근할 수 없는 링크입니다."가 나온다.

RPC는 `security definer`로 만들고, 함수 안에서 `auth.uid()`로 호출자를 확인한다. 초대 코드는 혼동되는 문자(0/O, 1/I)를 뺀 8자리 무작위 값이고, 만료는 7일이다 **[제안]**.

### 4.2 동기화와 알림
1. 쓰기: 화면에서 저장하면 Supabase에 바로 쓰고, 성공하면 캐시를 갱신한다. 오프라인이면 저장 버튼을 막고 "인터넷 연결 후 저장할 수 있어요"를 보여 준다. 보기는 캐시로 계속 가능하다 **[제안, v1]**.
2. 읽기: 앱 실행, 포그라운드 복귀, 당겨서 새로고침, `BGAppRefreshTask`, Realtime 변경 알림 때 **커플 데이터 전체**를 받아 캐시를 통째로 바꾼다. ~~`updated_at > 마지막 동기화 시각` 증분 동기화 + `deleted_at` 소프트 삭제~~ 2026-10-21 계획 단계에서 변경. 사유: v1 데이터는 수백 행이라 전체 동기화가 충분히 가볍고, 연결 끊기·합치기로 행이 다른 커플로 옮겨 가는 경우도 증분 방식보다 단순하게 맞출 수 있음. 일정이 수천 건을 넘으면 증분 방식으로 바꾼다.
3. 앱이 켜져 있는 동안에는 Realtime 채널(`couple_id` 필터)로 변경을 즉시 받는다.
4. 동기화가 끝날 때마다 앞으로 14일치 로컬 알림을 다시 예약한다(iOS는 앱당 64개까지 예약 가능). 알림 시각은 내 기기의 규칙(`reminder.rules`)과 일정별 예외(`reminder.overrides`)로 정한다. 그래서 같은 일정이어도 두 사람이 받는 알림이 다를 수 있다(CAL-06).
5. 한계: 상대 폰이 오래 앱을 열지 않고 백그라운드 새로고침도 돌지 않으면, 상대가 새로 넣은 일정의 알림은 다음 동기화까지 예약되지 않는다. 그래서 달력 첫 화면에 "새로 추가·변경된 상대 일정" 배지를 띄운다.
6. 충돌: 같은 행을 둘이 고치면 나중에 저장한 쪽이 이긴다(CAL-08).

### 4.3 위젯
- App Groups를 쓸 수 있으면: 앱이 위젯용 스냅샷(시작일, 다가오는 기념일, 꾸미기 설정, 배경 사진 파일)을 App Group에 쓰고 `WidgetCenter.shared.reloadAllTimelines()`를 호출한다.
- 앞으로 7일치 자정 엔트리를 타임라인에 미리 넣는다(DDY-07).
- 잠금 화면 위젯은 "D+N"과 기념일 이름만 보여 준다(DDY-05).

### 4.4 추천 (v3)
`Recommender`는 순수 함수다. 입력은 카테고리, 두 사람의 선호, 최근 기록, 필터, 제외 목록이고, 출력은 카테고리와 이유 목록이다. 규칙은 요구사항 2.7.1을 따른다. RNG를 주입받아 테스트에서 결과를 고정할 수 있다.

## 5. 보안

- 앱에는 Supabase **anon key만** 넣는다. anon key는 공개되어도 되는 키이고, 실제 보호는 RLS가 한다. **service_role key는 앱, 저장소, 문서 어디에도 넣지 않는다.**
- 모든 커플 데이터 테이블에 RLS를 켠다. 정책: `couple_id in (select couple_id from couple_members where user_id = auth.uid())`. 이 조건은 함수 `is_member(couple_id)`로 만들어 모든 정책에서 재사용한다.
- Storage 버킷 `photos`는 비공개다. 경로 첫 폴더가 `couple_id`이고, 정책은 위와 같은 멤버 확인을 쓴다. 사진은 서명된 URL(유효 1시간)로 받는다.
- 초대 코드 조회와 가입은 RPC로만 한다. `invites` 테이블은 직접 select할 수 없다(코드 목록 노출 방지).
- 계정 삭제(CPL-07): RPC `delete_my_account()`. 내 멤버 행을 지우고, 내가 마지막 멤버이면 커플 전체를 지운 뒤 `auth.users`에서 나를 삭제한다. 사진 파일은 함수가 돌려준 경로 목록으로 앱이 지운다.
- 키 관리: Supabase URL과 anon key는 git에서 제외한 `Secrets.xcconfig`에 두고 빌드 설정으로 주입한다. 저장소에는 `Secrets.example.xcconfig`만 올린다.

## 6. 테스트 전략

| 대상 | 방법 |
|---|---|
| 디데이·기념일 계산, 추천 점수, 통계 집계, 도장 토글 | XCTest 단위 테스트(순수 함수) |
| RLS·RPC(가입, 합치기, 코드 닫기, 삭제) | Supabase CLI로 로컬 DB를 띄우고 SQL 테스트(pgTAP)를 돌린다. 사용자 2~3명을 만들어 "남의 커플 데이터를 못 읽는지"를 확인한다 |
| 두 기기 동기화 | 개발 중에는 시뮬레이터 2개에 서로 다른 계정으로 로그인해서 확인한다(무료 환경에서는 푸시를 안 쓰므로 시뮬레이터로 충분). 최종 확인은 실기기 2대로 한다 |
| 위젯 | Xcode 프리뷰 + 실기기 홈 화면 |

## 7. 개발 환경
- 문서 작성은 Windows에서 했고, 빌드·실행은 Mac + Xcode + 무료 Apple ID(Personal Team)로 한다.
- Supabase 프로젝트 1개(무료). 로컬 개발에는 Supabase CLI + Docker를 쓴다(선택).
- DB 스키마는 `supabase/migrations/*.sql`로 저장소에서 관리한다.
