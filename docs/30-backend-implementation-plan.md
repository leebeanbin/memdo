# 백엔드 구현 실행 계획

상태: 구현 시작 기준선  
기준 규모: 내부 파일럿 50명  
목표: 로그인한 사용자가 iOS에서 만든 일정을 안전하게 저장·조회·동기화하는 첫 운영 경로 완성

## 1. 고정 기술

```text
Runtime: Supabase Edge Runtime (Deno-compatible)
Language: TypeScript 5.x
Database: Supabase PostgreSQL
Auth: Supabase Auth
Validation: zod
Scheduler: Supabase Cron
Queue: Supabase Queues (pgmq)
Vector: pgvector in Supabase PostgreSQL
Ephemeral state: Upstash Redis REST, AI·MCP 경로만
AI: OpenAI Responses API
Local AI: llama.cpp server, development/self-host only
Observability: OpenTelemetry-shaped events → Grafana Cloud, Sentry/MetricKit on iOS
```

Kafka·RabbitMQ, 외부 vector DB, materialized view, 라우팅 프레임워크는 추가하지 않는다. pgmq와 pgvector는 같은 PostgreSQL 안에서 사용하고 Redis는 원본 저장소가 아닌 만료 가능한 AI·MCP 상태에만 사용한다. MCP는 외부 진입점이며 DB에 직접 연결하지 않는다. 로컬 개발은 Docker와 저장소에 고정한 Supabase CLI를 사용한다.

데이터 접근은 SQL migration을 schema 원본으로 하고 사용자 RLS 경로는 Supabase client를 사용한다. Drizzle ORM은 trusted worker에서 복잡한 typed SQL이 실제로 필요해질 때만 추가하며 migration 권한은 갖지 않는다.

## 2. 인증 결정

사용자가 요청한 Google·GitHub 로그인을 제공하고 iOS 심사 대응을 위해 배포 전 동등한 개인정보 보호 로그인 수단을 추가한다. 계정 없는 신규 진입은 제공하지 않는다.

```text
Google / GitHub 로그인
→ Supabase Auth user 생성
→ public.users와 user_preferences 1:1 생성
→ 같은 user-scoped RLS 경로로 sync
```

- 앱은 provider access token이나 service-role key를 저장하지 않는다.
- 서버 소유자는 request body의 `userId`가 아니라 검증된 JWT의 `sub`로 결정한다.
- 같은 이메일이라는 이유만으로 계정을 자동 병합하지 않는다. 명시적 identity linking만 허용한다.
- Google Calendar 연결 OAuth는 Google 로그인과 별도 동의·토큰 수명주기를 갖는다.

## 3. 구현 원칙

1. OpenAPI의 이름과 필드를 먼저 따른다.
2. 모든 사용자 데이터 테이블에 RLS를 활성화한다.
3. RLS는 `(select auth.uid()) = user_id`를 사용하고 `user_id`를 인덱싱한다.
4. 모든 외래 키 열을 인덱싱하고 삭제 정책을 명시한다.
5. 일정 command는 `baseVersion`과 `Idempotency-Key`를 검증한다.
6. 멱등성 기록과 실제 mutation이 함께 성공해야 하는 command는 PostgreSQL 함수 한 트랜잭션으로 처리한다.
7. 외부 HTTP 호출은 DB 트랜잭션 안에서 수행하지 않는다.
8. 목록은 `(sort_value, id)` cursor를 사용하고 OFFSET을 쓰지 않는다.
9. 50명 단계에는 측정되지 않은 캐시와 인덱스를 추가하지 않는다.
10. UI Domain, API DTO, DB row를 같은 타입으로 사용하지 않고 경계 mapper로 변환한다.
11. 인덱스는 실제 query shape와 EXPLAIN을 동반하고, 전송 최적화는 projection·delta·ETag·압축·batch로 별도 관리한다.
12. 모든 route/job은 request 또는 operation ID, duration, result, retryability를 구조화 event로 남긴다.
13. 사용자 문구는 iOS String Catalog, API·DB enum은 안정 영문 code를 사용한다.

## 4. 저장소 목표 구조

```text
supabase/
  config.toml
  migrations/
  functions/
    _shared/
      auth.ts
      errors.ts
      request.ts
      response.ts
      telemetry.ts
    health/
    days/
    todos/
    sync/
  tests/
    database/
    functions/
package.json
deno.json
.github/workflows/backend-ci.yml
```

