# Experience 로드맵

> 제품 기능 로드맵: [로드맵과 백로그](./09-roadmap-and-backlog.md)
> 계약 수준 디자인 규칙: [디자인 시스템·밀도·Agent UI 계약](./28-design-system-density-and-agent-ui.md)
> 구현 수준 규칙: [iOS DESIGN](../apps/ios/Memdo/DESIGN.md)

## 이 문서가 존재하는 이유

[`28-design-system-density-and-agent-ui.md`](./28-design-system-density-and-agent-ui.md)는 계약
감사 문서이고, `apps/ios/Memdo/DESIGN.md`는 이미 구현된 화면별 규칙을 기록한 문서다. 둘 다 미래
방향을 버전 단위로 계획하는 로드맵이 아니다. 이 문서는 UI/UX를 [`09-roadmap-and-backlog.md`](./09-roadmap-and-backlog.md)의
제품 기능 버전과는 **독립된 번호 체계**로 계획한다 — Experience v1.x는 제품 v1.x와 나란히
진행되지 않는다. 각 Experience 버전이 실제로 어떤 제품 버전에 의존하는지는 아래에 개별적으로
명시한다.

## 원칙

- 장식용 motion보다 **상태 전이와 원인·결과를 사용자가 이해하도록 하는 motion**을 우선한다.
- **실제 내부 이벤트가 없는데 "검색 중", "분석 중"처럼 보이게 하는 fake progress UI는 절대 만들지
  않는다.** Agent 활동 UI는 항상 실제 tool/runtime state에 연결된 신호만 보여준다.
- 새 규칙을 발명하기 전에 기존 규칙([`28`](./28-design-system-density-and-agent-ui.md)과
  `DESIGN.md`)을 먼저 감사한다 — 이미 있는 규칙을 무시하고 처음부터 다시 설계하지 않는다.

## Experience v1.0 — Interaction Polish

- **Product goal**: 새 motion을 발명하지 않고, 이미 있는 전환·피드백이 실제로 `DESIGN.md`의
  규칙을 지키는지 감사하고 빠진 곳을 채운다.
- **감사 대상(이미 실재함, 확인됨)**: `AgentComponents.swift`의 proposal 카드
  `.transition(.asymmetric(...))` 4곳; approve/decline 피드백; 일정 생성/완료/재조정 motion;
  loading/error/empty state; `DESIGN.md`가 이미 명시한 `accessibilityReduceMotion`에서 커스텀
  opacity/scale 제거, VoiceOver 커스텀 액션(예: "하루 일정 메뉴 열기"), 모달 초점 이동 규칙과의
  실제 구현 일치 여부.
- **In scope**: 기존 규칙 대비 구현 감사, 불일치 수정.
- **Out of scope**: 새 motion vocabulary 발명(v1.1의 영역).
- **의존성**: 없음 — 지금 바로 시작 가능. 제품 v0.9/v1.0 시기와 자연스럽게 맞물린다(Agent UI가
  이미 이번 세션에서 크게 확장됐으므로).

## Experience v1.1 — Motion Language

- **Product goal**: 오늘 존재하지 않는 것을 실제로 정의한다 — 확인 결과 spring 파라미터/duration
  tier/haptic taxonomy를 한곳에 모은 문서는 현재 어디에도 없다(`28`은 계약 수준 제약만, `DESIGN.md`는
  화면별 개별 규칙만 가짐). scale vs. opacity vs. slide를 언제 쓸지, 일관된 haptic taxonomy
  (light/medium/success/error)를 정의한다.
- **In scope**: 새 vocabulary 문서화, 기존 화면에 점진 적용.
- **Out of scope**: Agent 전용 활동 UI(v1.2의 영역).
- **의존성**: v1.0의 감사 결과 위에서 작업 — 감사 없이 vocabulary부터 만들면 이미 있는 좋은
  패턴을 놓칠 수 있다.

## Experience v1.2 — Agent Presence

- **Product goal**: 실제 tool/runtime state에 연결된 Agent 활동 UI. `AgentResponse`가 이미 가진
  `isToolPhase`/`message.toolHint`(`AgentComponents.swift`/`AssistantView.swift`에 실재함, 예:
  `"일정을 제안하는 중..."`)를 확장하는 것이지, 병렬 시스템을 새로 만드는 게 아니다.
- **명시적 제약(문서에 그대로 남긴다)**: 실제로 진행 중인 이벤트가 뒷받침하지 않는 "검색 중"/
  "분석 중" 같은 진행 텍스트는 절대 보여주지 않는다 — fake progress UI 금지.
- **In scope**: `toolHint`가 실제 tool dispatch 이벤트와 1:1로 대응하는지 감사·보강; clarification
  UI state(Epic J)의 시각적 표현이 이 vocabulary를 따르는지 확인.
- **Out of scope**: 새로운 tool phase 텍스트를 실제 이벤트 없이 추가.
- **의존성**: v1.1의 motion vocabulary. 제품 쪽으로는 Epic J(clarification UI state)와 자연스럽게
  맞물린다 — 제품 v1.2(Pattern Signals)가 아니라 이미 완료된 Agent 작업(v0.9 시기)과 짝을
  이룬다는 점에 주의: 번호가 같다고 제품 v1.2와 나란히 진행되는 게 아니다.

## Experience v1.3 — Insight Visualization

- **Product goal**: [`09`](./09-roadmap-and-backlog.md)의 v1.1(Weekly Insight)/v1.2(Pattern
  Signals)이 실제로 계산한 데이터가 있어야만 의미가 있는 sparkline/heatmap 스타일 시각화.
- **In scope**: 실제 계산된 수치만 시각화 — "Code = Truth" 원칙은 시각화에도 동일하게 적용된다.
  장식용 가짜 차트는 만들지 않는다.
- **Out of scope**: 제품 v1.1/v1.2가 실제로 데이터를 계산하기 전에 시각화부터 만드는 것.
- **의존성**: 제품 v1.1(Weekly Insight)의 실제 데이터 없이는 시작할 수 없다 — 이 버전만은 제품
  로드맵과 직접적인 순서 의존성을 가진다(다른 Experience 버전과 달리).
