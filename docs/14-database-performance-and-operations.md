# 데이터베이스 성능·운영 설계

> 근거 모델: [데이터 모델](./04-data-model.md)  
> API 조회 경로: [API 명세](./05-api-spec.yaml)  
> 파이프라인 작업: [데이터 파이프라인](./17-data-pipeline.md)  
> 규모 가정: 출시 초기 활성 사용자 50명

## 1. 결론

현재 규모에는 단일 PostgreSQL과 명시적인 복합·부분 인덱스로 충분하다. 파티셔닝, 읽기 복제본, Redis, 별도 메시지 브로커는 사용하지 않는다.

현재 ERD의 관계 방향은 적절하지만 다음이 보완되어야 한다.

- 모든 외래 키 조회용 인덱스
- 사용자별 날짜 조회용 복합 인덱스
- 동기화 커서용 인덱스
- 활성 데이터만 포함하는 부분 인덱스
- 반복 인스턴스 중복 방지 제약
- 하루 요약 응답 중복 방지 제약
- 외부 작업 큐와 멱등성 기록
- 소프트 삭제 데이터 정리 정책

## 2. 용량 가정

보수적으로 다음을 가정한다.

| 항목 | 사용자당 | 전체 50명 |
|---|---:|---:|
| Todo 생성 | 하루 20개 | 하루 1,000개 |
| Todo 연간 누적 | 연 7,300개 | 연 365,000개 |
| 하루 요약 | 하루 1개 | 연 18,250개 |
| 요약 응답 | 하루 10개 | 연 182,500개 |
| 동기화 기기 | 2대 | 최대 100대 |
| 브리핑 | 하루 1개 | 연 18,250개 |

이 정도는 PostgreSQL 단일 인스턴스에서 작은 데이터셋이다. 최적화 목표는 대규모 분산 처리가 아니라 잘못된 전체 테이블 스캔, 중복 기록, 외부 API 재시도를 예방하는 것이다.

## 3. 핵심 조회 경로

### Q1 오늘 화면

```sql
select *
from public.todos
where user_id = $1
  and scheduled_date = $2
  and deleted_at is null
order by start_at nulls last, sort_order, id;
```

인덱스:

```sql
create index todos_user_day_active_idx
on public.todos (user_id, scheduled_date, start_at, sort_order, id)
where deleted_at is null;
```

### Q2 하루 요약 대상

```sql
select *
from public.todos
where user_id = $1
  and scheduled_date = $2
  and status in ('planned', 'in_progress', 'partial')
  and deleted_at is null
order by start_at nulls last, sort_order, id;
```

인덱스:

```sql
create index todos_user_day_pending_review_idx
on public.todos (user_id, scheduled_date, start_at, sort_order, id)
where deleted_at is null
  and status in ('planned', 'in_progress', 'partial');
```

상태는 부분 인덱스 조건에 포함되므로 별도 단일 `status` 인덱스를 만들지 않는다.

### Q3 커서 동기화

```sql
select *
from public.todos
where user_id = $1
  and (updated_at, id) > ($2, $3)
order by updated_at, id
limit 200;
```

인덱스:

```sql
create index todos_user_sync_cursor_idx
on public.todos (user_id, updated_at, id);
```

OFFSET을 사용하지 않고 `(updated_at, id)` 키셋 커서를 사용한다.

### Q4 반복 인스턴스 조회

```sql
select *
from public.todos
where schedule_rule_id = $1
  and scheduled_date >= $2
  and deleted_at is null;
```

인덱스와 중복 제약:

```sql
create unique index todos_rule_occurrence_unique_idx
on public.todos (schedule_rule_id, scheduled_date)
where schedule_rule_id is not null
  and deleted_at is null;
```

### Q5 브리핑 조회

```sql
create unique index daily_briefings_user_date_uidx
on public.daily_briefings (user_id, briefing_date);

create index briefing_items_briefing_order_idx
on public.briefing_items (briefing_id, sort_order, id);
```

## 4. 외래 키 인덱스

PostgreSQL은 외래 키에 자동으로 인덱스를 만들지 않는다. 다음 컬럼은 전부 인덱스가 필요하다.

```text
todos.user_id
todos.daily_plan_id
todos.schedule_rule_id
reminders.todo_id
daily_reviews.user_id
review_responses.daily_review_id
review_responses.todo_id
briefing_items.briefing_id
briefing_items.article_id
agent_runs.user_id
agent_actions.agent_run_id
consent_records.user_id
integration_jobs.user_id
```

이미 복합 인덱스의 선두 컬럼인 외래 키에는 중복 단일 인덱스를 만들지 않는다.

## 5. 유일성과 데이터 무결성

```sql
alter table public.daily_plans
  add constraint daily_plans_user_date_key
  unique (user_id, plan_date);

alter table public.daily_reviews
  add constraint daily_reviews_user_date_key
  unique (user_id, review_date);

alter table public.review_responses
  add constraint review_responses_review_todo_key
  unique (daily_review_id, todo_id);

alter table public.todos
  add constraint todos_progress_check
  check (progress between 0 and 100);

alter table public.todos
  add constraint todos_time_order_check
  check (end_at is null or start_at is null or end_at > start_at);
```

