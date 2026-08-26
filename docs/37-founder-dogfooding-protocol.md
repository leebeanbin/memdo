# 37. Founder Dogfooding Protocol (Personal Team, 3–4 weeks)

> 실행 환경(브랜치/설치 절차): [`36-personal-team-dogfood-setup.md`](./36-personal-team-dogfood-setup.md)
> 이후 단계(Internal Dogfooding/Closed Beta/Expanded Beta): [`08-test-and-release-plan.md`§9](./08-test-and-release-plan.md#9-출시-검증-단계-release-validation-stages)
> 로드맵 위치: [`09-roadmap-and-backlog.md`](./09-roadmap-and-backlog.md)
> UI/UX 감사 기준: [`33-experience-roadmap.md`](./33-experience-roadmap.md)
> 매일 채워 넣는 실제 로그 파일: [`dogfood-log.md`](./dogfood-log.md)

## 이 문서가 존재하는 이유

`08` §9는 이미 TestFlight 이후의 검증 단계(Internal Dogfooding → Closed Beta → Expanded Beta)를
정의하고 있다. 이 문서는 그 **앞**에 새로 추가되는 단계 — Apple Developer Program 등록 전, 무료
Personal Team으로 개발자 본인 기기에서 3~4주간 실사용하는 기간 — 의 프로토콜만 다룬다. 목적은
"그냥 써보기"가 아니라 실제 product-validation 사이클로 만드는 것: 무엇이 깨지는지, 무엇이
불편한지, 실제로 쓰는 기능이 뭔지, Agent가 실제로 유용한지, 알림이 성가신지, 그리고 어떤 아이디어가
v1.0 버그이고 어떤 게 v1.1+ 기능 요청인지를 구분해서 기록한다.

이 기간 동안 **신규 기능 개발은 하지 않는다** — v1.0의 "beta 기간에는 신규 기능보다 정확성/UX
안정화를 우선한다" 원칙이 이 단계에도 동일하게 적용된다(`09`).

## Personal Team 빌드에서 사용 불가능한 항목 (dogfood 실패가 아님)

아래 항목은 `36-personal-team-dogfood-setup.md`에서 이미 의도적으로 제외한 기능이다. 이 기간 동안
관찰되지 않거나 동작하지 않아도 **버그로 기록하지 않는다** — Release/TestFlight 단계(`08` §9의
Internal Dogfooding 이후)에서 별도로 검증한다.

- Widget
- Share Extension
- Live Activities
- Sign in with Apple / Apple revoke 경로
- TestFlight/Xcode Organizer 전용 검증(실제 배포된 빌드의 crash symbolication 등)

## 1. Baseline Smoke Pass (1회, 일상 사용 시작 전)

Personal Team 빌드를 처음 설치한 직후, 정상적인 일상 사용을 시작하기 전에 아래를 순서대로 1회
확인한다. 실패 항목은 dogfooding을 시작하기 전에 먼저 해결한다(P0로 취급).

```text
[ ] 앱 최초 실행 → 인증 상태(로그인/게스트) 정상 진입
[ ] Google OAuth 로그인 왕복 성공
[ ] GitHub OAuth 로그인 왕복 성공
[ ] 오늘 화면 / 캘린더 화면 / 설정 화면 정상 표시
[ ] 일정 생성 → 수정 → 완료 처리 → 삭제 각각 정상 동작
[ ] 오프라인 상태에서 mutation 생성 → 온라인 복귀 → 정상 동기화
[ ] 로컬 알림 최소 1건 예약·전달 확인
[ ] 알림 7일·48개 rolling window: 다수 일정 등록 후 오래된/먼 알림이 정리되는지 확인
[ ] memdo:// 딥링크(알림 탭 → 상세 화면 라우팅) 정상 동작
[ ] 클라우드 Agent(OpenRouter BYOK 연결) 정상 응답
[ ] 온디바이스 Agent(지원 기기에서) 정상 응답
[ ] 루틴/리뷰 proposal 흐름(제안 → 승인/거절) 정상 동작
[ ] clarification 흐름(Agent가 모호한 요청에 되묻는 상태) 정상 동작
[ ] 계정 삭제(Google/GitHub 등 non-Apple 계정, 가능하면 별도 테스트 계정으로) 정상 동작
[ ] 백그라운드 → 포그라운드 복귀 시 알림 reconciliation 재실행 확인(scenePhase 활성화 훅)
[ ] MetricKit: MetricsCollector 초기화가 크래시 없이 완료됨(로컬에서 실제 diagnostic 수신은
    관찰 불가 — 초기화 자체만 확인, `08` §9.4 참고)
```

이 체크리스트를 통과하면 정상적인 일상 사용을 시작한다. 매일 다시 실행할 필요는 없다 — Baseline은
1회성이다.

## 2. Daily Observation Log

실제로 채워 넣을 파일은 [`dogfood-log.md`](./dogfood-log.md)다. 형식은 최대한 가볍게 유지한다 —
매 항목마다 아래 필드를 채운다(마크다운 테이블 한 줄 또는 짧은 블록, 편한 쪽으로):

- **날짜/시각**
- **카테고리** — 다음 7개 중 하나: `BUG` / `UX_FRICTION` / `AGENT_QUALITY` / `PERFORMANCE` /
  `NOTIFICATION` / `FEATURE_IDEA` / `DATA_INTEGRITY`
- **맥락** — 무엇을 하려고 했는지
- **기대 동작**
- **실제 동작**
- **심각도** — P0(데이터 유실/크래시/핵심 흐름 완전 차단) / P1(반복적으로 불편하지만 우회 가능) /
  P2(사소함)
- **재현 가능?** — yes / no / unknown
- **스크린샷/로그/참고** — 있으면만
- **임시 우회 방법** — 있으면만

`FEATURE_IDEA`는 그 자리에서 구현하지 않는다 — 기록만 하고 넘어간다(§4 참고). 완벽하게 채우지
못해도 괜찮다 — 필드가 비어 있는 것보다 항목 자체를 안 남기는 게 더 큰 손실이다.

## 3. Issue Triage Policy

기록된 항목은 아래 규칙으로 분류한다. 목적은 "쓰다가 떠오른 멋진 기능"이 안정화 기간을 다시 기능
개발로 되돌리는 것을 막는 것이다.

| 조건 | 처리 |
|---|---|
| P0/P1 정확성 문제, 데이터 유실, 크래시, 핵심 흐름 완전 차단 | **dogfooding 중 즉시 수정** |
| 반복적으로 발생하는 UX friction이 정상 사용을 방해함 | v1.0 polish 후보 — 주간 리뷰에서 우선순위 결정 |
| 시각/모션 polish이되 워크플로에 영향 없음 | Experience 백로그(`33`)로 — 사소하고 명백히 안전한 경우만 예외적으로 즉시 반영 |
| 새로운 기능/스코프 확장 | v1.1+ 백로그로 이동, **이번 기간에 구현하지 않음** |
| 추측성 AI 아이디어("이런 것도 하면 좋겠다") | 즉시 구현 금지 — `dogfood-log.md`에 `FEATURE_IDEA`로만 기록하고 근거(실제 반복 관찰) 축적 대기 |

## 4. Weekly Review (20–30분)

매주 한 번, `dogfood-log.md`를 훑으며 아래를 집계한다:

- 심각도별 미해결 버그
- 반복되는 UX friction
- Agent 실패 / clarification 오작동 사례
- 알림 피로도(성가시다고 느낀 빈도)
- 지연/성능 관찰
- 전혀 안 쓴 기능
- 반복적으로 쓴 기능
- 수집했지만 의도적으로 보류한 feature idea 목록

각 항목은 다음 넷 중 하나의 결정으로 끝나야 한다:

- **fix now** — 이번 주 안에 수정
- **observe another week** — 아직 패턴이 불확실, 한 주 더 관찰
- **defer to v1.1+** — 스코프 확장이 명확함, 백로그로 이동
- **drop** — 근거 부족 또는 가치 낮음

리뷰 결과(결정 + 근거 한 줄)를 `dogfood-log.md`의 "Weekly Review" 절에 날짜별로 추가한다.

## 5. Dogfood Exit Gate

아래 조건이 **모두** 충족되면 이 단계를 종료하고 `08` §9의 릴리스 로드맵(Apple Developer Program
등록 → TestFlight → Internal Dogfooding → Closed Beta → Expanded Beta)으로 넘어간다. 지금 시점에
근거 없는 숫자 임계값(예: "P1 몇 건 이하")은 정하지 않는다 — `08`/`09`가 이미 따르는 원칙과 동일하게,
실제 dogfooding 기간의 증거로 판단한다.

```text
[ ] 미해결 P0 없음
[ ] 알려진 data-loss 이슈 없음
[ ] 반복적으로 실패하는 핵심 워크플로 없음
[ ] 알림 시스템이 일상 사용에 충분히 신뢰할 수 있게 동작함
[ ] OAuth/sync/BYOK 핵심 경로가 안정적으로 유지됨
[ ] Agent 실패 사례가 파악되었고, 수정되었거나 명시적으로 허용 가능하다고 판단됨
[ ] UX 이슈가 v1.0 polish 대상과 Experience/v1.1 백로그로 모두 triage 완료됨
```

이 gate를 통과하면 `08` §9.1의 순서에 "0. Personal Team Founder Dogfooding"이 선행 단계로
포함되어 있음을 확인하고, Apple Developer Program 등록(`35-testflight-release-runbook.md` §0)으로
진행한다.

## 6. UI/UX 관찰 체크리스트 (Experience 근거 수집용)

`33-experience-roadmap.md`의 Experience v1.0(Interaction Polish) 감사가 참고할 실사용 근거를
모으는 목적이다. **이 기간 동안 새 motion 시스템을 만들지 않는다** — 관찰하고
`dogfood-log.md`에 `UX_FRICTION`으로 기록하는 것까지만 한다.

- 정보 위계/가독성
- 탭 타겟 크기·상호작용 마찰
- empty/loading/error state
- 카드 전환(transition) 자연스러움
- approve/decline 피드백의 명확성
- Agent presence/tool-phase 피드백(`isToolPhase`/`toolHint`)이 실제 진행 상황과 일치하는지
- Reduce Motion 켰을 때 커스텀 opacity/scale이 실제로 꺼지는지
- Haptic 일관성(같은 종류의 액션에 같은 haptic이 오는지)
