# Founder Dogfood Log

> 형식/규칙: [`37-founder-dogfooding-protocol.md`](./37-founder-dogfooding-protocol.md)
> 매일 이 파일 맨 아래(Entries)에 새 항목을 추가한다. 완벽하게 채우지 않아도 된다 — 비워도 되는
> 필드는 비워 두고, 항목 자체를 기록하는 것을 우선한다.

카테고리: `BUG` / `UX_FRICTION` / `AGENT_QUALITY` / `PERFORMANCE` / `NOTIFICATION` /
`FEATURE_IDEA` / `DATA_INTEGRITY`
심각도: `P0`(데이터 유실/크래시/핵심 흐름 차단) / `P1`(반복 불편, 우회 가능) / `P2`(사소함)

## Baseline Smoke Pass 결과

> `37` §1의 체크리스트를 1회 실행한 날짜와 결과를 여기에 기록.

- 날짜:
- 결과: (전항목 통과 / 실패 항목 목록)

---

## Entries

<!--
항목 템플릿 (복사해서 사용):

### YYYY-MM-DD HH:MM — [CATEGORY]
- 맥락:
- 기대 동작:
- 실제 동작:
- 심각도:
- 재현 가능: yes / no / unknown
- 참고(스크린샷/로그):
- 임시 우회:
-->

### 2026-08-26 — [BUG]
- 맥락: 시간을 넣어 일정 추가 후 "하루 정리"(오늘 요약) 화면 확인
- 기대 동작: 방금 추가한 일정이 요약에 나타나야 함
- 실제 동작: 나타나지 않음 — 처음엔 동기화가 안 되는 것처럼 보였음
- 원인: `DailySummaryView.swift`가 `kind == .task`(시간 없는 할 일)만 필터링해서, 시간이
  있는 `.event` 항목을 전부 제외하고 있었음. `docs/07` §5 스펙 기준으로는 kind 제한이 없어야
  하는 게 맞음 — 구현 drift.
- 심각도: P1(핵심 화면이 대부분의 실제 사용 사례에서 빈 결과를 보여줌)
- 재현 가능: yes
- 조치: 수정 완료, PR #36 (`fix/daily-summary-include-events`)

### 2026-08-26 — [BUG]
- 맥락: 위 항목 수정 확인 중 — 일정은 "하루 정리" 모달 안에 나타났지만, 오늘 화면 상단의
  "0/0 완료" 링/진행률이 그대로였음
- 기대 동작: 시간 있는 일정을 완료 처리하면 상단 링/진행률도 갱신되어야 함
- 실제 동작: 갱신 안 됨
- 원인: 동일 근본 원인 — `TodayView.swift`의 `completedCount`/`taskCount`도
  `kind == .task`만 필터링하고 있었음(별도 위치에서 같은 패턴이 중복 구현됨). `schedules`
  자체는 이미 `isActive` 기준으로 필터링된 상태라 kind 필터는 순수 과잉 제한이었음.
- 심각도: P1
- 재현 가능: yes
- 조치: 수정 완료, 같은 PR #36에 포함

### 2026-08-26 — [BUG] [DATA_INTEGRITY]
- 맥락: "하루 정리"에 새로 추가한 완료 취소 버튼을 실기기에서 테스트 — 버튼은 눌리는데(호버
  반응) 실제로 완료 취소가 안 됨
- 기대 동작: 탭하면 완료 취소되고 DB에도 반영되어야 함
- 실제 동작: 아무 일도 안 일어남
- 원인: `ScheduleModel.swift`의 `toggleDone(id:)`에 `kind == .task` guard가 있어서
  `.event` 종류 항목은 `save()` 호출 전에 조기 리턴 — **DB 쓰기 자체가 시도되지 않음**(UI
  버그가 아니라 데이터 계층 버그). 반면 기존 "완료" 버튼(`DailySummaryView.complete`)은 kind
  체크 없이 `save()`를 직접 호출해서 이벤트도 완료 처리는 됐었음 — 즉 "완료는 되는데 취소만
  안 되는" 비대칭이 이미 존재했고, 이번에 되돌리기 버튼을 추가하면서 드러남.
- 심각도: P1(데이터 자체는 안전하지만 사용자가 되돌릴 방법이 전혀 없었음)
- 재현 가능: yes
- 조치: 수정 완료, 같은 PR #36에 포함(guard 제거)
- 별도 논의 필요(구현 안 함): `ScheduleRow.swift`의 메인 Today/캘린더 목록에서는 `.event`
  종류 항목에 아예 체크마크가 안 뜨고(시간 아이콘만), 오직 "하루 정리" 화면에서만 이벤트를
  완료/취소할 수 있음 — 메인 화면에서도 이벤트 완료 토글을 노출할지는 디자인 결정이 필요해서
  구현하지 않음, `33` Experience 백로그 후보로 기록.