`_shared`에는 실제로 반복되는 인증·오류·request ID·telemetry 처리만 둔다. Repository interface, DI container, 범용 router는 필요가 생기기 전에는 만들지 않는다.

## 5. 단계별 구현

### B0. 로컬 기반과 계약 잠금

산출물:

- Supabase CLI 버전 고정과 `supabase init`
- local config와 example env 이름
- OpenAPI parse/lint
- TypeScript format·typecheck·test
- `supabase db reset` CI
- secret scan

완료 조건:

> 새 개발자가 비밀값 없이 로컬 DB를 재생성하고 health function 테스트를 실행할 수 있다.

### B1. 인증·사용자·기본 설정

DB:

- `users`
- `user_preferences`
- 최소 enum과 `updated_at` 처리
- RLS policy와 cross-user 차단 테스트

앱·서버:

- Google, GitHub, Apple Supabase Auth 설정
- 로그인 callback과 세션 복원
- 로그인 후 profile/preferences upsert
- 로그아웃 시 서버 cache 제거, 로컬 전용 데이터 보존

완료 조건:

> 세 공급자로 로그인한 사용자가 자기 profile만 읽을 수 있고 다른 사용자의 UUID를 요청해도 DB가 거부한다.

### B2. UI 계약 수정과 첫 일정 vertical slice

서버·DB:

- 현재 `users`, `user_calendars`, `todos` migration을 forward migration으로 보완
- `GET /days/{date}`, `GET /calendars`, `GET/POST /todos`
- 오늘 조회 query와 동일한 복합·부분 인덱스, RLS cross-user test
- 목록 DTO는 화면에 필요한 필드만 반환하고 provider raw data는 제외

iOS:

- `TodoResponseDTO`, `Schedule`, `LocalScheduleRecord`, mapper 분리
- `reminder: String`을 typed offset으로, `location: String`을 구조화 값으로 교체
- Task는 시작·종료를 선택 사항으로 바꾸고 `timeBucket`을 명시적으로 표현
- 2026-07 fixture 날짜와 한국어 enum raw value 제거
- `URLSession` client로 캘린더·일정 조회/생성 연결

관찰·성능:

- `todos.list`, `todos.create`, `days.get` route event
- duration, status class, response bytes, returned rows 기록
- 대표 오늘 조회 EXPLAIN과 p95 50ms 목표 확인

완료 조건:

> iPhone 15 시뮬레이터에서 실제 날짜의 Event와 Task를 생성하고 재실행 후 다시 조회하며, 앱·API·DB의 알림과 장소 값이 손실 없이 왕복한다.

### B3. 일정 command와 캘린더 관리

- `GET/PATCH/DELETE /todos/{id}`, `/status`, `/reschedule`
- 캘린더 생성·수정·숨김
- `baseVersion`, `Idempotency-Key`, soft delete와 원자적 재예약 RPC
- 상세 시트의 수정·완료·다른 날짜 이동·삭제를 실제 command에 연결
- stale version 409, 같은 idempotency key 재전송, 재예약 중 실패 rollback 테스트

완료 조건:

> UI의 모든 일정 상세 action이 빈 closure 없이 동작하고 중복·동시 요청에도 한 번만 일관되게 반영된다.

### B4. 오프라인 sync와 Widget snapshot

- SwiftData outbox와 `pending/synced/conflict` 상태
- `/sync`의 mutation별 결과와 `(updatedAt,id)` delta cursor
- tombstone 최소 DTO, 최대 push 100/pull 200 배치
- App Group snapshot 원자 교체와 Widget 딥링크
- sync batch size/conflict/bytes와 snapshot freshness 지표

완료 조건:

> 네트워크를 끄고 생성·수정한 뒤 재연결하면 서버와 수렴하고, 앱·홈 위젯·잠금화면 위젯의 다음 일정과 개수가 일치한다.

### B5. 반복 일정

- `schedule_rules`와 Todo occurrence unique 제약
- daily/weekday/weekly/biweekly/monthly/yearly preset을 지원 RRULE subset으로 정규화
- pgmq `refresh_recurrence_window` 작업과 30일 rolling window
- 사용자 수정 instance 예외 보존, 규칙 변경·비활성화 transaction
- 서울/로스앤젤레스 DST, 월말, 중복 실행 테스트

완료 조건:

