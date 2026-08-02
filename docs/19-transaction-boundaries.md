# 트랜잭션 경계와 의사결정

> 데이터 규칙: [데이터 모델](./04-data-model.md)  
> 작업 파이프라인: [데이터 파이프라인](./17-data-pipeline.md)  
> 외부 통합: [외부 API 통합](./15-external-integrations-and-naming.md)

## 1. 원칙

트랜잭션은 “함께 성공하거나 함께 실패해야 데이터 의미가 유지되는 DB 변경”에만 사용한다.

포함:

- 여러 행의 상태가 하나의 사용자 행동을 표현
- 도메인 변경과 후속 작업 등록이 함께 보장돼야 함
- 중복 요청 방지 기록과 실제 변경

제외:

- OpenAI 호출
- 뉴스 검색
- APNs 전송
- EventKit 접근
- 긴 계산
- 사용자 입력 대기

외부 호출 중 DB 트랜잭션을 열어두지 않는다.

## 2. 격리와 동시성

- 기본 격리 수준: PostgreSQL `READ COMMITTED`
- Todo 수정: `version` 기반 optimistic concurrency
- 일반 command와 sync 모두 request body의 `baseVersion` 사용
- 작업 획득: `FOR UPDATE SKIP LOCKED`
- 같은 반복 규칙의 창 생성: unique 제약 + `ON CONFLICT DO NOTHING`
- 직렬화 격리 수준은 사용하지 않는다.

충돌 응답:

```text
409 RESOURCE_VERSION_CONFLICT
```

클라이언트는 최신 데이터를 받고 사용자 변경을 다시 적용할지 결정한다.

## 3. 트랜잭션 결정표

| 작업 | 하나의 트랜잭션 | 이유 |
|---|---:|---|
| Todo 단일 생성 | 예 | Todo와 reminder 설정의 원자성 |
| Todo 수정 | 예 | version 확인과 업데이트를 한 문장으로 처리 |
| Todo 직접 재예약 | 예 | 원본 rescheduled와 replacement insert 원자성 |
| 완료 버튼 | 예 | Todo 상태와 completedAt 일치 |
| 하루 요약 완료 응답 | 예 | Todo 상태와 ReviewResponse 중복 방지 |
| 내일로 이동 | 예 | 원본 rescheduled와 새 Todo가 함께 존재해야 함 |
| AI 초안 생성 | 아니오 | 외부 호출과 사용자 승인 대기 포함 |
| AI 초안 commit | 예 | Plan, Todo 묶음, draft committed 상태의 원자성 |
| 반복 규칙 생성 | 예 | 규칙과 초기 작업 등록이 함께 보장 |
| 반복 인스턴스 배치 | 규칙별 예 | 한 규칙 실패가 다른 규칙을 막지 않게 함 |
| 동기화 batch | mutation별 예 | 한 충돌이 전체 100개를 롤백하지 않게 함 |
| 브리핑 외부 수집 | 아니오 | 네트워크 호출 |
| 브리핑 최종 저장 | 예 | briefing과 items가 불완전하게 보이지 않게 함 |
| 동의 철회 | 예 | 동의, 자동화 중지, 연결 상태, 폐기 작업 등록 |
| APNs 발송 | 아니오 | 외부 네트워크 |
| APNs 작업 등록 | 도메인 변경과 함께 예 | 변경 성공 후 알림 작업 유실 방지 |
| Slack 메시지 전송 | 아니오 | 외부 API라 DB 롤백으로 취소할 수 없음 |
| Slack 전송 proposal 상태 변경 | 단계별 예 | 승인·executing·applied/failed 전이를 원자적으로 기록 |

## 4. 하루 요약 응답

### 완료

한 트랜잭션:

```text
ReviewResponse insert
Todo status=completed
Todo progress=100
Todo completedAt=now
pending reminder cancel job insert
```

`(daily_review_id, todo_id)` unique 제약으로 중복 탭을 막는다.

### 내일로 이동

한 트랜잭션:

```text
원본 Todo version 확인
→ 원본 status=rescheduled
→ 새 Todo insert
→ 새 Todo.rescheduledFromId=원본 ID
→ ReviewResponse insert
→ 원본 reminder 취소 job insert
```

새 Todo 생성에 실패했는데 원본만 rescheduled가 되면 일정이 사라진 것처럼 보이므로 반드시 원자적으로 처리한다.

