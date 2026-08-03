# 전체 문서 정합성 감사와 해결 기록

상태: GAP-001~018 해결
점검 범위: `00`~`27`, iOS DESIGN, OpenAPI 3.1
최종 반영일: 2026-08-01

## 1. 결과

이전 감사에서 발견한 구현 차단 8개와 Phase 착수 전 보완 9개를 기준 문서에 반영했다.

```text
P0 구현 차단: 8 → 0
P1 구현 전 보완: 9 → 0
출시 전 외부 결정: 책임·기한·차단 조건 확정
의도적 후순위: 확장 조건 유지
```

구현 중 새 불일치가 발견되면 이 문서의 다음 GAP ID로 기록하고, ADR·UX·데이터·OpenAPI·테스트를 같은 PR에서 수정한다.

## 2. 해결 매트릭스

| GAP | 해결 | 정답 문서 |
|---|---|---|
| 001 삭제 후 Day 상태 | 삭제 이력만 있으면 needs_planning, 완료 이력이 남으면 completed | 10, 11, 03 |
| 002 optimistic concurrency | 일반 command와 sync 모두 `baseVersion`, stale은 409 | 05, 19, 25 |
| 003 상세·재예약 API | GET Todo와 원자적 reschedule command 추가 | 05, 19 |
| 004 Todo 필드 불일치 | input·patch·response 필드와 필수 version 정렬 | 04, 05 |
| 005 review inclusion | Todo별 토글 제거, 모든 미완료 Todo 확인 | 02, 07, 10 |
| 006 Reminder 이중 모델 | 일정당 로컬 reminder 하나, Todo offset으로 저장 | 04, 05, 07 |
| 007 Review 설정·응답 | 고정 대상, partial 1~99, 조건부 targetDate | 02, 05, 07 |
| 008 Consent 입력 | type enum과 `ConsentGrantInput` 추가 | 05, 06 |
| 009 로컬→계정 | 로컬 UUID 유지, 내용 병합 금지, cache 정책 확정 | 03, 04, 10 |
| 010 Sync 결과 | mutation별 applied·conflict·rejected schema | 05, 17 |
| 011 DailyPlan 편집 | 날짜별 GET·PUT과 version 계약 | 05 |
| 012 P1 추적성 | PRD-101~108과 TEST-101~108 연결 | 01, 12 |
| 013 schema inventory | 물리 테이블 PK·FK·unique·보존·RLS 표 | 04 |
| 014 외형 token | ADR-058로 theme·accent 서버 enum을 제거하고 iOS semantic Light/Dark + 고정 brand point로 대체 | 02, 05, 10, 27 |
| 015 자동 브리핑 | localTime·days·timezone, 하루 1회 | 02, 05, 17 |
| 016 반복 규칙 | DAILY·WEEKLY 부분집합, 예외·version 정책 | 03, 05, 10 |
| 017 알림 예산 | 7일·48개 rolling window와 reconciliation | 07, 10 |
| 018 일정 유형·Agent IA | 임시 milestone/AI 페이지를 event·task·dueAt과 3개 콘텐츠 탭+Agent 액션으로 교체하고 PRD·UX·ERD·OpenAPI·TEST를 동기화 | 01, 02, 04, 05, 10, 11, 12, 27, iOS DESIGN |

## 3. 출시 게이트

| 게이트 | 결정 | 책임 | 기한 |
|---|---|---|---|
| 이름·도메인 | 개발명 Memdo, 상표 확인 전 Store 제출 금지 | Founder | 외부 배포 30일 전 |
| 국가·연령 | 대한민국, 만 14세 이상 | Founder | 정책 작성 전 |
| 법률 검토 | 외부 전문 승인 없으면 공개 출시 금지 | Founder | 공개 출시 30일 전 |
| DB 운영 | 내부 50명은 Free, 공개 사용자 전 Pro | Tech Lead | 공개 출시 7일 전 |

외부 확인이 필요한 사실을 완료로 가장하지 않고 release checklist가 배포를 차단하게 한다.

## 4. 의도적 후순위

다음은 현재 구현에 필요하지 않고 전환 조건이 이미 정의돼 있다.

- Hono
- Agents SDK와 다중 Agent
- iOS 내부 호출용 MCP
- 일반 Todo 조회 Redis cache·Kafka·외부 검색 서버
- 파티셔닝과 읽기 복제본
- OpenAPI client code generation과 operationId

iOS MVP는 `URLSession` 기반의 작은 수동 client를 사용한다. 코드 생성 ADR이 생길 때 안정적인 operationId를 전체 API에 추가한다.

## 5. 검증 기준

- OpenAPI YAML parse
- schema `$ref` 해소
- 내부 상대 링크 존재
- UX 입력과 데이터/API 필드 매핑
- 쓰기 command의 idempotency·baseVersion
- P0·P1 PRD의 TEST 연결
- 사용자 소유 테이블의 RLS와 FK 인덱스
- 출시 게이트 책임·기한

첫 migration과 Swift API 모델 구현은 이 해결 기록을 기준으로 시작할 수 있다.
