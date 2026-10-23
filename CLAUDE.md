# 달콤(dalcom) — 커플 캘린더 iPhone 앱

세션을 시작하면 먼저 `docs/HANDOFF.md`를 읽는다. 지금까지 한 일, 다음 단계, 이미 내린 결정이 거기 있다. 이미 적힌 내용은 사용자에게 다시 묻지 않는다.

## 구성

- `App/`, `Widget/`: SwiftUI 앱(DateApp)과 위젯(DateWidget). `project.yml`을 XcodeGen으로 돌려 `DateApp.xcodeproj`를 만든다(프로젝트 파일은 git에 없다).
- `Packages/DateCore/`: 앱과 위젯이 함께 쓰는 순수 Swift 로직. 시뮬레이터 없이 `swift test --package-path Packages/DateCore`로 테스트한다.
- `supabase/`: Postgres 스키마·RLS·RPC(마이그레이션)와 pgTAP 테스트. CLI는 전역 설치 없이 `npx supabase@2.121.0`으로 쓴다.
- `docs/01~04`: 승인된 명세(제품, 요구사항 ID CPL-xx, 아키텍처, 데이터 모델). `docs/setup.md`: Mac 준비 절차.
- `docs/superpowers/plans/2026-10-21-v1-couple-calendar.md`: 구현 계획(Task 1~13). 진행 상황은 `docs/HANDOFF.md`가 정본이다.

## 작업 규칙

- 한국어 반말로 짧게 답한다. 코드 주석은 한국어, 식별자와 파일명은 영어로 쓴다.
- 커밋 메시지는 `<type>: <한국어 요약>`(feat, fix, debug, refactor, docs, test, chore). 하나의 커밋에는 하나의 목적만 담는다.
- 로컬 커밋은 허용돼 있다. 푸시와 main 병합은 사용자에게 먼저 묻는다.
- 비밀값(`Config/Secrets.xcconfig`, anon key 외 모든 키)은 채팅에 적지도 출력하지도 않는다. service_role 키는 어디에도 쓰지 않는다.
- "완료"는 실제로 실행해서 확인한 뒤에만 쓴다. 확인 못 한 것은 "미확인"으로 적고 사용자가 무엇을 눌러야 하는지 말한다.
- 사용량이 넉넉하지 않다. 하위 에이전트로 구현을 나누지 말고 직접 구현하며, 리뷰는 전체가 끝난 뒤 한 번만 한다. 긴 대화는 새 세션으로 나눈다.
- 실행: 계획은 `superpowers:executing-plans` 방식으로 한 Task씩, 테스트를 먼저 쓰고 실패를 본 뒤 구현한다.
- 계획·명세가 바뀌면 지우지 않고 `~~삭제선~~` + 날짜·사유로 남긴다.
