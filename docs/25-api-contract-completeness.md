# API 계약 완성도와 공통 규칙

> 기계 판독 계약: [OpenAPI](./05-api-spec.yaml)  
> 외부 AI: [Integration Hub](./21-integration-hub-google-calendar-mcp.md)

## 1. 공개 API 영역

| 영역 | 상태 |
|---|---|
| Day·Todo·검색 | 정의 |
| Sync | 정의 |
| 반복 일정 | 정의 |
| 하루 요약 | 정의 |
| Preferences·Theme | 정의 |
| Interests·Briefing | 정의 |
| AI draft·Agent runs | 정의 |
| Consent·data export/delete | 정의 |
| Devices·notification | 정의 |
| Google connection·calendar | 정의 |
| Change proposals | 정의 |
| Automations | 정의 |
| Health | 정의 |

## 2. 공통 URL

```text
Base: https://api.memdo.example/v1
MCP:  https://mcp.memdo.example/mcp
Web:  https://memdo.example
```

## 3. 인증

- 공개 health와 OAuth callback 외 Bearer JWT
- Supabase access token
- service-role key는 public API에서 금지
- MCP는 별도 OAuth access token

## 4. 오류

```json
{
  "error": {
    "code": "RESOURCE_VERSION_CONFLICT",
    "message": "일정이 다른 기기에서 변경되었습니다.",
    "retryable": false,
    "requestId": "uuid",
    "details": {}
  }
}
```

공통 상태:

```text
400 validation
401 unauthenticated
403 permission/consent
404 missing
409 state/version/idempotency conflict
422 domain rule
429 rate limit
500 internal
503 dependency unavailable
```

## 5. 멱등성

- POST command와 상태 변경에 `Idempotency-Key`
- 사용자·route·key 조합
- 24시간 보존
- 같은 key와 다른 body는 409
- 동일 요청은 원래 status와 body 재반환
- schedule rule, consent, automation, delete도 command이므로 동일 규칙 적용

## 6. pagination

- opaque cursor
- cursor 내부는 `(sort_value, id)`
- 기본 20
- 최대 200은 sync만
- 일반 목록 최대 50
- OFFSET 금지

## 7. rate limit

50명 파일럿 기본:

| 범위 | 제한 |
|---|---:|
| 일반 API | 사용자당 120/분 |
| 검색 | 사용자당 30/분 |
| AI | 사용자당 10/시간 |
| AI 계획 생성 | 사용자당 3/분 |
| OAuth 시작 | 사용자당 10/시간 |
| proposal 승인 | 사용자당 30/분 |
| MCP | client·user당 60/분 |

429는 `Retry-After`를 포함한다.

## 8. 요청 제한

```text
JSON body: 256KB
Todo title: 120자
Todo note: 2,000자
AI message: 2,000자
검색어: 100자
sync mutations: 100개
```

## 9. 버전

- major URL version `/v1`
- additive 변경은 같은 major
- 필드 제거·의미 변경은 `/v2`
- deprecated 응답 header와 문서 제공
- iOS 공개 버전이 사용하는 API는 최소 6개월 유지

## 10. request ID

- 클라이언트 `X-Request-ID` 선택
- 서버가 없으면 UUID 생성
- 응답 header에 반환
- 로그·trace·오류 body에 연결

## 11. 시간

- 날짜: `YYYY-MM-DD`
- timestamp: ISO 8601 offset 포함
- 사용자 timezone: IANA
- 서버 저장: `timestamptz`

## 12. MCP 계약

MCP tool schema는 OpenAPI에 섞지 않고 별도 MCP manifest/test fixture로 관리한다.

필수:

- tool name
- input JSON Schema
- structured output Schema
- approval policy
- 오류 코드
- 개인정보 scope
- example

## 13. 계약 검증

CI:

```text
YAML parse
OpenAPI lint
breaking change check
generated fixture validation
example response schema validation
MCP tool schema test
```

## 14. 인증 서비스 경계

Google·GitHub·Apple 로그인, provider callback, access-token refresh, logout은 Supabase Auth의 공개 계약을 그대로 사용하며 Memdo OpenAPI에 재정의하지 않는다.

Memdo API가 직접 소유하는 것은 다음이다.

```text
JWT 검증
프로필·preferences
device 등록
외부 connection
data export
account deletion orchestration
```

## 15. 동시성

- 일반 수정·상태 변경·삭제·재예약 request body 또는 query에 `baseVersion`
- 생성은 `baseVersion=0` 또는 생략 가능한 생성 전용 schema
- stale version은 `RESOURCE_VERSION_CONFLICT`
- 409 `details.currentResource`에는 현재 사용자가 읽을 수 있는 최신 표현
- 성공 응답에는 증가한 `version`

## 16. operationId 정책

MVP iOS client는 `URLSession` 기반의 작은 수동 client이므로 OpenAPI `operationId`를 코드 생성 전제 조건으로 두지 않는다. 코드 생성을 도입하는 ADR이 승인되면 모든 operation에 안정적인 `operationId`를 한 번에 추가하고 breaking-change 검사를 활성화한다. 누락을 계약 오류로 취급하지 않는다.
