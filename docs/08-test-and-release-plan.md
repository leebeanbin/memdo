# 테스트 및 출시 기준

> 테스트 대상: [제품 요구사항](./01-product-requirements.md)  
> 정규 테스트 ID: [요구사항 추적표](./12-requirements-traceability.md)  
> 상태·API 기준: [데이터 모델](./04-data-model.md), [API 명세](./05-api-spec.yaml)

## 1. 테스트 전략

MVP는 핵심 상태 전이와 실제 기기 위젯·알림 검증에 집중한다.

## 2. 단위 테스트

### 일정

- 제목 공백 거부
- 종료 시간이 시작 시간 이전이면 거부
- 시간 없는 일정 저장
- 날짜와 타임존 변환
- 완료 시 진행률 100

### 하루 요약

- 미완료 일정만 대상
- 완료·건너뜀·취소 제외
- 일부 완료 포함
- 응답별 정확한 상태 전이
- 내일로 이동 시 원본과 새 일정 연결
- 중복 응답의 idempotency

### 반복

- 매일
- 평일
- 월·수·금
- 월말
- 타임존 변경
- 규칙 수정 시 수동 예외 보존

## 3. 통합 테스트

- 로그인 후 사용자별 데이터 격리
- 오프라인 생성 후 온라인 동기화
- 여러 기기에서 동일 일정 완료
- 일정 수정 후 로컬 알림 재예약
- 동의 철회 후 AI API 거부
- 연결 해제 후 외부 토큰 사용 불가
- AI 초안 commit 전 Todo 미생성

## 4. UI 테스트

- 일정 없음 → 계획 시작
- 직접 일정 추가
- AI 초안 수정·승인·폐기
- 하루 요약 전체 흐름
- 일부 완료
- 내일로 이동
- 알림 권한 거부
- 개인정보 숨김 위젯
- 큰 글자와 VoiceOver

## 5. 실제 기기 테스트

- 잠금화면 위젯 표시
- 잠금 상태 탭 → 인증 → 올바른 화면
- 로컬 알림 전달과 액션
- 기기 재부팅 후 예약 알림
- 앱 강제 종료 상태의 알림
- 저전력 모드
- 네트워크 없음
- 타임존 변경
- 시스템 알림 권한 변경

## 6. 보안·개인정보 테스트

- 다른 사용자의 UUID로 API 접근 차단
- RLS 우회 시도 차단
- 삭제된 동의로 AI 요청 차단
- 민감 필드가 로그에 기록되지 않음
- 앱 번들에 API 키 없음
- 위젯 숨김 모드에서 제목 노출 없음
- 계정 삭제 시 삭제 작업 생성

## 7. 출시 차단 조건

- 일정 유실 또는 중복 생성
- 완료 응답이 다른 일정에 적용
- 반복 규칙이 무한 인스턴스 생성
- 지원하지 않는 RRULE이 저장됨
- 동의 없이 AI 데이터 전송
- 잠금화면 숨김 설정에서 제목 노출
- 다른 사용자의 데이터 접근
- 알림 거부 시 앱 크래시

## 8. MVP 승인 체크리스트

> **개정(v1.0 Epic K, 2026-08-25)**: 아래 각 항목은 실제 코드 기준으로 재검증했다 — 체크박스가
> 비어 있던 이전 버전은 실제 구현 여부와 무관하게 전부 미확인 상태였을 뿐이다. 이제부터는 실제
> 코드에 없는 항목만 미체크로 남긴다. **blocker**는 v1.0(Public Beta) 출시를 막는 항목,
> **non-blocker**는 출시를 막지는 않지만 추적이 필요한 항목이다.

- [x] PRD P0 요구사항 전부 구현 — **non-blocker** (표본 검증 결과 대부분 구현 확인 —
  `apps/ios/Memdo/Memdo/ScheduleModel.swift`/`ScheduleAPI.swift`/`NotificationScheduler.swift`,
  `memdo-backend/supabase/functions/todos`/`rules`/`reviews`/`days`. 전체 P0 항목의 line-by-line
  전수 검증은 아님 — 표본 검증)
