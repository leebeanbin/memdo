# App Store 개인정보 답변 (Privacy Nutrition Label 초안)

> 처리방침 원문: [../privacy/index.html](../privacy/index.html) (공개 URL:
> https://leebeanbin.github.io/memdo/privacy/)
> 근거 정책 문서: [개인정보·동의·AI 정책](./06-privacy-consent-ai-policy.md)
> Privacy Manifest: [`apps/ios/Memdo/Memdo/PrivacyInfo.xcprivacy`](../apps/ios/Memdo/Memdo/PrivacyInfo.xcprivacy)

이 문서는 App Store Connect의 "App Privacy" 질문지에 실제로 입력할 답변을 실제 코드 기준으로
미리 정리한 초안이다. 최종 제출은 App Store Connect 웹 UI에서 이 표를 그대로 옮기며 진행한다
(Epic N의 TestFlight/제출 런북 범위). 이 표 자체가 제출물은 아니다 — 실제 App Store Connect
화면에서의 선택이 최종 사실이다.

## 추적(Tracking) 여부

**아니오.** `ASIdentifierManager`/`AppTrackingTransparency`/`AdSupport`/IDFA 관련 API를 앱 코드
전체(메인 앱, 위젯, 공유 확장)에서 사용하지 않음을 확인했다(코드 grep으로 검증, 2026-08-25).
광고 SDK나 제3자 분석/트래킹 SDK도 포함하지 않는다.

## 수집하는 데이터 유형

| Apple 카테고리 | 세부 유형 | 사용자 신원과 연결됨 | 수집 목적 | 근거 |
|---|---|:---:|---|---|
| Contact Info | Email Address | 예 | 계정 인증 및 식별 | Apple/Google/GitHub OAuth 로그인 — `MemdoApp.swift` |
| Identifiers | User ID | 예 | 계정 식별, 데이터 소유권 | Supabase `auth.users.id` |
| User Content | Other User Content (일정 제목·시간·메모) | 예 | 핵심 일정 관리 기능 | `todos` 테이블, `ScheduleAPI.swift` |
| Health & Fitness | Fitness | 예 | 운동 기록 기능(사용자 직접 입력, HealthKit 읽기 아님) | `WorkoutLog`, `workout-logs` 함수 — HealthKit entitlement는 현재 비활성 |
| Other Data | 뉴스 관심 카테고리 | 예 | 뉴스 브리핑 기사 선별(요약은 기기 내 처리, 서버 미전송) | `BriefingFeed.swift` |
| Other Data | OpenRouter API 키 | 예 | 클라우드 AI 기능 실행 시 사용자 대신 OpenRouter 호출 | `agent-key` 함수 — 서버 저장, 원문 키는 클라이언트에 재노출되지 않음 |

## 수집하지 않는 데이터 유형 (명시적으로 아니오로 답변)

- **Location**: 위치 정보 API를 사용하지 않음
- **Financial Info**: 결제/카드 정보 없음(StoreKit 결제 도입 시 재검토 필요 — 현재 미도입)
- **Contacts**: 주소록 접근 없음
- **Browsing History**: 없음
- **Search History**: 없음
- **Purchases**: 없음
- **Usage Data**: 제3자 분석 SDK 없음. 서버 구조화 로그(`_shared/http.ts`의 `logRequest`)는 있으나
  사용자 식별 목적의 분석용이 아니라 운영 디버깅용 요청 로그이며 앱스토어의 "Usage Data" 정의
  범위 밖으로 판단 — App Store Connect 제출 시 재확인
- **Sensitive Info**: 없음
- **Diagnostics**: 현재 미해당. **v1.0 Epic M(MetricKit) 배포 후 "Crash Data"/"Performance Data"로
  갱신 필요** — 이 문서는 Epic M 배포 시점에 반드시 업데이트한다(지금은 아직 배포 전이므로
  포함하지 않음, 실제로 없는 것을 있다고 미리 적지 않기 위함)

## 데이터가 앱 기능에 연결되는지 여부

수집된 모든 데이터는 App Functionality(앱 기능 제공) 목적으로만 사용되며, 광고·서드파티 분석·
데이터 브로커에게 판매되지 않는다.

## 삭제 관련 답변

계정 삭제 요청 시 위 데이터가 실제로 삭제되는 흐름은 v1.0 Epic L에서 구현한다 — 그 전까지는 이
문서의 "App Store Connect 제출은 Epic L 완료 후" 원칙을 따른다(§10 `06-privacy-consent-ai-policy.md`와
동일 원칙: 공개 출시 전 전문 검토 승인 필요).

## 갱신 이력

- 2026-08-25: 최초 작성 (v1.0 Epic K), 실제 코드 감사 기준
