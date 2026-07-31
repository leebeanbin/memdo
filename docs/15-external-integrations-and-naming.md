# 외부 API 통합 방식과 네이밍

> 개인정보 범위: [개인정보·동의·AI 정책](./06-privacy-consent-ai-policy.md)  
> 실행 파이프라인: [데이터 파이프라인](./17-data-pipeline.md)  
> 코드 규칙: [엔지니어링 규칙](./16-engineering-and-commit-rules.md)

## 1. 통합 대상

| 기능 | 초기 공급자 | 실행 위치 |
|---|---|---|
| AI 계획·요약 | OpenAI Responses API | 서버 |
| Push | APNs | 서버 |
| Apple Calendar | EventKit | iOS |
| 뉴스 | OpenAI Responses API `web_search` | 서버 |
| 인증 | Sign in with Apple + Supabase Auth | iOS·서버 |

MCP는 초기 내부 앱 통합에 사용하지 않는다. 다른 AI 클라이언트에 Memdo 기능을 공개할 필요가 생길 때 추가한다.

## 2. 경계 구조

외부 공급자 이름을 제품 도메인에 퍼뜨리지 않는다.

```text
Domain Use Case
    ↓
Port
    ↓
Provider Adapter
    ↓
External SDK / HTTP API
```

예:

```text
GeneratePlanDraft
    ↓
PlanningModel
    ↓
OpenAIPlanningModel
    ↓
OpenAI Responses API
```

한 구현만 있는 포트는 무조건 만들지 않는다. 다만 외부 제공자, 시스템 프레임워크, 테스트가 필요한 시간·네트워크 경계에는 좁은 포트를 둔다.

## 3. 정규 네이밍

### 도메인 작업

동사 + 명사:

```text
CreateTodo
UpdateTodo
CompleteTodo
GeneratePlanDraft
CommitPlanDraft
GenerateDailyBriefing
SyncCalendarWindow
SendPushNotification
```

### 포트

기능을 표현하고 공급자 이름을 넣지 않는다.

```text
PlanningModel
NewsSource
PushSender
CalendarGateway
TokenVault
Clock
```

피할 이름:

```text
AIService
APIManager
Helper
CommonService
ExternalClient
DataProcessor
```

### 어댑터

공급자 + 기능:

```text
OpenAIPlanningModel
APNsPushSender
EventKitCalendarGateway
SupabaseTokenVault
<ProviderName>NewsSource
```

### 외부 식별자

```text
provider
provider_account_id
provider_resource_id
provider_request_id
```

`external_id` 하나에 서로 다른 의미를 섞지 않는다.

## 4. 환경 변수

대문자 `제품_공급자_목적` 형식:

```text
MYDAY_OPENAI_API_KEY
MYDAY_OPENAI_MODEL
MYDAY_APNS_KEY_ID
MYDAY_APNS_TEAM_ID
MYDAY_APNS_BUNDLE_ID
MYDAY_APNS_PRIVATE_KEY
MYDAY_NEWS_PROVIDER
MYDAY_SUPABASE_URL
MYDAY_SUPABASE_SERVICE_ROLE_KEY
```

클라이언트에 포함할 수 있는 공개 설정과 서버 비밀을 분리한다. `SERVICE_ROLE_KEY`, OpenAI 키, APNs 개인 키는 iOS 빌드 설정에 넣지 않는다.

## 5. OpenAI 통합

### 입력

- 현재 사용자 요청
- 사용자가 허용한 일정 필드
- 날짜와 타임존
- 출력 JSON Schema

### 출력

- `PlanDraft`
- 최대 5개 Todo 제안
- 저장되지 않은 임시 ID
- 각 제안 이유
- 충돌 경고

### 호출 규칙

- 서버에서만 호출
- 명시적인 JSON Schema 출력
- 15초 타임아웃
- 읽기·초안 생성은 네트워크 오류에 최대 2회 재시도
- commit은 OpenAI를 다시 호출하지 않음
- 응답 원문은 기본 저장하지 않음
- `provider_request_id`, 지연, 토큰 사용량, 성공 여부만 운영 메타데이터로 기록

### 모델 이름

코드 여러 곳에 모델 문자열을 쓰지 않는다.

```text
MYDAY_OPENAI_MODEL
```

단 하나의 서버 설정에서 읽고 Agent 실행 기록에는 실제 사용 모델을 남긴다.

MVP 값:

```text
MYDAY_OPENAI_MODEL=gpt-5.6-luna
```

## 6. 뉴스 통합

MVP 공급자는 OpenAI Responses API의 `web_search`다.

```text
MYDAY_NEWS_PROVIDER=openai_web_search
```