### 2026-08-26 — [UX_FRICTION]
- 맥락: "오늘"/"지난 7일"/"지난 30일" 세 스코프를 오가며 확인
- 내용: 제목 톤(하루 정리 vs 지난 N일), eyebrow 라벨, 진행률 단어(확인 vs 놓침), 섹션
  순서(미완료→완료 vs 완료→미완료), 미완료 액션 세트(오늘만 "내일로 이동" 있음), "일정 분석"
  문장 템플릿까지 스코프별로 전부 따로 만들어져 통일감이 없음
- 판단: 사용자 확인 결과 지금은 우선순위 낮음("무시해도 될 것 같다") — 구현 보류.
  `33-experience-roadmap.md` Experience 백로그 후보로 기록. 제안(나중에 참고): 제목 톤 통일,
  섹션 순서 통일, 미완료 액션 세트 통일 정도면 큰 재설계 없이 일관성 확보 가능해 보임.

### 2026-08-26 — [BUG]
- 맥락: 오늘 새로 만든 일정이 "지난 7일"/"지난 30일" 탭에도 나와야 하는 것 아니냐는 질문에서
  발견
- 기대 동작: 오늘 생성한 일정이 "지난 7일"/"지난 30일"에도 포함되어야 함(오늘 포함 rolling
  window가 자연스러움)
- 실제 동작: 오늘 것은 항상 빠짐
- 원인: `SummaryScope.week`/`.month`의 `interval(endingAt:)`가 `end: startOfDay`(오늘
  자정)였는데 필터가 `< end`(미만)라서 오늘 항목이 정확히 경계에서 제외됨. 순수 경계값 계산
  실수(이 화면 자체가 docs/07엔 없는 기능이라 스펙 위반은 아님).
- 심각도: P2(데이터 유실은 아니지만 최근 항목이 안 보임)
- 재현 가능: yes
- 조치: 수정 완료 — 오늘 포함 정확히 7일/30일이 되도록 시작일도 함께 조정(`-7`→`-6`,
  `-30`→`-29`), 경계값 회귀 테스트(`testWeekAndMonthIntervalsIncludeToday`) 추가, 같은 PR
  #36에 포함.

### 2026-08-26 — [BUG]
- 맥락: Google OAuth 액세스 거부 이슈 해결(Google Cloud Console에서 비활성화된 키 재활성화 —
  코드 문제 아니었음) 후, 설정 화면 계정 섹션을 게스트 모드에서 확인
- 기대 동작: 게스트(비로그인) 상태에서는 "게스트 로그아웃"만 보여야 함(실제 계정이 없으므로)
- 실제 동작: "계정 삭제" 버튼도 함께 노출됨
- 원인: `SettingsView.swift`의 `session.phase == .guest` 분기 밖에 "계정 삭제" 버튼이
  무조건 배치되어 있었음. 게스트 로그아웃이 이미 동일한 결과(로컬 데이터 전체 삭제, 동일 경고
  문구)를 제공하는데, 계정 삭제는 추가로 백엔드 `DELETE /account`(Apple revoke 등 게스트에
  무의미한 경로 포함)까지 호출하는 구조라 중복이자 혼란스러운 노출.
- 심각도: P2(데이터 손실 위험은 낮음 — 게스트 삭제도 데이터를 지우긴 함 — 이지만 UX 혼란)
- 재현 가능: yes
- 조치: 수정 완료, `session.phase != .guest`로 스코프 제한, PR #37
  (`fix/settings-hide-delete-account-for-guest`)

### 2026-08-26 — [FEATURE_IDEA]
- 맥락: 전체 화면 상단에 화면 제목이 크게 표시되는 현재 패턴에 대해, 로고로 대체하면 어떨지 문의
- 내용: 제목 텍스트 대신/추가로 앱 로고를 헤더에 노출하는 방안
- 판단: 즉시 구현하지 않음 — dogfooding 기간 중 신규 디자인 시스템 도입 금지 원칙(`37`)에 따라
  보류. 화면 제목은 네비게이션 컨텍스트(현재 어느 화면인지) 전달 역할이 커서, 로고로 전면 대체는
  비권장 의견 제시함(대신 안: 홈 화면 등 특정 앵커 지점에 로고를 제목과 함께/별도로 배치).
- 다음 단계: `33-experience-roadmap.md`의 Experience 백로그 후보로 남겨두고, weekly review에서
  재논의.

### 2026-08-26 — [BUG] [DATA_INTEGRITY]
- 맥락: Google 로그인 시도 시 "액세스 차단됨: 401 invalid_client — The OAuth client was not
  found" 발생. 처음엔 Google Cloud Console의 비활성화된 키 문제로 오판(재활성화했지만 근본
  원인 아니었음).
