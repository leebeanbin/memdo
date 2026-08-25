# TestFlight 배포 런북 + 실기기 검증 매트릭스

> v1.0 실행 계획: [로드맵](./09-roadmap-and-backlog.md), [테스트·출시 기준](./08-test-and-release-plan.md)
> Epic L(계정 삭제/알림 cap), Epic M(MetricKit)이 이 런북이 다루는 실기기 검증 항목에 포함된다.

이 문서는 v1.0 Epic N — 최초 TestFlight 업로드를 **재현 가능하게 성공**시키는 것이 목표다.
이번 범위에서는 fastlane, GitHub Actions archive/upload, `match` 같은 별도 certificate
management, App Store Connect API key 기반 자동 배포를 **도입하지 않는다** — 수동 Xcode
Organizer 업로드가 실제로 몇 번 성공하고 나서, 반복 작업이 실제로 부담이 될 때 자동화를
결정한다(문서 맨 아래 "CI 자동화 decision gate" 참고).

## 0. 외부 전제 조건 — 이 문서가 코드로 해결할 수 없는 유일한 blocker

**Apple Developer Program 등록이 아직 되어 있지 않다.** `apps/ios/Memdo/Memdo.entitlements`의
HealthKit 항목이 "유료 Apple Developer Program 멤버십 필요"라는 주석과 함께 비활성화되어 있고,
`project.yml`에 `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE`이 전혀 설정되어 있지 않다 — 무료 Apple ID로
개인 기기 설치까지는 가능하지만, TestFlight 배포에는 유료 Program 등록이 **반드시** 필요하다.
이 등록은 사람이 Apple Developer 웹사이트에서 직접 해야 하는 외부 행정 절차이며, 이 코드베이스
어디에서도 대신할 수 없다. 아래 1~9단계는 이 등록이 완료된 이후를 전제로 한다.

## 1. App Store Connect 준비

1. Apple Developer Program 등록 완료 확인.
2. App Store Connect에서 새 앱 등록: Bundle ID `com.memdo.ios`, 이름/SKU/primary language 지정.
3. App Store Connect의 "App Privacy" 질문지에 [`34-app-store-privacy-answers.md`](./34-app-store-privacy-answers.md)의
   내용을 그대로 옮겨 입력(Epic K가 이미 실제 코드 기준으로 정리해 둠).
4. Privacy Policy URL에 `https://leebeanbin.github.io/memdo/privacy/` 입력(Epic K).

## 2. Bundle ID / Signing & Capabilities / Team 확인

1. Xcode에서 `apps/ios/Memdo/Memdo.xcodeproj` 열기(먼저 `xcodegen generate` 실행 — `project.yml`이
   실제 소스).
2. Memdo 타겟 → Signing & Capabilities:
   - Team을 등록된 Apple Developer Program 계정으로 설정(현재 `project.yml`에 없으므로 최초
     설정은 Xcode UI에서 직접 하거나, 이후 `project.yml`에 `DEVELOPMENT_TEAM`을 추가해 재생성).
   - "Automatically manage signing" 사용 권장(수동 프로비저닝 프로파일 관리는 이번 범위 밖).
3. MemdoWidget/MemdoShare 확장 타겟도 각각 같은 Team으로 서명되는지 확인 — App Group
   (`group.com.memdo.ios`) capability가 세 타겟 모두에 켜져 있어야 한다(이미 entitlements 파일에
   존재, Signing & Capabilities에서 실제 활성화 여부만 재확인).
4. HealthKit entitlement는 계속 비활성 상태로 둔다(v1.0 범위 밖 — 유료 계정이 생겼다고 자동으로
   켜지 않는다. 켜려면 별도 결정과 개인정보 정책 갱신이 필요하다).

## 3. Release 빌드 설정 확인

1. Scheme "Memdo" → Edit Scheme → Archive가 **Release** configuration을 쓰는지 확인(project.yml의
   `archive: config: Release`로 이미 맞게 설정돼 있음 — Xcode UI에서 재확인만).