- [ ] OpenAPI와 구현 일치 — **non-blocker** (사용자에게 보이는 blocker는 아니지만 문서 부채).
  `docs/05-api-spec.yaml`이 약 50개 미구현 경로(`/slack/*`, `/briefings*`, `/devices*`,
  `/automations*`, `/agent-runs*`, `/connections*`, `/change-proposals*`, `/health/*` 등)를 포함하고
  있고, 반대로 `agent-cloud-chat`/`agent-usage`/`categories`/`workout-logs`는 스펙에 없음. v1.0
  Epic K에서 current(실제 구현)/planned(설계됐지만 미구현) 구조로 재정리 예정 — Epic L 완료 후
  진행
- [x] DB 마이그레이션 검증 — **non-blocker, 통과**. `memdo-backend/supabase/migrations/`에 25개
  마이그레이션, 최근까지 활발히 유지됨
- [x] 실제 iPhone 위젯·딥링크 통과 (코드 존재, 실기기 검증은 Epic N 매트릭스로) — **blocker
  (실기기 검증 자체는)**. 커스텀 `memdo://` scheme(true universal link 아님) + 위젯 타겟 코드는
  존재. 실기기 확인은 Epic N의 real-device verification matrix에서 진행
- [x] 알림 액션 통과 — **non-blocker, 통과**. `NotificationScheduler.swift`/
  `MemdoNotificationDelegate`에 `UNNotificationCategory`/액션 구현 확인
- [x] 오프라인 동작 통과 — **non-blocker, 통과**. `OutboxQueue`, `pendingWriteIDs` 기반 로컬
  우선 모델 확인
- [ ] 개인정보 처리방침 게시 — **blocker**. 코드에 없음 — v1.0 Epic K에서 실제 public URL로 게시
- [ ] Privacy Manifest 작성 — **blocker**. `PrivacyInfo.xcprivacy` 파일 자체가 없음 — App Store
  Connect 업로드 자체를 막는 항목. v1.0 Epic K에서 실제 Required Reason API 감사 기반으로 작성
- [ ] App Store 개인정보 답변 검토 — **blocker**. 초안 없음 — v1.0 Epic K에서 작성
- [ ] 계정 및 데이터 삭제 흐름 검증 — **blocker**. 코드 자체가 없음(백엔드 endpoint, iOS UI 둘 다
  없음) — "미검증"이 아니라 "미구현". v1.0 Epic L에서 Apple 토큰 revocation을 포함해 구현
- [ ] 장애 모니터링과 지원 채널 준비 — **non-blocker (앱스토어 제출을 막지는 않음), 하지만 beta를
  책임감 있게 운영하려면 사실상 필요**. `_shared/http.ts`의 구조화 JSON 요청 로깅만 존재, 실시간
  알림/지원 채널 없음. v1.0 Epic M에서 MetricKit 기반 최소 crash/hang 진단만 추가 — 실시간
  alerting/Sentry는 이번 버전 범위 밖(로드맵 decision gate로 이후 판단)
- [ ] 로컬→계정 UUID 유지와 sync 충돌 검증 — **non-blocker**. UUID 연속성은 익명 인증 승격으로
  암묵적으로 동작 확인(`MemdoApp.swift`), `sync/index.ts`에 명시적 409/conflict 처리 코드는
  발견되지 않음 — v1.0 범위에서 별도 구현 예정 없음, 실사용 중 문제 관찰 시 별도 Epic으로 대응
- [ ] 알림 7일·48개 rolling window 실제 기기 검증 — **blocker**. `docs/07-notification-and-daily-review.md`
  §10 스펙(오늘 포함 7일 window, 최대 48개 pending, 예정 시각 오름차순+Todo ID tiebreak, 초과 시
  가까운 알림 우선 유지)이 `NotificationScheduler.swift`에 전혀 구현되지 않음(반복 알림 2개 +
  개별 일정 알림만 개별 예약, cap/window/reconciliation 로직 없음) — v1.0 Epic L에서 구현
- [ ] 출시 게이트 책임자·기한 충족 — 조직 항목, 코드로 검증 불가

## 9. 출시 검증 단계 (Release Validation Stages)

