# 일정 검색 파이프라인

> 데이터 기준: [데이터 모델](./04-data-model.md)  
> DB 인덱스: [DB 성능·운영](./14-database-performance-and-operations.md)  
> Agent 사용: [Agent 설계](./20-ai-agent-architecture.md)

## 1. 결론

초기 50명 규모에는 별도 조회 테이블, 검색 서버, 벡터 DB가 필요 없다. `todos` 원본 테이블에 사용자·날짜·상태 필터와 PostgreSQL `pg_trgm` 검색을 적용한다.

검색 경로는 두 개지만 같은 `SearchTodos` 도메인 기능을 사용한다.

```text
사용자 검색 UI ─┐
               ├→ SearchTodos → PostgreSQL
Memdo Agent ──┘
```

Agent 전용 검색 데이터 복제본을 만들지 않는다.

## 2. 검색 대상

기본 검색 필드:

- `title`
- `note`
- `scheduled_date`
- `time_bucket`
- `status`
- `source`
- 반복 여부

검색하지 않는 필드:

- AI 프롬프트 원문
- 감사 로그
- 외부 공급자 원본 응답
- 개인정보 동의 기록

## 3. 검색 단계

```mermaid
flowchart LR
    Q["검색 입력"] --> N["공백·길이 정규화"]
    N --> F["사용자·날짜·상태 필터"]
    F --> T["제목·메모 문자열 검색"]
    T --> R["랭킹"]
    R --> P["키셋 페이지네이션"]
    P --> S["최소 SearchResult 반환"]
```

### 3.1 입력 정규화

- 앞뒤 공백 제거
- 연속 공백 하나로 축소
- 최대 100자
- 빈 문자열은 텍스트 검색 없이 구조화 필터만 적용
- SQL wildcard는 파라미터 바인딩으로 처리

### 3.2 기본 범위

사용자가 범위를 지정하지 않으면:

```text
지난 90일 ~ 앞으로 365일
deleted_at is null
```

Agent는 사용자의 표현에서 날짜가 명확할 때만 범위를 좁힌다. “예전에”, “최근에”처럼 모호하면 정규 기본값을 사용하고 응답에 범위를 표시한다.

## 4. 검색 API

기존 Todo 목록 API를 확장한다.

```http
GET /v1/todos?q=운동&from=2026-01-01&to=2026-12-31&status=completed&cursor=...
```

파라미터:

```text
q
from
to
status[]
timeBucket[]
source[]
isRecurring
cursor
limit <= 50
```

응답:

```text
items
matchedFields
nextCursor
hasMore
appliedFilters
```

`matchedFields`는 `title`, `note`만 반환하며 note 전체를 노출하지 않는다.

## 5. 한국어 검색

PostgreSQL 기본 형태소 분석만으로 한국어 어미와 조사를 만족스럽게 처리하기 어렵기 때문에 MVP는 trigram 부분 문자열 검색을 사용한다.

```sql
create extension if not exists pg_trgm;

create index todos_title_trgm_active_idx
on public.todos
using gin (lower(title) gin_trgm_ops)
where deleted_at is null;
```

메모 검색은 초기에는 사용자 날짜 범위로 먼저 좁힌 뒤 `ILIKE`를 사용한다. 실제 메모 검색 p95가 목표를 넘을 때만 아래 결합 인덱스를 추가한다.

```sql
create index todos_search_text_trgm_active_idx
on public.todos
using gin (
  lower(title || ' ' || coalesce(note, '')) gin_trgm_ops
)
where deleted_at is null;
```

두 GIN 인덱스를 동시에 처음부터 만들지 않는다. 제목 검색 인덱스로 시작하고 측정 후 결합 인덱스로 교체한다.

## 6. 쿼리와 랭킹

랭킹 우선순위:

1. 제목 완전 일치
2. 제목 prefix 일치
3. 제목 trigram 유사도
4. 메모 포함
5. 최신 일정

정확한 생산성 점수처럼 사용자에게 점수를 노출하지 않는다.

개념 쿼리:

```sql
select
  id,
  title,
  scheduled_date,
  status,
  start_at,
  case
    when lower(title) = lower($query) then 100
    when lower(title) like lower($query) || '%' then 80
    else similarity(lower(title), lower($query)) * 50
  end as rank
from public.todos
where user_id = $user_id
  and scheduled_date between $from and $to
  and deleted_at is null
  and (
    lower(title) % lower($query)
    or lower(title) like '%' || lower($query) || '%'
    or lower(coalesce(note, '')) like '%' || lower($query) || '%'
  )
order by rank desc, scheduled_date desc, id
limit $limit;
```

구현 전 `EXPLAIN (ANALYZE, BUFFERS)`로 실제 인덱스 사용을 검증한다.

## 7. 검색 결과 모델

```text
TodoSearchResult
- id
- title
- emoji
- scheduledDate
- startAt
- timeBucket
- status
- matchedFields
- notePreview?
```

검색 결과에는 전체 Todo 객체를 반환하지 않는다. 상세가 필요하면 `GET /todos/{id}`를 호출한다.

## 8. Agent 검색

Agent 도구:

```text
search_todos(
  query?,
  from?,
  to?,
  statuses?,
  time_buckets?,
  sources?,
  is_recurring?,
  cursor?,
  limit?
)
```

도구 규칙:

- 항상 현재 인증 사용자 범위
- 최대 20개
- 날짜 범위 최대 2년
- note는 미리보기만
- 검색 결과가 많으면 추측하지 않고 조건을 좁히도록 안내
- Agent가 SQL이나 임의 filter 문법을 전달하지 않음

예:

```text
사용자: 지난달에 운동한 날을 찾아줘
Agent:
  from/to 계산
  statuses=[completed]
  query="운동"
  search_todos 호출
  날짜와 제목만 요약
```

## 9. 검색 기록

MVP에서는 검색어 기록 테이블을 만들지 않는다.

운영 메트릭만 기록:

- 검색 요청 수
- 결과 0건 비율
- DB 지연
- Agent와 직접 검색 구분

검색어 원문과 결과 제목은 로그에 남기지 않는다.

## 10. 확장 기준

다음이 실제로 확인될 때만 확장한다.

| 조건 | 다음 단계 |
|---|---|
| 메모 검색 p95 200ms 초과 | 결합 trigram 인덱스 |
| 의미가 비슷한 일정 검색 요구가 반복 | 임베딩 실험 |
| 사용자당 Todo 100만 건 수준 | 검색 전용 저장소 검토 |
| 여러 도메인 문서 통합 검색 | 별도 검색 인덱스 검토 |

임베딩을 도입하더라도 권한 필터는 검색 후가 아니라 검색 전 또는 저장소 namespace 수준에서 적용한다.

