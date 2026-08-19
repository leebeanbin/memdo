# AI Agent 구성과 운영 구조

> 제품 정책: [개인정보·동의·AI 정책](./06-privacy-consent-ai-policy.md)  
> 일정 검색: [검색 파이프라인](./18-todo-search-pipeline.md)  
> 트랜잭션: [트랜잭션 경계](./19-transaction-boundaries.md)  
> 외부 통합: [외부 API 통합](./15-external-integrations-and-naming.md)

> **실제 구현 현황(2026-08-17)**: 이 문서의 "1. 선택"이 서술하는 `OpenAI Responses API +
> 서버 오케스트레이션` 단일 경로는 [ADR-073](./10-decisions-and-open-questions.md)으로 대체됐다.
> 실제로 배포한 구조는 (1) 기기 내 Apple FoundationModels(`LanguageModelSession`, Reflection
> 포함, `apps/ios/Memdo/Memdo/AssistantView.swift`)를 기본 경로로 쓰고, (2) 사용자가 원할 때만
> 자신의 OpenRouter API 키(BYOK)로 클라우드 모델을 쓰는 2트랙 구조다. 클라우드 경로는
> `memdo-backend/supabase/functions/agent-cloud-chat`가 OpenRouter Chat Completions를 SSE로
> 스트리밍하고, `propose_schedule` 도구 호출마다 서버가 직접 시간 충돌을 재검사한다(6절 이하가
> 말하는 Consent Gate·Read Tools·Structured Proposal의 취지는 유지했지만 실제 도구 이름·개수·
> Responses API 세부 계약은 이 문서와 다르다). 아래 절은 원래 설계 의도와 확장 조건을 남겨 두는
> 참고 자료로 유지한다.

## 0. 실제 제공 경로와 비용 경계

1. 지원 기기에서는 Apple FoundationModels를 기본으로 사용한다. 일정 분류·요약·초안처럼 기기 내
   모델에 맞는 작업은 서버 추론비 없이 처리한다.
2. 더 큰 문맥이나 서버 모델이 필요한 사용자는 자신의 OpenRouter 키를 연결한다. 입력은
   `SecureField`와 명시적 시스템 붙여넣기로 제한하고, 앱은 클립보드를 자동으로 읽지 않는다.
3. `.env` 파일 업로드는 지원하지 않는다. 단일 키 연결에 불필요하고 파일 안의 다른 배포·DB 비밀까지
   전송할 위험이 있기 때문이다. 다중 공급자 일괄 연결 수요가 확인될 때만 허용된 키 이름을 기기에서
   파싱하고 원본 파일은 서버에 보내지 않는 방식을 검토한다.
4. 향후 Memdo가 비용을 부담하는 Cloud 플랜을 추가하면 서버 소유 키만 Edge Function에서 사용하고,
   사용자별 월 포함량·요청 속도·일일 비용에 hard cap을 둔다. iOS 안에서 기능이나 디지털 사용량을
   판매하는 결제는 StoreKit 경로를 사용한다. 무제한 무료 플랜과 클라이언트 내 공용 공급자 키는 두지 않는다.

## 1. 선택

MVP는 `LLM Gateway + 서버 함수 도구 + 단일 Memdo Agent`를 사용한다. production 기본 adapter는 OpenAI Responses API이고 개발·명시적 self-host adapter는 llama.cpp다.

초기에는 Agents SDK, 다중 Agent, handoff를 사용하지 않는다. iOS 내부 Agent는 MCP를 거치지 않으며 외부 client용 MCP는 같은 Memdo API를 호출한다.

이유:

- 계획·검색·브리핑이라는 작은 도구 집합
- 사용자가 승인하기 전 쓰기 금지
- Supabase Edge Functions의 TypeScript 실행 환경
- 직접 오케스트레이션이 더 짧고 명시적
- 다중 Agent가 해결할 독립 전문 영역이 아직 없음

Agents SDK는 도구 호출 루프, 세션, guardrail, handoff, tracing 관리가 필요해질 때 도입 후보로 둔다. 공식 문서상 Agents SDK도 OpenAI 모델에 Responses API를 기본 사용하며, SDK는 그 위의 오케스트레이션 계층이다.

## 2. 전체 구조