별도 뉴스 API 키는 사용하지 않는다. `OpenAIWebSearchNewsSource`가 아래 `NewsSource` 계약으로 결과를 정규화한다.

입력:

```text
queries
language
country
publishedAfter
limit
cursor
```

정규 출력:

```text
provider
providerArticleId
canonicalUrl
title
sourceName
publishedAt
snippet
language
```

파이프라인:

```text
검색 → URL 정규화 → 중복 제거 → 게시 시각 검증
→ 관심도 계산 → 상위 후보만 AI 요약 → 브리핑 저장
```

공급자 원문 응답을 장기 저장하지 않는다. 라이선스상 허용된 필드만 저장하고 원문 링크를 항상 제공한다.

품질·비용 규칙:

- 출처 URL, 매체명, 게시 시각 중 하나라도 검증할 수 없으면 제외
- 검색 후보 10개 이하, 사용자 브리핑 3~5개
- 같은 정규 관심사 쿼리는 30분 재사용
- 월 뉴스 호출 예산의 80%에서 생성 빈도를 하루 1회로 제한
- 100%에서 새 브리핑 생성을 중지하고 마지막 성공 브리핑을 표시
- 유료 검색 비용이나 출처 품질이 목표를 넘을 때만 정식 뉴스 API 또는 허용 RSS로 교체

## 7. EventKit 통합

EventKit은 iOS 내부 어댑터다.

```text
CalendarGateway
└── EventKitCalendarGateway
```

접근 범위:

- `busy_only`
- `title_and_time`
- `full_details`

서버에 전송할 때 사용자의 AI 동의 범위보다 넓은 정보를 보내지 않는다. 외부 이벤트는 다음 키로 연결한다.

```text
provider = apple_eventkit
provider_calendar_id
provider_resource_id
provider_last_modified_at
```

## 8. APNs 통합

도메인은 “푸시를 보낸다”가 아니라 “알림 전달 작업을 요청한다”.

```text
NotificationRequest
→ integration_jobs
→ APNsPushSender
→ delivery_attempts
```

APNs 응답:

- 성공: provider request ID 기록
- 영구 실패 토큰: device token 비활성화
- 일시 실패: 지수 백오프 재시도

일정·하루 요약은 로컬 알림이 기본이며 APNs는 서버 변경과 복구 신호에 사용한다.

## 9. 공통 오류 코드

공급자 오류를 앱에 그대로 노출하지 않는다.

```text
INTEGRATION_UNAUTHORIZED
INTEGRATION_RATE_LIMITED
INTEGRATION_TIMEOUT
INTEGRATION_UNAVAILABLE
INTEGRATION_INVALID_RESPONSE
INTEGRATION_CONSENT_REQUIRED
INTEGRATION_CONFIGURATION_ERROR
```

서버 로그에는 공급자 세부 오류를 남기되 앱 응답은 정규 오류 코드와 재시도 가능 여부만 반환한다.

## 10. 타임아웃과 재시도

| 통합 | 타임아웃 | 자동 재시도 |
|---|---:|---:|
| OpenAI 초안 | 15초 | 최대 2회 |
| 뉴스 검색 | 8초 | 최대 2회 |
| APNs | 5초 | 최대 3회 |
| Supabase 내부 요청 | 3초 | 최대 1회 |

재시도:

- 지수 백오프 + jitter
- 429와 5xx 및 네트워크 타임아웃만
- 검증 오류, 동의 오류, 인증 영구 실패는 재시도하지 않음
- 쓰기는 idempotency key가 있을 때만 자동 재시도

50명 규모에는 별도 circuit breaker 라이브러리를 추가하지 않는다. 5분간 연속 실패 횟수를 모니터링하고 작업을 다음 실행 시점으로 미룬다.

## 11. Webhook 규칙

Webhook을 제공하는 공급자를 연결할 경우:

- 서명 검증 후 처리
- `provider_event_id` unique 제약
- 수신 원문은 최소 기간만 보관
- 2xx를 빠르게 반환하고 실제 처리는 작업 큐로 전달
- 순서가 뒤바뀌어도 `provider_updated_at`으로 최신 상태만 적용

## 12. 공급자 교체 조건

어댑터 교체를 검토하는 기준:

- 이용약관이 제품 요구와 충돌
- 월 비용이 정한 예산 초과
- 7일 p95 지연 또는 오류율 목표 초과
- 필요한 국가·언어·출처 범위 부족

추측으로 두 공급자를 동시에 구현하지 않는다.

## 13. Google Calendar와 외부 AI

Google OAuth, 증분 동기화, 출처 인덱싱, Memdo Remote MCP, 승인 Universal Link의 상세 구조는 [Integration Hub](./21-integration-hub-google-calendar-mcp.md)를 정답으로 사용한다.