- 실제 원인: Supabase Dashboard → Authentication → Providers → Google/GitHub의 Client
  ID/Secret 필드에 **실제 값이 아니라 `env(SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID)` 같은
  리터럴 문자열이 그대로 저장**되어 있었음. `config.toml`의 `env(...)` 문법은 로컬 CLI 전용이고,
  `supabase config push`가 원격에 반영할 때 명령을 실행한 셸의 환경변수로 치환해야 하는데, 셸에
  해당 env var가 없는 상태로 push된 것으로 추정됨.
- **이 세션 이전 기록과의 연결**: 이 세션 초반에 프로덕션 프로젝트에 대해 `supabase
  --experimental config push`를 관련 env var 미설정 상태로 2회 실행한 사건이 있었고, 당시
  대시보드 확인으로 "문제 없음"이라 결론 내렸으나 — 이번에 실제 값이 `env(...)` 리터럴로 저장돼
  있는 게 확인되면서, 그때 놓친 실제 피해였을 가능성이 높음.
- 심각도: **P0**(Google/GitHub 로그인 자체가 완전히 차단된 상태 — 신규 사용자 온보딩 핵심 경로
  전체 불능)
- 재현 가능: yes(발견 당시)
- 조치: 사용자가 Supabase Dashboard에서 Google/GitHub 양쪽 Client ID/Secret을 실제 값으로
  직접 교체 완료(2026-08-26). 코드 변경 없음 — 순수 프로덕션 설정 문제였음. 이후 코드 exchange
  단계(`Unable to exchange external code`)까지는 진행되어 client_id 문제 자체는 해결 확인.
  전체 로그인 왕복 최종 확인은 진행 중.
- 재발 방지 아이디어(구현 안 함): 향후 `config push` 실행 전 관련 env var가 실제 설정돼 있는지
  사전 확인하는 절차/스크립트를 만들지 검토 가치 있음 — 지금은 기록만.

### 2026-08-26 — [UX_FRICTION]
- 맥락: 게스트 모드 설정 화면에 "로그아웃"이 떠 있는 게 혼란스럽다는 지적
- 판단: 실제 문제 맞음 — 로그인한 적 없는 게스트에게 "로그아웃"은 부적절한 용어. 실제로는
  익명 세션+로컬 데이터를 초기화하는 기능이라 "게스트 데이터 초기화"로 라벨/확인 다이얼로그
  전부 변경.
- 조치: 수정 완료, PR #38 (`fix/settings-guest-logout-label`)