> UI preset마다 예상 occurrence가 한 번만 생성되고 단일 일정 수정이 전체 규칙을 의도 없이 바꾸지 않는다.

### B6. 설정·알림·하루 요약

- `user_preferences`, `devices`, `daily_reviews`, `review_responses`
- 요약/계획 알림 시간과 요일 동기화
- 완료·부분·건너뜀·내일·다른 날짜 transaction
- `GET /daily-reviews/{date}`와 오늘/7일/30일 사실 기반 집계
- 로컬 알림 거부, timezone 변경, 중복 응답 테스트

완료 조건:

> 설정 화면의 모든 값이 재실행 후 유지되고 미완료 일정 응답이 Todo 상태와 과거 요약에 같은 결과로 나타난다.

### B7. 직접·Agent 공용 검색

- `pg_trgm` 제목 인덱스와 사용자·날짜·상태 선필터
- 제목·메모·장소 검색, source/calendar/status/period 필터
- 최소 `TodoSearchResultDTO`, cursor, 최대 50개
- 원문 검색어 미로깅, query p95와 0-result 비율만 기록
- 의미 검색 요구가 반복될 때만 pgvector embedding 실험

완료 조건:

> 캘린더 검색 UI와 Agent `search_todos`가 같은 결과 집합과 권한 경계를 사용하고 대표 검색 p95가 200ms 이하다.

### B8. Google Calendar

- 로그인 OAuth와 분리된 최소 scope 동의
- token vault, `data_connections`, `calendar_sources`, external event mirror
- incremental sync token, webhook 신호, pgmq sync 작업
- UI sourceProvider/calendarLabel/ownership 필터 연결
- read-only 먼저, 별도 재동의 후 proposal 기반 쓰기

완료 조건:

> 연결·증분 동기화·재인증·철회가 동작하고 Google 일정이 Memdo Todo로 위장되지 않는다.

### B9. 관심사 브리핑

- briefing keywords, article URL dedupe, daily briefing/items
- pgmq `generate_daily_briefing`, 날짜당 unique와 retry
- 매체·게시 시각·원문 URL이 있는 3~5개만 저장
- 동일 정규 키워드 결과 재사용, 최종 후보만 LLM 요약
- ETag와 최소 briefing DTO, 생성 지연·기사 수·token 비용 지표

완료 조건:

> 사용자가 정한 키워드와 시간으로 하루 한 번 생성되고 실패 시 불완전한 브리핑 대신 이전 결과를 유지한다.

### B10. Agent·LLM Gateway·의미 검색

- consent records, plan drafts, agent runs/actions, change proposals
- OpenAI Responses adapter와 llama.cpp local adapter
- typed tool schema와 structured output 검증
- pgvector는 동의한 일정·노트의 선택적 embedding에만 사용
- Upstash Redis는 Agent/MCP rate limit과 짧은 실행 lock에만 사용
- 승인 전 쓰기 금지, prompt 원문 기본 미저장, 모델/지연/token/eval 기록

완료 조건:

> 두 model adapter가 같은 평가 fixture를 통과하고 사용자가 승인하지 않으면 어떤 Todo도 변경되지 않는다.

### B11. Slack

- 실제 지원 범위를 `chat.postMessage`, `chat.scheduleMessage`와 `/memdo add`로 제한
- workspace/channel 최소 scope와 허용 채널
- message proposal 승인, Slack timestamp 기반 멱등성
- 외부 호출 전후 짧은 transaction과 실패 보상

완료 조건:

> 승인된 메시지만 한 번 전송되며 연결 해제 뒤에는 token과 예약 작업을 사용할 수 없다.

### B12. Memdo MCP

- Streamable HTTP MCP Worker와 OAuth
- `search_todos`, `get_day`, `create_change_proposal`, `get_operation` 최소 도구
- 도구는 Memdo API만 호출하고 DB·provider token에 접근하지 않음
- iOS Agent와 같은 command/query/consent/proposal 경로 사용
- tool schema contract test, per-client/user rate limit, 감사 event

완료 조건:

> Codex 같은 외부 client가 일정을 읽고 승인 링크를 만들 수 있지만 승인 전 직접 쓰기는 할 수 없다.

### B13. 운영·글로벌화·출시

- Grafana dashboard/alert, Sentry/MetricKit, synthetic health
- backup/restore 훈련, secret rotation, data export/delete
- `ko-KR`, `en-US`, timezone/DST, Dynamic Type 실제 기기 검증
- 공개 출시 전 Supabase Pro, 개인정보·약관·App Review 점검