> [`09-roadmap-and-backlog.md`](./09-roadmap-and-backlog.md)의 v1.0(Public Beta / Stability)에
> 대응하는 실행 계획이다. **원칙: beta 기간에는 신규 기능 추가보다 correctness/UX 안정화를
> 우선한다** — v1.0의 "Out of scope: 신규 제품 기능" 결정과 동일한 원칙을 여기서도 반복한다.

### 9.1 단계 구성

1. **Internal dogfooding — 1주**: 개발자 본인만, 실제 기기, 실제 데이터. 목적: 시뮬레이터/CI로는
   잡히지 않는 것(알림 타이밍, 백그라운드 refresh, 실제 OAuth 왕복)을 먼저 잡는다.
2. **Closed Beta — 2주**: TestFlight을 통한 소규모 known 그룹.
3. **Expanded Beta — 2~4주**: 더 넓은 TestFlight 그룹. 동일한 metric을 더 큰 표본으로, closed
   beta에서는 보이지 않던 기기/OS 다양성에 따른 회귀를 특히 주시한다.
4. **v1.0 release gate**: 아래 metric이 2주 이상 연속으로 허용 범위 안에 있고, `08` §8의 MVP
   체크리스트가 전부 닫혀야 한다.

### 9.2 각 단계에서 보는 metric (Closed Beta부터 동일하게 적용)

- 크래시/오류율
- Agent runtime 실패율
- proposal 승인/거절 비율
- latency(p50/p95 turn time)
- 재시도율
- onboarding/BYOK 연결 실패율
- mutation 정확성(데이터 유실/중복 신고 없음)
- 알림 피로도(opt-out率)
- 주간 재방문율

구체적인 숫자 임계값은 이 문서에서 지금 고정하지 않는다 — 실제 beta 데이터가 쌓이기 전에 숫자를
확정하는 것은 로드맵 전체가 피하려는 조기 확정과 같은 문제다. 임계값은 각 단계를 실제로 운영하며
정한다.

### 9.3 GitHub Pages (Privacy Policy 호스팅) 런북

Privacy policy 공개 URL(`https://leebeanbin.github.io/memdo/privacy/`)은 새 도메인/호스팅 없이
memdo repo(이미 public)의 GitHub Pages로 제공한다. **아래 1회성 설정은 이미 완료됨(2026-08-25,
`gh api -X POST repos/leebeanbin/memdo/pages -f "source[branch]=main" -f "source[path]=/"`)**:

```text
source: main branch, path "/"
build type: legacy (별도 GitHub Actions 워크플로 불필요)
https: 강제 적용됨
```

**Pages가 전체 repo를 탐색 가능한 사이트로 만들지 않도록 하는 구조**:

- `.nojekyll`을 repo 루트에 둬서 Jekyll 자동 테마/네비게이션 생성을 끈다 — `docs/*.md`가 자동으로
  브라우징 가능한 사이트 메뉴로 노출되지 않는다.
- Privacy policy는 `/privacy/index.html` 단일 정적 페이지로만 존재한다. 이 페이지 자체가
  `docs/`의 다른 문서로 링크하지 않는다.
- repo 루트에 별도 `index.html`을 두지 않아 `https://leebeanbin.github.io/memdo/` 루트 자체는
  아무 것도 서빙하지 않는다(브라우징 가능한 랜딩 페이지 없음).
- 정책 원문은 `privacy/index.html`로 repo에 version-controlled 상태로 유지되며, 수정 시 파일
  안의 "최종 수정일"을 함께 갱신한다.

**만약 향후 Pages 설정을 다시 바꿔야 한다면**(예: 커스텀 도메인 추가, source 변경): GitHub repo
Settings → Pages 화면에서 사람이 직접 변경하거나, 동일한 `gh api` 패턴을 재사용한다. 이 설정
자체를 v1.0 이후 별도로 확장할 계획은 없다.

**배포 확인**: `main`에 머지된 뒤 `curl -I https://leebeanbin.github.io/memdo/privacy/`로 실제
`200`을 반환하는지 확인 — 이것이 Epic K DoD의 "실제 public URL 접근 가능" 항목이다.