앱 검증과 DB 제약을 모두 둔다. DB 제약은 동시 요청과 버그가 잘못된 데이터를 기록하는 마지막 방어선이다.

## 6. RLS 성능

모든 사용자 테이블에 `user_id` 인덱스를 확보하고 정책 함수는 한 번만 평가되도록 한다.

```sql
create policy todos_select_own
on public.todos for select
using ((select auth.uid()) = user_id);
```

복잡한 조직 권한은 없으므로 security-definer 권한 함수는 만들지 않는다.

## 7. 쓰기 성능

### 단일 사용자 동작

- Todo 하나의 생성·수정은 단일 행 쓰기다.
- 완료 응답과 `review_responses` 기록은 짧은 하나의 트랜잭션으로 묶는다.
- 트랜잭션 안에서 OpenAI, 뉴스, APNs 같은 HTTP 호출을 하지 않는다.

### 반복 일정 생성

- 30일분을 한 번에 다중 행 `INSERT`한다.
- `(schedule_rule_id, scheduled_date)` 충돌 시 `DO NOTHING`한다.
- 생성 작업은 최대 500행 배치로 제한한다.

### 사용자 설정

```sql
insert ... on conflict (user_id) do update
```

SELECT 후 INSERT/UPDATE로 나누지 않는다.

## 8. 인덱스 예산

쓰기마다 모든 인덱스도 갱신되므로 “혹시 필요할 것 같은” 인덱스는 만들지 않는다.

초기 `todos` 인덱스:

1. 기본 키
2. `todos_user_day_active_idx`
3. `todos_user_day_pending_review_idx`
4. `todos_user_sync_cursor_idx`
5. `todos_rule_occurrence_unique_idx`

실제 쿼리 없이 `title`, `emoji`, `color`, `source` 단일 인덱스는 만들지 않는다.

## 9. JSONB 사용 규칙

JSONB 허용:

- 외부 제공자의 원본 오류 세부정보
- Agent 도구 요청의 비민감 요약
- 공급자별 확장 메타데이터

정규 컬럼 유지:

- 상태
- 날짜와 시간
- 사용자 ID
- 외부 ID
- 작업 상태
- 재시도 횟수
- 동의 범위에서 자주 조회하는 값

조회 조건에 지속적으로 쓰이는 JSONB 필드는 정규 컬럼으로 승격한다.

## 10. 소프트 삭제와 보존

- Todo는 30일 소프트 삭제 후 물리 삭제한다.
- 물리 삭제는 하루 한 번 최대 1,000행씩 실행한다.
- 감사 로그는 별도 보존 정책을 따른다.
- 초기 규모에서는 테이블 파티셔닝을 하지 않는다.
- 1천만 행 또는 단일 테이블 20GB에 접근할 때 파티셔닝을 재검토한다.

## 11. 연결과 타임아웃

- Edge Function은 Supabase의 풀링 연결을 사용한다.
- 요청마다 장기 연결을 직접 만들지 않는다.
- API DB statement timeout: 3초
- 배치 작업 statement timeout: 15초
- 외부 HTTP 호출은 DB 트랜잭션 밖에서 수행한다.

## 12. 성능 목표

50명 기준, 서버 내부 DB 구간 목표:

| 경로 | p95 목표 |
|---|---:|
| 오늘 Todo 조회 | 50ms 이하 |
| 하루 요약 대상 조회 | 50ms 이하 |
| Todo 단일 쓰기 | 100ms 이하 |
| 동기화 200행 | 150ms 이하 |
| 반복 인스턴스 500행 | 500ms 이하 |

전체 API 지연에는 네트워크가 포함되므로 별도로 측정한다.

## 13. 운영 점검

출시 전 대표 쿼리에 다음을 실행한다.

```sql
explain (analyze, buffers)
select ...;
```

월 1회 확인:

- `pg_stat_statements` 총 실행 시간 상위 10개
- 평균 100ms 이상 DB 쿼리
- 순차 스캔이 발생한 대형 테이블
- 사용되지 않는 중복 인덱스
- dead tuple과 autovacuum 상태
- integration_jobs 재시도와 실패 건수

50명 규모에서 캐시는 추가하지 않는다. DB p95 목표를 실제로 넘는 경로가 확인될 때만 쿼리·인덱스를 먼저 고친다.

## 14. 검색 인덱스

사용자 직접 검색과 Agent 검색은 별도 조회 테이블 없이 같은 Todo 검색 경로를 사용한다. 한국어 제목 부분 검색을 위한 `pg_trgm` GIN 인덱스와 확장 기준은 [일정 검색 파이프라인](./18-todo-search-pipeline.md)에 정의한다.

GIN 인덱스는 쓰기 비용이 있으므로 제목 검색 하나로 시작하고 메모 결합 인덱스는 측정 후 추가한다.