2. `Memdo/Config.xcconfig`(gitignored, 로컬 전용)에 실제 프로덕션 Supabase URL/publishable key가
   들어 있는지 확인 — Debug 빌드용 값이 Release Archive에 섞여 들어가면 TestFlight 빌드가 로컬
   개발 서버를 가리키는 사고가 난다.
3. `apps/ios/Memdo/Memdo/PrivacyInfo.xcprivacy`(Epic K)가 Archive에도 포함되는지 -- 이미
   `project.yml`의 `sources:`로 자동 포함되므로 별도 조치 불필요, Organizer의 privacy report에서
   최종 확인.

## 4. 버전/빌드 번호 규칙

현재 `Info.plist`는 `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 1`을 하드코딩하고
있다(빌드 설정 치환이 아니라 리터럴 값) — 이번 범위에서는 이 방식을 유지하고, 자동 증가 규칙을
새로 만들지 않는다(그건 CI 자동화와 함께 올 일). 규칙:

- **`CFBundleShortVersionString`(마케팅 버전)**: App Store Connect에 노출되는 사용자용 버전.
  v1.0 개발 중에는 `1.0`으로 고정, 실제 공개 출시 시점에 맞춰 조정.
- **`CFBundleVersion`(빌드 번호)**: 같은 마케팅 버전 안에서 App Store Connect에 업로드할 때마다
  **반드시 이전 값보다 큰 정수**여야 한다(같은 값으로 재업로드하면 거부됨). 매 업로드 전
  `Info.plist`의 `CFBundleVersion`을 수동으로 1씩 올린다.

## 5. Archive → Organizer validate → App Store Connect upload

1. 실제 기기 연결 없이도 Archive 가능(디바이스 대상은 "Any iOS Device (arm64)" 선택).
2. Xcode → Product → Archive.
3. Archive 완료 후 자동으로 열리는 Organizer에서 새 Archive 선택 → **Validate App** 먼저 실행(실제
   업로드 전에 서명/entitlement/Info.plist 문제를 미리 잡는다).
4. Validate 통과 후 **Distribute App** → App Store Connect → Upload.
5. 업로드 완료까지 수 분~수십 분 소요 — App Store Connect의 "TestFlight" 탭에서 처리 상태 확인
   (Apple의 자동 정적 분석/서명 재검증이 끝나야 "Ready to Submit" 상태가 된다).

## 6. TestFlight internal testing 활성화

1. App Store Connect → TestFlight → 방금 업로드된 빌드가 처리 완료되면 나타남.
2. Internal Testing 그룹에 개발자 본인(Apple ID)을 추가 — 별도 심사 없이 즉시 설치 가능(Internal
   Testing은 App Review를 거치지 않는다).