## 5. AI 초안

### 생성

```text
짧은 DB 읽기
→ 트랜잭션 종료
→ OpenAI 호출
→ 결과 검증
→ 짧은 트랜잭션으로 PlanDraft 저장
```

사용자 승인 대기 동안 어떤 트랜잭션도 유지하지 않는다.

### commit

한 트랜잭션:

```text
PlanDraft SELECT FOR UPDATE
→ owner/expiry/status 확인
→ DailyPlan upsert
→ Todo batch insert
→ PlanDraft status=committed
→ idempotency record 저장
```

동일 draft의 두 번 commit을 막는다.

## 6. 반복 일정

### 규칙 생성

한 트랜잭션:

```text
ScheduleRule insert
→ refresh_recurrence_window job insert
```

인스턴스 생성은 외부 호출이 없지만 사용자 요청 응답을 짧게 유지하기 위해 작업으로 분리한다.

### 인스턴스 생성

규칙 하나당 트랜잭션 하나:

```text
규칙 활성 상태 확인
→ 향후 occurrence 계산 완료
→ batch insert on conflict do nothing
→ windowGeneratedThrough 갱신
```

계산은 트랜잭션 전에 할 수 있으나 최종 활성 상태를 트랜잭션 안에서 다시 확인한다.

## 7. 동의 철회

한 트랜잭션:

```text
ConsentRecord revoked
→ 관련 AgentAutomation disabled
→ DataConnection status=revoking
→ token revoke job insert
```

외부 토큰 폐기는 트랜잭션 밖 작업이다. 실패해도 앱 내부 접근은 이미 차단되어야 한다.

## 8. 브리핑 저장

외부 뉴스 검색과 AI 요약은 트랜잭션 밖에서 끝낸다.

최종 저장만 한 트랜잭션:

```text
NewsArticle upsert
→ DailyBriefing upsert
→ 기존 BriefingItem 교체
→ 새 BriefingItem batch insert
→ job succeeded
```

사용자에게 항목이 절반만 있는 브리핑을 보여주지 않는다.

## 9. 작업 큐

작업 claim 트랜잭션:

```text
pending/retry_wait 한 행 SELECT FOR UPDATE SKIP LOCKED
→ processing, lockedAt, lockedBy 업데이트
→ commit
```

그 후 외부 호출하고 결과 저장은 새 트랜잭션에서 수행한다.

## 10. 타임아웃

- 사용자 요청 트랜잭션: 목표 500ms 이하
- DB statement timeout: 3초
- 배치 작업: 15초
- lock timeout: 1초

lock timeout 발생 시 사용자 요청은 재시도 가능한 충돌로 반환하고 무한 재시도하지 않는다.

## 11. 롤백과 보상

DB 트랜잭션으로 묶을 수 없는 외부 부작용은 보상 작업을 정의한다.

| 외부 작업 | 부분 실패 처리 |
|---|---|
| APNs | 재시도 후 실패 기록, 도메인 상태 유지 |
| 외부 캘린더 쓰기 | 동기화 실패 표시, 사용자가 재시도 |
| 뉴스 생성 | 이전 브리핑 유지 |
| OpenAI 초안 | 초안 생성 실패, Todo 변화 없음 |
| 토큰 폐기 | 내부 연결 즉시 차단 후 폐기 재시도 |
| Slack 메시지 | idempotency key와 저장된 Slack timestamp로 중복 전송을 막고 실패 시 proposal 재시도 |

분산 트랜잭션과 two-phase commit은 사용하지 않는다.

모든 version update는 다음 형태의 조건부 한 문장으로 처리한다.

```sql
update public.todos
set ..., version = version + 1, updated_at = now()
where id = :id
  and user_id = (select auth.uid())
  and version = :base_version
returning *;
```

반환 행이 없으면 별도 소유권 안전 조회로 404와 409를 구분한다. 외부 API 호출은 이 조건부 update 전후의 DB 트랜잭션 안에 넣지 않는다.

## 12. 테스트

필수 동시성 테스트:

- 같은 draft 동시 commit 한 번만 성공
- 같은 Todo 동시 완료 응답 중복 방지
- stale version 수정은 409
- 반복 job 중복 실행에도 한 occurrence
- reschedule 중 새 Todo 실패 시 원본 롤백
- 동의 철회와 Agent 실행 경쟁 시 Agent 실행 차단