```mermaid
flowchart TD
    U["사용자 메시지"] --> C["Consent Gate"]
    C --> A["Memdo Agent"]
    A --> LLM["LLM Gateway"]
    LLM --> OPENAI["OpenAI Responses"]
    LLM --> LOCAL["llama.cpp local/self-host"]
    A --> RT["Read Tools"]
    RT --> SEARCH["search_todos"]
    RT --> DAY["get_day_context"]
    RT --> PREF["get_user_preferences"]
    RT --> FREE["find_free_time"]
    A --> OUT["Structured Proposal"]
    OUT --> UI["사용자 확인 UI"]
    UI -->|승인| CMD["Command API"]
    CMD --> DB[("PostgreSQL")]
    UI -->|수정| A
    UI -->|취소| END["변경 없음"]
```

Agent는 조회하고 제안한다. 실제 쓰기는 Agent 도구가 아니라 승인된 Command API가 수행한다.

## 3. Agent 이름

제품 코드 이름:

```text
MemdoAgent
```

사용자 표시 이름:

```text
Memdo
```

피할 이름:

```text
SuperAgent
OrchestratorAgent
TodoMasterAgent
PersonalAGI
```

## 4. Agent 책임

포함:

- 자연어 일정 검색
- 사용자의 하루 의도 이해
- 일정 초안 제안
- 기존 일정 충돌 설명
- 브리핑 기사 요약
- 모호한 요청에 필요한 최소 확인

제외:

- 완료 여부 추측
- 사용자 승인 없는 쓰기
- DB SQL 생성·실행
- 동의 범위 결정
- 권한 우회
- 외부 토큰 접근
- 장기 자동화 실행

반복 일정 자동 생성은 Agent가 아니라 승인된 `ScheduleRule`과 규칙 엔진의 책임이다.

## 5. 도구 목록

### 조회 도구

```text
search_todos
get_todo
get_day_context
get_user_preferences
find_free_time
get_interest_topics
```

### 외부 정보 도구

```text
search_news
```

뉴스 동의가 있을 때만 활성화한다.

### 제안 도구

별도 DB 쓰기가 아니라 실행 결과의 구조를 만드는 도구:

```text
propose_plan_draft
propose_todo_changes
propose_schedule_rule
```

실제 변경 도구:

```text
없음
```

승인 후 앱이 일반 API를 호출한다.

## 6. 도구 네이밍

모델 도구 이름은 lower snake_case 동사 + 명사:

```text
search_todos
get_day_context
find_free_time
search_news
```

도구 설명에는 반드시 다음을 포함한다.

- 사용할 때
- 사용하지 않을 때
- 입력 필드
- 반환 필드
- 최대 결과 수
- 오류 코드
- 개인정보 범위

`execute`, `process`, `handle` 같은 모호한 동사는 사용하지 않는다.

## 7. 실행 흐름

```text
1. 인증 확인
2. AI 동의와 세부 scope 확인
3. 사용자 입력 검증
4. Agent instructions 구성
5. 허용된 도구만 등록
6. Responses API 실행
7. 도구 호출을 서버 도메인 함수로 처리
8. 최종 structured output 검증
9. PlanDraft 또는 Proposal 저장
10. 사용자 승인 화면
11. 승인 후 일반 Command API 실행
```

## 8. 출력 타입

### AgentResponse

```text
kind:
  answer
  todo_search_results
  plan_draft
  todo_change_proposal
  schedule_rule_proposal
  clarification
  refusal

message
evidence[]
proposal?
appliedScope
```

### TodoChangeProposal

```text
proposalId
expiresAt
summary
operations[]
warnings[]
```

operation:

```text
create
update
reschedule
complete
skip
```

`complete`와 `skip`도 반드시 사용자 확인을 받는다.

## 9. 프롬프트 구조

```text
<role>
개인형 데일리 캘린더의 계획 파트너
</role>

<product_rules>
평가하지 않기
완료 추측 금지
승인 없는 변경 금지
</product_rules>

<privacy_scope>
이번 실행에서 허용된 데이터 필드
</privacy_scope>

<tool_rules>
조회 도구 사용 조건
결과 한도
재호출 제한
</tool_rules>

<output_contract>
정확한 structured output schema
</output_contract>

<stop_conditions>
최대 turn과 모호성 처리
</stop_conditions>
```

## 10. 실행 제한

```text
max model turns: 6
max tool calls: 8
search_todos max results: 20
news candidates before summary: 10
whole request timeout: 20 seconds
tool timeout: 3 seconds internal / 8 seconds external
```

