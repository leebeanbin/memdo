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

- [ ] PRD P0 요구사항 전부 구현
- [ ] OpenAPI와 구현 일치
- [ ] DB 마이그레이션 검증
- [ ] 실제 iPhone 위젯·딥링크 통과
- [ ] 알림 액션 통과
- [ ] 오프라인 동작 통과
- [ ] 개인정보 처리방침 게시
- [ ] Privacy Manifest 작성
- [ ] App Store 개인정보 답변 검토
- [ ] 계정 및 데이터 삭제 흐름 검증
- [ ] 장애 모니터링과 지원 채널 준비
- [ ] 로컬→계정 UUID 유지와 sync 충돌 검증
- [ ] 알림 7일·48개 rolling window 실제 기기 검증
- [ ] 출시 게이트 책임자·기한 충족

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

### 9.3 Xcode Organizer로 crash report 확인하기 (v1.0 Epic M)

앱 자체는 `MetricsCollector.swift`가 MetricKit crash/hang diagnostic을 기기 로컬 로그로만
남긴다(어디로도 전송하지 않음) — 이것과 별개로, TestFlight/App Store로 배포된 빌드의 crash는
Xcode Organizer가 앱 코드와 무관하게 자동으로 수집·symbolicate한다. Beta 기간 동안 이 절차로
crash를 확인한다:

1. Xcode → Window → Organizer.
2. 왼쪽에서 Memdo 앱을 선택하고 "Crashes" 탭으로 이동.
3. TestFlight/App Store로 배포된 빌드에서 발생한 crash가 여기 나타난다(전달까지 지연될 수
   있음 — 실시간이 아니다).
4. 각 crash를 열면 이미 symbolicate된 스택 트레이스를 볼 수 있다 — 별도 dSYM 업로드 없이도
   Xcode가 자동으로 처리한다(Archive 시 dSYM이 함께 생성·보관되는 한).
5. "Hangs"/"Disk Writes"/"Launch Time" 등 다른 MetricKit 기반 탭도 같은 화면에서 확인 가능하다.

기기에 연결된 사용자 계정(Apple ID)이 App Store Connect의 해당 앱에 접근 권한이 있어야 데이터가
보인다. 실기기에서 직접 강제 크래시를 발생시켜 이 절차 자체가 실제로 동작하는지 사전에 한 번
확인하는 것을 Epic N의 실기기 검증 매트릭스 항목으로 포함한다.