3. TestFlight 앱에서 초대 수락 → 실기기에 설치 → 아래 §8 스모크 테스트 진행.
4. Closed/Expanded Beta로 확장할 때는 [`08-test-and-release-plan.md`](./08-test-and-release-plan.md#9-출시-검증-단계-release-validation-stages)의
   단계별 절차를 따른다 — External Testing 그룹은 최초 1회 App Review가 필요하다는 점이 Internal과
   다르다.

## 7. 흔한 업로드 실패와 복구 절차

| 증상 | 원인 | 복구 |
|---|---|---|
| "No signing certificate" | Team 미설정 또는 인증서 만료 | Signing & Capabilities에서 Team 재선택, Xcode가 자동으로 인증서 재발급 시도 |
| "Missing Info.plist key" | Privacy Manifest/권한 설명 문구 누락 | Epic K의 `PrivacyInfo.xcprivacy`와 `Info.plist`의 `NSXxxUsageDescription` 키 확인 |
| "The bundle version must be higher" | `CFBundleVersion`을 이전 업로드와 동일하게 둠 | §4 규칙대로 수동 증가 후 재-Archive |
| "Invalid Bundle. The app uses an SDK that is not public" | 베타 Xcode/SDK로 Archive함 | Epic M 참고 — 이 프로젝트는 production Xcode(현재 26.6)만 사용, 베타 SDK로 Archive 금지 |
| Validate는 통과했는데 Upload가 멈춤/타임아웃 | 네트워크 문제 또는 Apple 서버 지연 | 재시도. 반복 실패 시 Organizer 대신 `xcrun altool`/Transporter 앱으로 업로드 시도 |
| TestFlight에 빌드가 안 보임(업로드는 성공) | Apple 처리 지연(자동 분석) | 보통 수분~1시간, 계속 지연되면 App Store Connect의 빌드 상태 메시지 확인 |

## 8. 설치 후 실기기 스모크 테스트 (매 업로드마다 최소 실행)

- 앱 최초 실행 → 로그인 화면/게스트 진입 정상.
- 오늘 화면에 일정 표시.
- 알림 권한 요청 및 최소 1개 알림 예약 확인.
- Widget 추가 후 정상 표시.
- 강제 종료 후 재실행 시 데이터 유지.

## 9. 실기기 검증 매트릭스 (Internal Dogfooding / Closed Beta 기간 반복 실행)

시뮬레이터로는 확인할 수 없는 항목만 모았다 — Internal Dogfooding(1주)과 Closed Beta(2주) 동안
반복 실행한다.

| 영역 | 확인 항목 | 관련 Epic |
|---|---|---|
| OAuth | Apple/Google/GitHub 3개 provider 모두 실제 로그인 왕복 성공(`docs/auth-social-login.md`가 "실기기 왕복 재확인 기록 없음"으로 명시한 항목) | v0.9 이전부터 있던 기존 갭 |
| OAuth | Apple 로그인 후 `apple_oauth_tokens`에 refresh token이 실제로 저장되는지(백엔드 로그로 간접 확인) | Epic L |
| 계정 삭제 | 설정 → 계정 삭제 → 확인 다이얼로그 → 실제 삭제 → 로그아웃 상태로 전환 | Epic L |
| 계정 삭제 | Apple 계정으로 삭제 시 Apple ID 설정의 "Sign in with Apple" 연결 앱 목록에서 Memdo가 사라지는지 | Epic L |
| 알림 | 여러 일정을 등록해 알림 rolling window(7일·48개 cap)가 실제로 오래된/먼 알림을 정리하는지 | Epic L |
| 알림 | 알림 액션("완료") 탭 시 실제로 완료 처리되는지 | 기존 |
| 알림 | 기기 재부팅 후 예약된 알림이 유지되는지 | 기존 |
| 백그라운드 | 백그라운드에서 포그라운드 복귀 시 알림 reconciliation이 다시 도는지(scenePhase 활성화 훅) | Epic L |
| BYOK | OpenRouter API 키 연결 → 클라우드 Agent 실제 응답 확인 | 기존 |
| Widget/잠금화면 | 잠금화면 위젯 탭 → 인증 → 상세 화면 딥링크 | 기존 |
| 딥링크 | `memdo://` scheme 기반 알림 탭 라우팅 정상 동작 | 기존 |
| Crash 진단 | Xcode Organizer의 Crashes 탭에서 실제 crash가 symbolicate되어 나타나는지(§9.3, `08-test-and-release-plan.md`) — 강제 크래시 1회로 파이프라인 자체를 검증 | Epic M |
| Privacy Manifest | Archive 시 Xcode의 privacy report에서 경고 없음 | Epic K |
| Privacy Policy | `https://leebeanbin.github.io/memdo/privacy/`가 실기기 Safari에서 정상 로드 | Epic K |

## 10. CI 자동화 decision gate

fastlane/GitHub Actions 기반 자동 배포는 아래 조건이 모두 충족될 때 Go로 판단한다 — 그 전까지는
이 런북의 수동 절차를 유지한다:

- 이 런북대로 수동 업로드를 **2회 이상** 성공.
- signing/provisioning 절차가 매번 반복 가능하고 안정적임이 확인됨(인증서/프로파일 문제로
  막히는 경우가 없음).
- 반복 배포(예: Closed/Expanded Beta에서 주 2~3회 이상)가 실제로 개발 흐름에 부담이 됨.

지금 시점에는 배포 빈도가 낮을 것으로 예상되므로, fastlane 구축에 드는 시간보다 첫 업로드를
실제로 성공시키는 것이 훨씬 가치가 크다 — 이 gate를 만족하기 전까지 자동화를 미리 만들지 않는다.
