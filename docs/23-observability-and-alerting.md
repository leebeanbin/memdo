# 관찰 가능성·모니터링·알림

> 스택: [기술 스택 기준선](./22-technology-stack-baseline.md)  
> 데이터 파이프라인: [데이터 파이프라인](./17-data-pipeline.md)  
> 개인정보: [개인정보·동의·AI 정책](./06-privacy-consent-ai-policy.md)

## 1. 선택

```text
Backend metrics/logs/traces: Grafana Cloud Free
iOS crashes/performance: Sentry Developer Free
Supabase platform logs: Supabase Dashboard
Apple production diagnostics: MetricKit
Uptime: Grafana Synthetic Monitoring
```

Prometheus와 Grafana 서버를 직접 배포하지 않는다. Grafana Cloud의 Prometheus 호환 metrics, Loki, Tempo를 사용한다.

## 2. 전송 구조

```mermaid
flowchart LR
    IOS["iOS"] --> SENTRY["Sentry"]
    IOS --> METRICKIT["MetricKit"]
    EDGE["Supabase Edge Functions"] --> OTLP["Grafana Cloud OTLP"]
    MCP["Cloudflare MCP Worker"] --> OTLP
    SYN["Grafana Synthetic"] --> HEALTH["/health/live"]
    CRON["Scheduled health job"] --> DBMETRIC["DB app metrics"]
    DBMETRIC --> OTLP
```

서버리스 환경에서는 Grafana Alloy를 별도 운영하지 않고 OTLP/HTTP로 직접 전송한다. 유실 없는 telemetry가 필요할 정도로 규모가 커지면 collector를 추가한다.

## 3. 서비스 이름

```text
memdo-api
memdo-jobs
memdo-mcp
memdo-approval-web
memdo-ios
```

공통 resource attributes:

```text
service.name
service.version
deployment.environment
request.id
```

user ID, Todo 제목, 이메일을 metric label에 넣지 않는다.

## 4. RED metrics

모든 HTTP 서비스:

```text
http_server_requests_total
http_server_errors_total
http_server_duration_ms
```

label:

```text
service
environment
route_template
method
status_class
```

실제 URL, proposal ID, Todo ID를 label로 사용하지 않는다.

## 5. 도메인 metrics

```text
memdo_sync_mutations_total
memdo_sync_conflicts_total
memdo_sync_payload_bytes
memdo_http_response_bytes
memdo_queue_depth
memdo_queue_oldest_message_seconds
memdo_job_retries_total
memdo_job_failures_total
memdo_google_sync_failures_total
memdo_google_sync_token_resets_total
memdo_agent_runs_total
memdo_agent_failures_total
memdo_agent_duration_ms
memdo_vector_search_duration_ms
memdo_redis_errors_total
memdo_proposals_created_total
memdo_proposals_approved_total
memdo_notification_failures_total
memdo_backup_age_seconds
```

AI 비용:

```text
memdo_llm_input_tokens_total
memdo_llm_output_tokens_total
memdo_llm_requests_total
memdo_llm_cost_usd
```

사용자 ID별 metric은 만들지 않는다.

## 6. 로그

JSON 구조:

```text
timestamp
level
service
environment
event_name
request_id
job_id?
agent_run_id?
provider_request_id?
duration_ms?
error_code?
```

로그 금지:

- Todo 제목·메모
- 검색어
- AI 입력·출력 원문
- OAuth token
- device token
- authorization header
- 이메일

## 7. traces

span:

```text
HTTP request
DB query category
domain command
external API
job processing
```

DB SQL 원문과 bind parameter는 전송하지 않는다. 외부 API span에는 공급자, operation, status, duration만 둔다.

기본 sampling:

```text
성공 요청 10%
오류 요청 100%
Agent 요청 100%
```

50명 파일럿에서 무료 한도를 넘으면 성공 sampling부터 낮춘다.

## 8. iOS

Sentry:

- crash
- handled error
- 앱 시작 지연
- network breadcrumb에서 URL path template만

MetricKit:

- hang
- crash diagnostic
- CPU
- memory
- launch time

사용자 메시지와 일정 내용을 Sentry context에 첨부하지 않는다.

## 9. health endpoints

```text
GET /health/live
GET /health/ready
```

`live`:

- 프로세스 응답 여부
- 외부 API 호출 없음

`ready`:

- 필수 설정 존재
- 짧은 DB `select 1`
- OpenAI·Google은 확인하지 않음

응답은 민감 설정을 포함하지 않는다.

## 10. dashboards

### API

- request rate
- error rate
- p50/p95/p99
- route별 지연

### Pipeline

- pending jobs
- oldest pending
- retry와 permanent failure
- Google sync 상태

### AI