완료 조건:

> staging 장애·복구 훈련과 개인정보 삭제 증거가 있고 기능별 SLO와 alert owner가 지정된다.

## 6. 현재 물리 schema와 다음 migration

`memdo-backend`의 첫 migration에는 아래만 존재한다.

```text
users
user_calendars
todos
```

따라서 제품 ERD 전체가 구현됐다고 표시하지 않는다. B2 forward migration은 현재 화면이 실제로 사용하는 일정 조회 shape를 먼저 보완하고, `user_preferences`, `daily_plans`, 별도 idempotency record는 해당 command가 구현되는 단계에서 추가한다. 이미 커밋된 첫 migration을 수정하지 않는다.

필수 인덱스:

```text
todos(user_id, scheduled_date, start_at, sort_order, id) where deleted_at is null
todos(user_id, updated_at, id)
daily_plans(user_id, plan_date) unique
user_calendars(user_id, lower(name)) unique
user_calendars(user_id, is_visible, sort_order, id)
```

오늘 조회의 실제 인덱스에는 `sort_order`와 `deleted_at is null` 조건을 포함하며 이름은 [DB 성능 문서](./14-database-performance-and-operations.md)의 `todos_user_day_active_idx`를 그대로 사용한다.

추가 인덱스는 실제 `EXPLAIN (ANALYZE, BUFFERS)`와 문서의 p95 기준을 넘을 때만 도입한다.

## 7. 트랜잭션 배치

| Command | 같은 트랜잭션 | 트랜잭션 밖 |
|---|---|---|
| Todo 생성·수정·상태 변경 | version 조건 update, idempotency record, audit metadata | push·AI·Google 호출 |
| 하루 요약 완료 | Todo 상태, review response, review 진행도 | 다음 알림 예약 |
| 내일로 이동 | 원본 상태, 새 Todo, 연결 ID, review response | push |
| Agent 승인 | proposal 검증, Todo mutation, proposal applied | Responses API 실행 |
| 작업 처리 | pgmq message read/visibility 전환 또는 operation 상태 기록 | 외부 호출 후 ack/archive와 별도 결과 transaction |

기본 격리는 `READ COMMITTED`를 유지하고 충돌은 `version` 조건부 update로 판정한다.

## 8. 테스트 피라미드

PR마다 최소 증거:

```text
SQL: schema constraint + RLS cross-user test
Function: validation + auth + error mapping test
Contract: OpenAPI example/schema test
Integration: local Supabase create → read → update → conflict
iOS: API fake를 사용한 repository test
Smoke: staging health + authenticated day read
```

실제 Google, Slack, OpenAI 호출은 해당 단계의 adapter contract test와 staging smoke에서만 수행한다.

## 9. 커밋과 PR 순서

```text
chore(backend): initialize local supabase toolchain
feat(auth): add user profile schema and rls
test(auth): reject cross-user profile access
feat(todo): add core schedule schema and commands
feat(api): expose day and todo endpoints
feat(ios): sync schedules through memdo api
test(sync): cover idempotency and version conflicts
```

마이그레이션·관련 함수·RLS·테스트는 같은 기능 PR에 포함한다. 이미 공유된 migration은 수정하지 않고 새 forward-fix migration을 추가한다.

## 10. 현재 시작 순서

B0 저장소와 첫 일정 조회·생성 계약, B2의 날짜 조회 API·인덱스·계약 테스트는 구현되어 있다. 다음
작업은 아래 순서다.

1. B1 외부 Supabase project와 Google·GitHub OAuth 값을 연결하고 실제 로그인 증거 확보
2. B2 UI에 남은 2026-07 fixture 날짜를 Clock·사용자 timezone으로 교체
3. 구현된 B2 `GET /days/{date}`와 iOS DTO/mapper/client를 실제 인증 session에 연결
4. 원격 DB에서 실제 query의 EXPLAIN 저장. route bytes/latency event는 구현 완료
5. iPhone 15에서 create → relaunch → read 통합 검증
6. B3 일정 command로 이동

pgvector table, Redis wrapper, MCP server, Drizzle schema를 B2에서 미리 만들지 않는다. 각각 B7, B10, B12의 첫 실제 사용과 같은 PR에서 추가한다.
