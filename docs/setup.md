# Mac 준비 절차

달콤은 SwiftUI 앱(DateApp)과 위젯 확장(DateWidget), 로컬 Swift 패키지(DateCore)로 이루어진다. Xcode 프로젝트 파일은 저장소에 없고, `project.yml`을 XcodeGen으로 돌려 만든다. 서명은 무료 Apple ID(Personal Team)로 한다.

## 정해진 값

| 항목 | 값 |
|---|---|
| 앱 번들 ID | `com.sunwoong.dalcom` |
| 위젯 번들 ID | `com.sunwoong.dalcom.widget` |
| 앱 그룹 | `group.com.sunwoong.dalcom` (쓸 수 있을 때만) |
| 백그라운드 작업 ID | `com.sunwoong.dalcom.refresh` |
| 스킴 / 타깃 | `DateApp`, 위젯 타깃 `DateWidget` |
| URL 스킴 | `dateapp` |
| 표시 이름 | 달콤 |
| 최소 iOS | 17.0 |

## 1. 도구 설치

Xcode 16 이상을 App Store에서 설치하고 한 번 실행해 추가 구성요소 설치를 마친다. 그다음 Homebrew로 XcodeGen을 설치한다. Supabase CLI는 전역 설치하지 않고 Windows와 Mac 모두 `npx supabase@<버전>`으로 실행한다(고정 버전: [버전 기록 대기]). 그래서 Node.js(npx)가 필요하다. 로컬 Supabase를 돌리려면 Docker Desktop도 필요하다.

```sh
xcodebuild -version        # Xcode 16 이상인지 확인
brew install xcodegen
docker --version
```

## 2. 저장소 받기와 비밀값 파일

```sh
git clone https://github.com/sunwoong-dev/dalcom.git date
cd date
git switch feat/v1-core
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig`를 열어 Supabase 프로젝트의 URL과 anon 키를 넣는다. 이 파일은 `.gitignore`에 들어 있어 커밋되지 않는다. service_role 키는 앱에 절대 넣지 않는다.

xcconfig에서는 `//`가 주석으로 읽히기 때문에 URL은 `https:/$()/abcd.supabase.co`처럼 `$()`로 끊어 적는다. 빌드되면 이 값이 Info.plist의 `SupabaseURL`, `SupabaseAnonKey` 키로 들어간다.

Personal Team ID를 알면 같은 파일의 `DEVELOPMENT_TEAM`에 적어 둔다. 그러면 `xcodegen generate`를 다시 돌려도 Team 선택이 풀리지 않는다. 모르면 비워 두고 Xcode에서 매번 고른다.

`Secrets.xcconfig`가 없으면 `xcodegen generate`가 설정 파일을 찾지 못해 실패하므로 이 복사를 먼저 해야 한다.

## 3. 프로젝트 만들기와 빌드

```sh
xcodegen generate
open DateApp.xcodeproj
```

`project.yml`을 고칠 때마다 `xcodegen generate`를 다시 돌린다. 생성되는 `DateApp.xcodeproj`와 `App/DateApp.entitlements`, `Widget/DateWidget.entitlements`는 `project.yml`에서 다시 만들어지는 파일이다.

DateCore 로직 테스트는 시뮬레이터 없이 돌린다.

```sh
swift test --package-path Packages/DateCore
```

## 4. 실기기에 설치하기

1. Xcode > Settings > Accounts에서 무료 Apple ID로 로그인한다.
2. 프로젝트의 DateApp, DateWidget 두 타깃 모두 Signing & Capabilities에서 Team을 Personal Team으로 고른다.
3. iPhone을 케이블로 연결하고 스킴 `DateApp`, 대상 기기를 그 iPhone으로 골라 실행한다.
4. 처음 설치하면 iPhone의 설정 > 일반 > VPN 및 기기 관리에서 개발자 앱을 신뢰한다. iOS 16 이상은 설정 > 개인정보 보호 및 보안 > 개발자 모드도 켜야 한다.

## 5. 7일마다 다시 설치하기

무료 Apple ID로 서명한 앱은 설치 후 7일이 지나면 실행되지 않는다. 데이터는 서버에 있으므로 다시 설치해도 잃지 않는다. 다시 설치하는 방법은 4번과 같다. Mac에 iPhone을 연결하고 Xcode에서 실행 버튼을 누르면 서명이 새로 발급되어 7일이 다시 시작된다. 상대방 폰은 꼭 필요할 때만 같은 방법으로 설치한다.

## Mac에서 아직 확인 안 함

아래 단계는 Windows에서 골격을 만들 때 실행하지 못했다. Mac에서 처음 열 때 순서대로 확인하고 결과를 이 절에 적는다.

### 1단계: 환경 확인 (미확인)

```sh
xcodebuild -version
brew --version
docker --version
```

Xcode가 16보다 낮으면 진행하지 말고 macOS 버전과 Mac 모델을 기록한다.

### 4단계: 개발 도구 설치 (미확인)

```sh
brew install xcodegen
```

Supabase CLI는 설치하지 않고 `npx supabase@[버전 기록 대기] --version`으로 실행되는지만 확인한다.

### 7단계: 빌드 (미확인)

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodegen generate
xcodebuild -scheme DateApp -destination 'generic/platform=iOS Simulator' build
```

`** BUILD SUCCEEDED **`가 나와야 한다. `project.yml`, Info.plist, Asset Catalog, String Catalog는 손으로 쓴 것이라 이 빌드가 첫 검증이다.

### 8단계: 무료 서명과 App Groups 확인 (미확인)

4번 절차대로 Personal Team을 고르고 실기기에 실행해 본다. 결과에 따라 위젯 방식을 정한다.

- A안: 서명이 성공하면 App Groups를 쓴다. 앱이 App Group에 스냅샷을 쓰고 위젯이 읽는다(Task 12 A).
- B안: "Personal development teams ... do not support the App Groups capability" 오류가 나면 `project.yml`의 두 타깃에서 `entitlements` 블록을 지우고 `xcodegen generate`를 다시 돌린다. 위젯은 위젯 편집 화면에서 시작일 등을 직접 고르는 방식으로 간다(Task 12 B). B안에서는 사진 배경을 제공하지 않는다.

확인 결과: [Mac 확인 대기]