한도를 넘으면 부분 결과와 명확한 실패 이유를 반환한다.

## 11. 대화 상태

MVP 기본은 요청 단위 실행이다.

- 서버에 장기 자유대화 메모리를 만들지 않는다.
- 사용자가 수정 중인 `PlanDraft`만 24시간 유지한다.
- 후속 메시지는 draft ID로 문맥을 연결한다.
- 과거 대화 전체를 매번 모델에 보내지 않는다.
- 사용자 선호는 명시적 preferences 테이블에서 읽는다.

대화형 사용이 핵심으로 검증되면 Responses continuation 또는 Agents SDK session 중 하나를 선택한다. 둘을 중복 적용하지 않는다.

## 12. Guardrail

### 입력

- 최대 길이
- 지원하지 않는 민감 작업 차단
- 동의 범위 확인
- 날짜와 타임존 검증

### 도구

- 인증 사용자 ID는 모델 입력이 아니라 서버 context에서 주입
- 최대 날짜 범위
- 최대 결과 수
- SQL, URL, 토큰을 도구 인자로 받지 않음

### 출력

- JSON Schema 검증
- 존재하지 않는 Todo ID 거부
- 조회하지 않은 Todo에 대한 변경 제안 거부
- 허용 범위 밖의 필드 제거
- 최대 작업 수 5개

## 13. 감사와 추적

저장:

```text
agentRunId
workflowName
model
toolNames
toolCallCount
latencyMs
resultKind
approvalStatus
providerRequestId
```

기본 미저장:

```text
사용자 메시지 원문
Todo 제목·메모
도구 전체 입출력
모델 응답 원문
```

Agents SDK tracing을 도입할 경우 민감 데이터 포함을 비활성화하고, SDK tracing과 자체 `agent_runs`의 책임을 구분한다.

## 14. 평가

출시 전 최소 평가셋:

- 직접 일정 검색 20개
- 날짜가 모호한 검색 10개
- 계획 생성 20개
- 충돌 일정 10개
- 동의 범위 10개
- 승인 없는 변경 방지 10개
- 한국어 시간 표현 20개

평가 항목:

```text
도구 선택 정확도
날짜 해석
검색 recall
잘못된 Todo ID 비율
미승인 쓰기 시도
동의 범위 위반
응답 지연
토큰 비용
```

## 15. 확장 조건

### Model adapter

두 adapter가 공유하는 것은 구조화 생성과 embedding 요청의 Memdo 입력·출력 계약뿐이다. OpenAI Responses API와 llama.cpp의 HTTP API가 완전히 같다고 가정하지 않는다.

```text
generateStructured(request, schema)
embed(texts, modelVersion)
```

- provider error는 정규 오류로 변환한다.
- model ID, prompt version, schema version을 AgentRun에 기록한다.
- local laptop endpoint는 production Edge에서 접근할 수 없으므로 production provider로 자동 fallback하지 않는다.
- Redis는 rate limit과 짧은 중복 실행 lock에만 사용하고 대화·Todo 원본을 저장하지 않는다.

### 의미 검색

직접 검색은 pg_trgm이 기본이다. 평가셋에서 의미 검색이 필요한 질의를 별도로 정의하고 pgvector가 recall을 개선할 때만 hybrid retrieval을 켠다. 동의하지 않은 note는 embedding하지 않으며 vector query에도 user filter를 먼저 적용한다.

### Agents SDK

다음이 필요할 때:

- 복수 turn의 복잡한 도구 루프
- 중단·승인 후 실행 재개
- 표준 tracing과 guardrail 운영
- 하나 이상의 전문 Agent

### 다중 Agent

다음이 데이터로 확인될 때만:

- 뉴스와 일정 계획이 서로 다른 평가 기준과 도구를 가져 단일 prompt 성능을 저해
- 병렬 전문 작업이 지연을 유의미하게 줄임
- 단일 Agent eval이 지속적으로 실패

### MCP

다음이 필요할 때:

- ChatGPT나 다른 Agent가 Memdo 일정에 접근
- 외부 클라이언트에 표준 도구 계약 제공

앱 내부 Agent가 자체 API를 호출하기 위해 MCP를 추가하지 않는다.

외부 Codex·ChatGPT에 일정을 제공할 때의 도구, OAuth, 제안 응답, 승인 링크 구조는 [Integration Hub](./21-integration-hub-google-calendar-mcp.md)를 따른다.