### 2026-08-27 — [BUG] [PERFORMANCE]
- 맥락: 이번 dogfooding 세션 전체 diff(`2614710^..78c8afb`)에 대해 multi-angle 코드 리뷰
  실행 — 10개 발견, 5개는 즉시 수정(PR #43), 5개는 제품 판단이 필요해 보류
- 즉시 수정된 것: Agent "완료" 액션이 여전히 `kind == .task`로 막혀 있던 것(toggleDone은
  이미 수정됐는데 Agent 경로만 안 따라감), `scheduleReminder`/`scheduleEndNotification`에
  남아있던 동일한 silent `try?` 패턴, pending count 로그가 memdo.* 외 알림까지 세던 것,
  `SummaryHistoryRow`의 VoiceOver title/subtitle 페어링 소실, `.interactive()` 제거가
  공유 modifier 레벨이라 무관한 버튼(WallpaperPreviewSheet)까지 영향받던 것
- 보류(제품 판단 필요, 로그만):
  1. `toggleDone`이 빠르게 두 번 탭하면 `pendingWriteIDs` guard 때문에 두 번째 탭이
     조용히 무시되고 첫 번째 네트워크 응답이 나중에 도착해서 되돌릴 수 있음(race condition)
  2. `ScheduleRow`(메인 Today 목록)는 여전히 이벤트에 체크마크 자체가 없음 — 이미 8/26
     항목에서 별도 논의 필요로 기록된 것과 동일 이슈
  3. 시뮬레이터 온디바이스 Agent 멈춤에 대한 수정이 플랫폼 분기(`#if targetEnvironment
     (simulator)`)뿐이라, 실기기에서 같은 현상(tool 호출 후 완료 시그널 안 옴)이 나면
     막을 방법이 없음 — 일반적인 timeout/watchdog은 별도 기능 단위 작업
  4. `SummaryHistoryRow`/`SummaryReviewRow`의 편집/삭제 메뉴 코드가 거의 동일하게
     중복됨 — 공유 컴포넌트로 뽑을 수 있음(리팩터, 버그 아님)
  5. 게스트 계정삭제 숨김(PR #37)이 클라이언트 UI 레벨뿐 — 백엔드 `DELETE /account`가
     익명 세션을 서버 측에서 별도 처리하지 않는 것도 확인됨(코드에 `is_anonymous`
     분기 없음). 추가로 발견: 게스트 "데이터 초기화"는 `client.auth.signOut()`만 호출해서
     로컬 세션만 지우고, 서버의 익명 사용자 row는 실제로 삭제되지 않음 — 익명 사용자가
     DB에 무기한 누적되는 별도의 데이터 위생 문제. 백엔드 정리 정책(예: 일정 기간 미접속
     익명 계정 자동 삭제) 결정이 필요.

### 2026-08-28 22:58 — [AGENT_QUALITY]
- 맥락: 유료 모델(`qwen/qwen3.7-flash`)로 Agent 채팅 중 "그러면 내 빈 일정이 언제 있고,
  독서실 내일 오후 9시부터 11시까지 있을거야"라고 입력 — 빈 시간 질문과 새 일정 언급이
  한 메시지에 섞인 복합 요청.
- 기대 동작: `find_free_slots`로 실제 빈 시간을 확인하고, "독서실"은 존재 여부가 확인되지
  않았으므로 추가할지 물어보거나 `propose_schedule`을 제안해야 함.
- 실제 동작: `search_schedules({from: "2026-08-29", to: "2026-08-29"})`만 호출했고 결과는
  `{"count": 0}`(해당 날짜 일정 없음)이었는데도, 최종 답변은 "내일(8/29)은 오후 9시부터
  11시까지 독서실 일정이 잡혀 있습니다"라고 답함 — 자기 tool 결과와 정반대되는 내용을
  지어냄(hallucination). `find_free_slots`는 끝내 호출되지 않음.
- 원인: `agent-cloud-contract.ts`의 `systemPrompt()`에 (1) tool 결과에 없는 항목의 존재를
  단정하지 말라는 grounding 규칙이 없었고, (2) 한 메시지에 여러 요청이 섞였을 때 각각을
  독립적으로 처리하라는 지시가 없었음. Founder debug trace(D2, 앱 내 "디버그 추적 복사")로
  실제 tool 호출/결과를 직접 확인해 재현·근거를 확보함.
- 심각도: P1(function-calling 배관 자체는 정상이지만, 답변이 자기가 방금 받은 데이터를
  무시하고 반대로 말함 — Agent 신뢰성 핵심 문제)
- 재현 가능: yes
- 참고(스크린샷/로그): 디버그 추적 — `requested/resolved: qwen/qwen3.7-flash,
  intent: searchSchedules, tool calls: [search_schedules({from:"2026-08-29",
  to:"2026-08-29"}) -> {"count":0}]`
- 조치: `memdo-backend`의 `systemPrompt()`에 두 directive 추가 — (a) grounding: 현재 turn의
  *성공한* authoritative tool 결과만 근거로 인정하고(대화 기록/사용자 발화/실패 결과는
  근거 아님), `propose_schedule`/`propose_schedule_update`의 성공 결과도 "생성/변경
  확정"의 근거가 아니라 승인 대기 staging일 뿐임을 명시. (b) compound-message: 한 부분이
  `request_clarification`이 필요해도 나머지 실행 가능한 부분(예: `find_free_slots`)은
  그대로 처리. `memdo-backend` PR #22 (`fix/agent-grounding-directive`, 커밋 `4b50c4d` +
  리뷰 보완 `7fecfd0`), merge 완료(`main` `8377dc9`), 배포(`deploy-supabase.yml`) 성공 확인.
- 남은 검증: 배포된 상태로 Simulator에서 동일 메시지 + 동일 모델로 재현, 다음 세 기준을
  독립적으로 확인 예정(아직 미완료) — Routing(`find_free_slots` 실제 호출 여부),
  Grounding(허위 존재 주장 재발 여부), Compound handling(두 intent 중 하나도 조용히
  누락되지 않는지).
- 후속(이번 라운드 범위 밖으로 명시적으로 미룸): identity를 `personal schedule assistant`
  에서 `personal planning assistant`로 일반화, `intended → proposed → confirmed` 상태
  경계 명문화, Schedule/Task 분류 기준, clarification을 필수 정보에만 쓰도록 제한, 모든
  create 전 `search_schedules` 강제 규칙 재검토, Reminder/Plan용 authoritative
  read/propose/update capability 추가.

---

## Weekly Review

> `37` §4 형식: 날짜, 집계 요약, 각 항목의 결정(fix now / observe another week / defer to v1.1+ / drop) + 근거 한 줄.

<!--
### Week of YYYY-MM-DD
- 요약:
- 결정:
-->