- 요청·실패
- 지연
- 도구 호출 수
- token
- proposal 승인률

### Mobile

- crash-free sessions
- launch
- hang
- API error

### Cost

- Supabase DB·egress 사용률
- Grafana ingestion
- Cloudflare Workers requests
- R2 storage
- OpenAI token 추정 비용

## 11. alerts

| 조건 | 심각도 | 전달 |
|---|---|---|
| 5분 error rate > 5% | warning | 이메일 |
| 5분 error rate > 20% | critical | 이메일·즉시 확인 |
| p95 > 2초 10분 | warning | 이메일 |
| oldest pending job > 5분 | warning | 이메일 |
| Google sync failure 3회 | warning | 이메일 |
| backup age > 36시간 | critical | 이메일 |
| health check 3회 연속 실패 | critical | 이메일 |
| OpenAI 일 예산 80% | warning | 이메일 |
| OpenAI 일 예산 100% | critical | AI 호출 차단 |

초기에는 PagerDuty를 추가하지 않는다.

## 12. 보존

- Grafana Free 한도 내 기본 보존
- Supabase Free 로그는 1일
- Sentry 원문 개인정보 미전송
- 자체 감사 로그는 DB 보존 정책

telemetry는 제품 데이터의 백업이 아니다.

## 13. 공급자 교체와 계측 계약

도메인 코드가 Grafana, Sentry, Supabase SDK를 직접 호출하지 않는다. 서버의 `_shared/telemetry.ts`와 iOS의 `TelemetryClient`만 공급자 SDK를 안다. 단, 구현이 하나인 동안 factory나 DI container는 만들지 않고 함수/initializer로 주입한다.

안정 계약:

```text
recordCounter(name, value, attributes)
recordDuration(name, milliseconds, attributes)
recordEvent(name, result, requestOrOperationId, attributes)
```

- 이름과 낮은 cardinality attribute는 Memdo가 소유한다.
- OTLP endpoint, sampling, environment, release는 환경 설정으로 바꾼다.
- dashboard는 route template, operation type, provider, result code만 사용한다.
- Grafana를 바꾸더라도 domain event 이름과 alert 의미는 유지한다.
- telemetry 전송 실패는 제품 요청을 실패시키지 않는다.

배포 단계별 최소 관찰:

| 단계 | 필수 관찰 |
|---|---|
| B2 일정 | rate/error/duration/response bytes/rows |
| B4 sync | mutation 수, payload bytes, lag, conflicts |
| B5 queue | depth, oldest age, retry, permanent failure |
| B7 search | p95, 0-result ratio, rows scanned/returned |
| B8 integrations | provider latency/error/token reset |
| B10 Agent | model, token, latency, tool, approval, vector/Redis error |
| B12 MCP | client class, tool, duration, rate limit, proposal result |

## 14. iOS Simulator 개발 로그 판별

다음 로그는 Memdo가 WebKit을 중복 링크한 오류가 아니라 iOS 26.5 Simulator 런타임의 접근성 번들 충돌로 분류한다.

```text
Class UIAccessibilityLoaderWebShared is implemented in both
WebKit.axbundle/WebKit and WebCore.axbundle/WebCore
```

판별 기준:

- 충돌 경로가 모두 `iOS 26.5.simruntime/.../System/Library/AccessibilityBundles` 아래다.
- Memdo 타깃에 `WebKit`, `WKWebView`, `UIWebView` 참조가 없다.
- 빌드·설치·실행이 성공하고 해당 한 줄 외 앱 크래시 또는 오류가 없다.

대응:

1. Apple 서명 런타임 안의 `WebKit.axbundle` 또는 `WebCore.axbundle`을 삭제·이름 변경하지 않는다.
2. `OS_ACTIVITY_MODE`로 전체 로그를 숨기지 않는다.
3. 앱 크래시가 없다면 개발 환경 경고로 격리하고, 새 Xcode 또는 iOS Simulator 런타임이 배포되면 재검증한다.
4. 실제 크래시가 동반되면 동일 재현 프로젝트와 진단 파일을 Feedback Assistant에 첨부한다.

근거: 동일 경고의 [Apple Developer Forums 사례](https://developer.apple.com/forums/thread/799951), [Xcode 26.6 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes?language=objc).

## 15. 장애 대응

```text
alert
→ dashboard
→ request/job/provider ID로 trace
→ Supabase 또는 Cloudflare 상태 확인
→ 기능 degrade
→ 복구
→ 24시간 내 짧은 incident note
```

degrade 예:

- OpenAI 장애: 직접 일정 기능 유지
- Google 장애: 마지막 sync 데이터와 stale 표시
- Grafana 장애: 제품 기능 유지
- Cloudflare 승인 웹 장애: 앱 내 승인 유지
