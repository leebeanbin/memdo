# 로드맵과 백로그

> 범위 기준: [제품 요구사항](./01-product-requirements.md)
> 선행 결정: [결정 기록](./10-decisions-and-open-questions.md)
> 각 버전 완료 증거: [요구사항 추적표](./12-requirements-traceability.md), [테스트 계획](./08-test-and-release-plan.md)
> Experience Track(별도 번호 체계): [Experience 로드맵](./33-experience-roadmap.md)
> 엔지니어링 측 pre-v0.9 이력(Epic C-J 구현 순서): [memdo-backend/docs/roadmap.md](../../memdo-backend/docs/roadmap.md)

> **개정(2026-08-24)**: Phase 0~5 기준 로드맵을 버전 기반(v0.9~v2.0) 로드맵으로 재구성했다. 기존
> Phase 0~5 내용은 실제로 있었던 이력이므로 삭제하지 않고 [이전 이력](#이전-이력-pre-v09) 절로
> 보존한다. 이 개정 이후 로드맵은 아래 원칙을 따른다.

## 가이딩 원칙

- **LLM = 해석(Interpretation), Code = 사실(Truth), User = 승인(Authority).** 완료율, 반복
  미완료, 일정 밀도, 루틴 유지율 같은 사실/신호는 항상 code/SQL이 계산한다. LLM은 이미 계산된
  사실을 해석·설명하거나 proposal을 생성하는 역할만 맡는다. 모든 mutation은 사용자 승인을 거쳐
  기존 Command API(`todos`/`preferences`/`reviews` 등)로만 실행된다 — 이 불변식은 v2.0까지 어떤
  버전에서도 바뀌지 않는다.
- 벡터 DB, 다중 Agent, 자유 자동 실행은 초기 버전에 도입하지 않는다. v2.0에서 실제로 필요하다면
  그 시점에 실사용 데이터를 근거로 결정한다 — 지금 미리 설계하지 않는다.
- "Memory"(세션을 넘나드는 영속적 사용자 모델링)는 v1.1~v1.5의 결정론적 insight/proactive 루프가
  실사용 가치를 증명한 뒤로 미룬다. 추측성으로 먼저 만들지 않는다.
- 이 로드맵은 **1인 개발자에게 맞는 gated 로드맵**이다. 각 버전은 다음 버전으로 넘어가는 명시적
  Go/Hold/Drop gate를 가진다. v1.0 이후 어떤 버전도 "반드시 만들어야 하는 백로그"가 아니다 — 예를
  들어 v1.4(제안형 알림)는 v1.1~v1.3에서 확인한 실사용 approval-rate 데이터가 근거가 될 때만 Go한다.

## v0.9 — Agent Foundation Closeout

**상태: 대부분 완료 (Epic J 진행 중)** — 이 버전은 이번 세션의 Epic C~J 작업으로 대부분 이미
구현되었다. 완결성을 위해 기록하고 다음 버전으로 가는 gate를 명시한다.

- **Product goal**: 사용자 대상 성장 작업을 시작하기 전에, 온디바이스/클라우드 Agent 런타임 경계,
  proposal staging, eval 인프라, 모델 registry를 신뢰 가능하고 테스트 가능하며 교체 가능한
  컴포넌트로 만든다.
- **주요 Epic 후보**: C(도메인 로직 분리) ✓ / D-1(런타임 경계) ✓ / D-2(공급자 중립 staging) ✓ /
  E(eval 러너) ✓ / F-1(결정론적 seeding) ✓ / F-2(다중 모델 비교) ✓ / G(모델 registry) ✓ /
  H(감사 로깅, write-only) ✓ / I(루틴/리뷰 proposal UI) ✓ / J(clarification tool + canonical
  AgentIntent) — 진행 중.
- **In scope**: 온디바이스/클라우드 라우팅; 모든 tool의 propose→approve→기존 Command API 패턴;
  eval corpus + grading + 다중 모델 비교; 모델 capability registry; 실행 단위 감사 기록(write
  경로만); iOS UI에서 모든 tool-call에 대한 커버리지.
- **Out of scope**: 감사 로그 UI/분석 소비자; 루틴/리뷰/clarification tool의 온디바이스 parity;
  `eval:compare` 실제 실행 + registry 승격(의도적으로 자동화하지 않은 사람의 수동 운영 단계); MCP;
  다중 Agent.
- **Definition of Done**: 사용자 권한이 필요한 모든 mutation proposal 출력은 실제 iOS confirmation
  UI를 가진다. clarification은 명확히 구분되는 UI state이지 approval UI가 아니다 — 승인할 대상이
  없다. Read-only tool은 confirmation 없이 assistant 응답에 직접 기여할 수 있다. Staged proposal
  출력이 iOS에서 silently drop되는 경우는 없다. 별도로 eval 쪽에서는: runtime-observable tool
  signal이 있는 corpus behavior는 모두 자동 채점 가능하고, `ANSWER`/`UNSUPPORTED`만 근본적으로
  manual-review로 남는다(버그가 아니라 구조적 한계) — 이는 eval corpus 자체의 `expectedBehavior`
  vocabulary이며, iOS `AgentIntent`의 case 집합과 관련은 있지만 동일하지 않다(예: `UNSUPPORTED`는
  전자에만 존재).
- **운영 metric**: 아직 실사용자가 없다 — 유일한 신호는 eval pass-rate 추세이며, 그것도 전용 eval
  계정으로 `eval:compare`를 실제로 실행했을 때만 의미가 있다.
- **Gate to v1.0**: Epic J가 머지되고, 실제 기기 + 실제 OpenRouter 연결 계정에서 모든 Agent
  proposal 유형과 clarification이 정확히 렌더/승인/거절되는지 수동 smoke pass로 확인하면 Go.

## v1.0 — Public Beta / Stability

- **Product goal**: 처음으로 실제 외부 사용자 앞에 앱을 내놓는다. 신규 기능보다 정확성과 안정성이
  우선한다.
- **주요 Epic 후보** (2026-08-25 기준, 4개 Epic으로 실행): Epic K(Compliance & Release-Blocker
  Triage — MVP 체크리스트 재검증, Privacy Manifest, privacy policy 공개, App Store 개인정보 답변,
  OpenAPI current-vs-planned 정리); Epic L(Release-Blocking Correctness Gaps — 계정/데이터 삭제 +
  Apple Sign In 토큰 revocation, 알림 7일·48개 rolling window); Epic M(MetricKit crash/hang
  diagnostics, 최소 안전망); Epic N(TestFlight 수동 업로드 런북 + 실기기 검증 매트릭스). 각 PR이
  머지되는 대로 이 항목들의 상태를 갱신한다 — 지금은 진행 중.
- **In scope**: TestFlight internal + closed beta 배포; App Store Connect 메타데이터/개인정보 답변;
  `08`의 모든 출시 차단 조건 실기기 검증.
- **Out of scope**: insight, 제안형 알림, personalization 등 신규 제품 기능 — beta 기간에는 신규
  기능보다 정확성/UX 안정화를 우선한다.
- **Definition of Done**: `08`의 MVP 체크리스트 전체 체크; closed → expanded beta에서 P0 크래시
  없음.
- **운영 metric**: 크래시/오류율; Agent runtime 실패율; proposal 승인/거절 비율; latency(p50/p95
  turn time); 재시도율; onboarding/BYOK 연결 실패율; mutation 정확성(데이터 유실/중복 없음);
  알림 피로도(opt-out率); 주간 재방문율.
- **Decision gate — 크래시/오류 관찰 도구**: v1.0은 Sentry 같은 외부 observability SaaS를
  도입하지 않고 MetricKit(crash/hang diagnostic, 기기 로컬 로그만) + Xcode Organizer의 자동
  symbolicated crash report만으로 beta를 운영한다([`23-observability-and-alerting.md`](./23-observability-and-alerting.md)
  참고). beta 기간 동안 이걸로 실제 관찰 가능성 공백이 발견되면 그때 Sentry 도입 여부를 판단한다 —
  지금 미리 결정하지 않는다.
- **Gate to v1.1**: beta 지표가 최소 2주 연속 허용 범위 안에 있고 `08`의 모든 항목이 닫히면 Go
  (구체적 임계값은 실제 데이터가 쌓인 뒤 정한다 — 지금 숫자를 미리 정하는 것은 이 로드맵이 피하려는
  조기 확정과 같다).

## v1.1 — Weekly Insight

- **Product goal**: 진짜 유용하고 완전히 결정론적인(code 계산) 주간 요약. 아직 LLM 해석은 없고,
  실제 숫자를 명확하게 보여주는 것부터 — 이후 모든 버전이 기반으로 삼는 "Code = Truth"의 토대.
- **주요 Epic 후보**: 이미 스펙만 있고 구현되지 않은 `GET /insights/weekly`(PRD-105,
  `05-api-spec.yaml`, [`31-ui-backend-contract-audit.md`](./31-ui-backend-contract-audit.md)에
  "로컬 계산만 있음, 계약 보완 필요"로 표시됨) 구현 — 완료율, 반복 미완료 항목, 일정
  밀도/과밀, 루틴 유지율을 전부 SQL/code로 계산. 이를 보여줄 실제 화면(오늘의 `DailySummaryView`가
  가진 결정론적 다이제스트를 확장/대체하는, 이 방향의 가장 가까운 기존 선례).
- **In scope**: 실제 migration/RLS/테스트가 있는 서버 집계 endpoint; Agent 채팅 뒤에 숨기지 않은
  실제 UI 화면.
- **Out of scope**: LLM이 생성한 서술문; 여러 주에 걸친 추세 탐지(v1.2 영역); insight에 대한
  proactive 알림(사용자가 직접 화면을 열어야 함).
- **Definition of Done**: endpoint가 테스트와 함께 배포됨; UI가 렌더링함;
  `31-ui-backend-contract-audit.md`의 PRD-105 행이 done으로 갱신됨.
- **운영 metric**: 화면 오픈율; 화면 체류 시간; 화면을 연 것이 행동 변화와 상관관계가 있는지
  (v1.2를 위한 탐색적 신호이며, 아직 hard gate metric은 아님).
- **Gate to v1.2**: 실사용자가 유의미하게 이 화면을 사용하면 Go(임계값은 실제 데이터로 결정);
  만들었지만 사용되지 않으면 Hold(Pattern Signals를 사용되지 않는 화면 위에 짓기 전에 먼저
  화면 표현 방식을 개선); 이 낮은 리스크의 기초 단계에서 Drop 가능성은 낮다.

## v1.2 — Pattern Signals

- **Product goal**: 여전히 100% code/SQL, LLM 없음 — 여러 주에 걸친 단순하고 설명 가능한 패턴(예:
  요일별 완료 편향, 반복되는 과밀 구간)을 탐지해 v1.3의 LLM 해석을 위한 토대를 놓는다.
- **주요 Epic 후보**: 다주(multi-week) 집계 쿼리; 작고 설명 가능한 signal taxonomy(모든 signal이
  그것을 만든 실제 row까지 추적 가능해야 함 — 블랙박스 스코어링 없음).
- **In scope**: SQL 전용 계산; signal을 단순 통계/배지로 보여주는 UI.
- **Out of scope**: LLM 서술/설명(v1.3); 어떤 형태의 자동 액션도 없음.
- **Definition of Done**: 실제 과거 데이터에 대해 2~3개 signal 유형이 테스트와 함께 정확히 계산됨.
- **운영 metric**: signal 정확도(실제 수동 분석과 대조하는 개발자 spot-check — 1인 개발 규모에서
  받아들일 수 있는 검증 기준); signal UI에 대한 참여도.
- **Gate to v1.3**: signal이 정확/유용하다고 검증되고 v1.1이 Hold/Drop되지 않았을 때만 Go. signal이
  계산은 되지만 노이즈가 많거나 가치가 낮으면 Hold.

## v1.3 — Insight → Proposal

- **Product goal**: LLM의 *첫* 해석 역할 — v1.2의 결정론적 signal을 자연어 설명으로, 그리고
  적절한 경우 Epic C~J에서 이미 만든 `propose_*`/승인 패턴을 그대로 재사용하는 proposal로 바꾼다.
  예: "화요일마다 반복적으로 미루는 걸 봤어요, 알림 시간을 당겨볼까요?" → `propose_routine_update`.
- **Prerequisite, 아직 존재하지 않음 — Proposal Outcome Telemetry / Correlation(그 자체로 작은
  Epic)**: Epic H의 `agent_audit_log`는 **실행 관찰 가능성(execution observability)만** 제공한다
  (tool dispatch, latency, `result_kind`) — `approvalStatus`나 이후의 승인/거절 행동과의 상관관계는
  의도적으로 제외했다(Epic H의 설계 결정: Agent는 그 이후 별도로 일어나는 Command API 승인 호출을
  볼 수 없다). **v1.3의 핵심 metric인 proposal 승인율은 오늘 데이터로 존재하지 않으며, 이미 배포된
  어떤 것의 부산물도 아니다.** 이 prerequisite epic은 최소한 다음을 추적해야 한다: proposal
  rendered → approved / declined / approval-failed → proposal type → origin(`normal` vs.
  `insight-derived`) → 안정적인 correlation identifier. Epic H의 `agentRunId`를 그대로 이어 쓸지
  별도 proposal ID를 둘지는 그 Epic을 실제로 스코핑할 때 결정한다 — 여기서 미리 고정하지 않는다.
- **주요 Epic 후보**: 위의 Proposal Outcome Telemetry epic; Agent가 v1.2의 signal을 읽을 수 있는
  새 read tool(예: `get_pattern_signals`, `get_routine_preferences`/`get_review_history`와 동일한
  패턴); proposal은 **기존** `propose_*` tool만으로 staging — 새로운 mutation 표면 없음.
- **In scope**: 이미 계산된 signal에 대한 LLM 설명; 여전히 reactive — 사용자가 Agent/Insight
  화면을 직접 열어야 한다.
- **Out of scope**: 화면을 열지 않았는데 Agent가 알아서 proposal을 생성하는 것(v1.4의 영역).
- **Definition of Done**: proposal outcome telemetry가 실제로 존재하고 데이터가 쌓인다; 최소 하나의
  signal → 최소 하나의 proposal 유형이 승인/거절 추적까지 end-to-end로 연결된다.
- **운영 metric**: insight-derived proposal의 승인율을, 사용자가 직접 요청한 proposal의 기본
  승인율과 비교 — v1.4를 만들 가치가 있는지 판단하는 핵심 신호(이 metric은 위 prerequisite
  telemetry가 배포된 뒤에만 측정 가능하다).
- **Gate to v1.4**: **insight-derived 승인율이 실제 관찰 기간 동안 유의미하게 높으면 Go; 중간
  수준이면 Hold(무자극 전달을 만들기 전에 signal 품질/문구를 먼저 개선); 개선 후에도 승인율이
  낮게 유지되면 제안형 알림 자체를 Drop(영구히 reactive-only로 유지).**

## v1.4 — Limited Proactive Suggestions

- **Product goal**: v1.3의 gate가 Go일 때만 — 사용자가 앱을 먼저 열지 않아도 v1.3에서 검증된
  proposal을 알림이나 Today 화면의 인라인 카드로 보여준다. "Limited"란 rate-limit이 걸려 있고
  쉽게 끌 수 있으며, 결코 열린 결말의 엔진이 아니라는 뜻이다.
- **주요 Epic 후보**: 이미 존재하는 `NotificationScheduler` 인프라를 재사용하는 전달 메커니즘만;
  엄격한 rate limiting + proposal 유형별 opt-out.
- **In scope**: v1.3에서 이미 검증된 proposal 유형에 대한 전달.
- **Out of scope**: 열린 결말/잦은 제안; 검증되지 않은 제안 유형; 승인 없는 자율 실행(어떤
  버전에서도 절대 없음).
- **Definition of Done**: rate limiting과 opt-out을 갖춘 proactive 채널 1개가 배포됨; 알림
  피로도를 명시적으로 모니터링.
- **운영 metric**: v1.3의 reactive 기준선 대비 proactive 승인율(실제 위험: 같은 품질의 제안이라도
  자극 없이 전달되면 승인율이 낮아질 수 있다); opt-out率; 전체 알림 피로도 metric이 악화되지 않아야
  함.
- **Gate to v1.5**: proactive 승인율이 reactive 기준선과 충분히 가깝게 유지되고 피로도가
  악화되지 않으면 Go; 아니면 Hold/Drop(reactive-only로 축소).

## v1.5 — Personalization

- **Product goal**: 쌓인, *검증된* 승인 이력(원문 대화 기억이 아니라)을 사용해 사용자별로 어떤
  signal/proposal을 보여줄지 가중치를 둔다 — 예: "완료 처리" nudge를 절대 승인하지 않는 사용자는
  더 이상 그것을 받지 않는다.
- **주요 Epic 후보**: 기존 signal/proposal 유형 위에 얹는 가벼운 사용자별 가중치 레이어. v1.3의
  Proposal Outcome Telemetry 위에 구축되는, 실제 유형별 승인율 데이터로 구동되는 가중치다(Epic H
  단독으로는 실행 관찰 가능성일 뿐 outcome 데이터가 아니다 — v1.3 참고). 여전히 code가 가중치를
  결정하며, LLM은 이를 결정하지 않는다.
- **In scope**: 이미 추적된 승인/거절 이력에 대한 가중치 로직.
- **Out of scope**: 자유형 대화를 "기억하는" memory(v2.0의 영역).
- **Definition of Done**: 가중치가 실제 사용자별 승인 데이터를 근거로 어떤 유형이 노출되는지를
  측정 가능하게 바꾼다.
- **운영 metric**: 전체 승인율 추세(유지되거나 개선되어야 하며 악화되면 안 됨); 유형별 억제의
  정확성.
- **Gate to v2.0**: v1.1~v1.5가 종합적으로 실제 지속적인 사용 가치를 증명한 뒤에만 Go — v2.0은
  구조적으로 훨씬 큰 투자이므로 가장 큰 gate다.

## v2.0 — Long-term Personal OS / Memory

- **Product goal**: 유형별 승인 가중치를 넘어서는, 영속적이고 더 긴 시간축의 사용자 모델링. 다른
  모든 것이 먼저 검증된 뒤에 오도록 의도적으로 가장 뒤에 배치한 가장 구조적으로 위험한 버전이다.
- **주요 Epic 후보 / In scope / Out of scope / Definition of Done / metric / gate**: 여기서는
  의도적으로 **선설계하지 않는다** — 지금 설계하는 것 자체가 이 로드맵이 피하려는 "백로그를 전부
  미리 만든다"는 안티패턴이다. 명시적으로 미룬 것: 벡터 DB, 다중 Agent, 자유 자동 실행은 지금
  결정하지 않는다 — v2.0에서 실제로 필요하다면 그 시점에, 실제 v1.x 데이터를 근거로 결정한다.

## 이전 이력 (pre-v0.9)

이번 개정 전까지 이 문서가 추적하던 Phase 0~5 로드맵이다. `2026-08-17` 개발 종료 시점 기준
구현 현황을 그대로 보존한다 (이후 Epic C~J로 Phase 3의 Agent 파이프라인이 크게 확장됐다 — 위
v0.9 절 참고).

### Phase 0 — 기술 검증

SwiftUI 앱 / SwiftData Todo / 잠금화면 위젯 / App Group 스냅샷 / Universal Link / 로컬 알림 /
알림 액션.

### Phase 1 — 로컬 MVP

오늘 화면 / 빈 계획 상태 / 직접 일정 CRUD / 오전·오후·저녁·언제든 / 반복 일정 / 하루 요약 시간 /
미완료 일정 확인 / 테마 프리셋 / 위젯 개인정보 숨김.

### Phase 2 — 계정과 동기화

Google·GitHub 로그인과 iOS 심사용 Sign in with Apple / PostgreSQL / RLS / 커서 동기화 / 여러 기기 /
계정 및 데이터 삭제.

### Phase 3 — 선택적 AI

계획 초안 / 자연어 일정 변환 / 사용자 승인 commit / AI 데이터 범위 동의 / 실행 기록 / AI 기능
전체 끄기.

### Phase 4 — 뉴스

관심사 / 최신 기사 검색 / 출처와 원문 링크 / 3~5개 요약 / 브리핑 알림 / 뉴스 개인화 동의.

### Phase 5 — 외부 캘린더

EventKit / 바쁜 시간만 읽기 / 제목 읽기 선택 / 외부 일정 쓰기 별도 동의 / 충돌 안내.

### 출시 후 검토 (당시 항목)

주간 회고 / Apple Watch / App Shortcuts / 자체 MCP / 다른 AI 클라이언트 연결.

### 구현 현황 (2026-08-17 개발 종료 시점 기록, 보존)

- Phase 0~2: 완료.
- Phase 3(선택적 AI): 완료. 계획 초안·자연어 일정 변환·사용자 승인 commit·AI 기능 끄기까지 온디바이스
  Agent(FoundationModels)와 클라우드 Agent(사용자 BYOK OpenRouter) 두 경로로 구현했다. AI 데이터
  범위 동의와 실행 기록은 서버 `agent_chat_requests` rate-limit 로그로 남는다.
- Phase 4(뉴스): 완료. 다만 서버 파이프라인이 아니라 iOS가 RSS를 직접 수집하고 온디바이스로 요약한다
  ([`10-decisions-and-open-questions.md`](10-decisions-and-open-questions.md) ADR-074).
- Phase 5(외부 캘린더): Google Calendar 읽기 전용 미러만 완료(바쁜 시간·제목 읽기, 출처 배지, Today
  통합 타임라인). EventKit(Apple Calendar) 연동과 외부 일정 쓰기는 만들지 않았다.
- 출시 후 검토 항목(주간 회고, Apple Watch, App Shortcuts, 자체 MCP, 다른 AI 클라이언트 연결)은
  이번 개발 범위에 포함하지 않았다. 자체 MCP는 [`21-integration-hub-google-calendar-mcp.md`](21-integration-hub-google-calendar-mcp.md)의
  Phase C로 설계만 남아 있다.
- Slack은 이 문서에 별도 Phase로 없었지만 실제로는 구현했다 — OAuth가 아닌 Incoming Webhook 방식
  (ADR-075).

## 만들지 않을 것

- 다중 Agent
- 외부 벡터 DB(pgvector 이외)
- 자유 배치 UI 편집기
- 조직 협업
- 프로젝트 관리
- 센서 기반 완료 추측
- 사용자 승인 없는 자동 삭제
