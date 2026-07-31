# 요구사항 추적성 매트릭스

이 문서는 “요구사항이 화면에는 있는데 API에 없거나, API는 있는데 테스트가 없는” 상태를 막는다.

## 1. P0 추적표

| 요구사항 | UX | 데이터 | API | 정책·기술 | 테스트 |
|---|---|---|---|---|---|
| PRD-001 최소 일정 저장 | 일정 생성 | Todo 필수 필드 | POST /todos | 로컬 우선 저장 | TEST-001 |
| PRD-002 느슨한 시간대 | 일정 생성·Today | timeBucket | TodoInput.timeBucket | 사용자 현지 날짜 | TEST-002 |
| PRD-003 빈 계획 질문 | Today Empty | DayView 상태 | GET /days/{date} | 위젯 스냅샷 | TEST-003 |
| PRD-004 요약 시간 설정 | 온보딩·설정 | UserPreferences | /daily-review/settings | 로컬 알림 | TEST-004 |
| PRD-005 미완료만 확인 | 하루 요약 | DailyReview | GET /daily-reviews/{date} | 대상 알고리즘 | TEST-005 |
| PRD-006 사용자만 완료 확정 | 완료 확인 | Todo.status | /responses, /status | ADR-002 | TEST-006 |
| PRD-007 응답 선택지 | 하루 요약 | ReviewResponse | POST /responses | 상태 전이표 | TEST-007 |
| PRD-008 반복 일정 | 일정 편집 | ScheduleRule | /schedule-rules | RRULE·30일 생성 | TEST-008 |
| PRD-009 일정 알림 | 일정 편집 | Todo.reminderOffsetMinutes | TodoInput reminder 필드 | 로컬 알림 | TEST-009 |
| PRD-010 위젯 딥링크 | 잠금화면 위젯 | WidgetSnapshot ID | DayView | Universal Link | TEST-010 |
| PRD-011 앱·위젯 일치 | Today·위젯 | WidgetSnapshot | DayView | App Group | TEST-011 |
| PRD-012 알림 거절 허용 | 권한 안내 | 설정 상태 | 해당 없음 | 권한 상태 분기 | TEST-012 |
| PRD-013 AI 승인 전 미저장 | AI 초안 | PlanDraft | draft + commit | ADR-006 | TEST-013 |
| PRD-014 세분화 동의 | AI·개인정보 | ConsentRecord | /privacy/consents | PRIV 정책 | TEST-014 |

## 2. 테스트 시나리오

### TEST-001 최소 일정

제목과 날짜만 입력한 Todo가 저장되고 재실행 후 표시된다.

### TEST-002 시간 없는 일정

시작 시간이 없는 Todo가 선택한 오전·오후·저녁·언제든 섹션에 표시된다.

### TEST-003 빈 계획 상태

당일 일정이 한 번도 없을 때만 시작 질문이 표시된다.

### TEST-004 하루 요약 예약

사용자가 선택한 현지 시각과 요일에 요약 알림 요청이 등록된다.

### TEST-005 요약 대상

planned·in_progress·partial만 포함되고 completed·skipped·rescheduled·cancelled는 제외된다.

### TEST-006 완료 소유권

시간 경과, 알림 무시, AI 실행만으로 completed가 되지 않는다.

### TEST-007 응답 상태 전이

각 응답이 데이터 모델의 상태 전이표와 동일하게 반영된다.

### TEST-008 반복 인스턴스

동일 규칙과 날짜의 인스턴스가 중복 생성되지 않고 수동 예외가 보존된다.

### TEST-009 알림 변경

일정 시간 수정 시 기존 알림이 취소되고 새 알림이 등록된다.

### TEST-010 잠금화면 이동

잠긴 실제 기기에서 위젯 탭 후 인증을 거쳐 정확한 화면으로 이동한다.

### TEST-011 스냅샷 일치

일정 변경 후 앱과 위젯의 다음 일정·남은 개수가 일치한다.

### TEST-012 권한 거부

알림 권한을 거부해도 일정 생성, 수정, 하루 요약 수동 실행이 가능하다.

### TEST-013 AI 미승인 저장 방지

초안 생성·수정·폐기 과정에서 commit 전 Todo 수가 바뀌지 않는다.

### TEST-014 동의 범위

동의하지 않은 일정 제목·메모가 AI 요청과 로그에 포함되지 않는다.

## 3. P1 추적표

| 요구사항 | UX | 데이터 | API | 정책·기술 | 테스트 |
|---|---|---|---|---|---|
| PRD-101 관심 뉴스 | Today·관심사 | Briefing·Interest | /interests, /briefings | 뉴스 동의·출처 | TEST-101 |
| PRD-102 Apple Calendar | 캘린더 연결 | local CalendarEntry | 로컬 EventKit | calendar.read | TEST-102 |
| PRD-103 테마 | 나의 스타일 | UserPreferences token | /preferences | ADR-045 | TEST-103 |
| PRD-104 여러 기기 | 로그인·동기화 | version·tombstone | /sync | ADR-038·043 | TEST-104 |
| PRD-105 주간 기록 | 주간 기록 | 집계 projection | /insights/weekly | 평가 금지 | TEST-105 |
| PRD-106 Google 연결 | 외부 연결 | DataConnection·mirror | /connections, /calendar | OAuth 최소 scope | TEST-106 |
| PRD-107 출처 인덱스 | 통합 캘린더 | CalendarEntry axes | /calendar/entries | ADR-021 | TEST-107 |
| PRD-108 외부 AI 승인 | 승인 웹 | ChangeProposal | /change-proposals | ADR-022 | TEST-108 |

## 4. P1 테스트 시나리오

### TEST-101 뉴스 출처

브리핑은 3~5개이며 각 항목에 검증된 매체·게시 시각·원문 URL이 있고, 같은 현지 날짜에는 자동 생성이 한 번만 성공한다.

### TEST-102 EventKit 최소 범위

busy-only 선택에서는 제목·메모가 앱 도메인이나 서버로 전달되지 않는다.

### TEST-103 테마 fallback

모르는 theme·color token을 받으면 `warmPaper`·`coral`로 표시하고 충분한 대비를 유지한다.

### TEST-104 계정 전환과 충돌

로컬 UUID가 로그인 후 유지되며 동일 UUID 재전송은 중복 생성되지 않고 stale `baseVersion`은 mutation별 conflict가 된다.

### TEST-105 비평가적 주간 기록

완료·부분·이동 수치를 사실로만 보여주고 생산성 점수나 실패 문구를 만들지 않는다.

### TEST-106 Google 연결

OAuth state·PKCE를 검증하고 선택한 access level 밖의 scope를 요청하지 않으며 연결 해제 후 token을 사용할 수 없다.

### TEST-107 출처 표시

Memdo Todo, Google mirror, Apple local event, AI proposal이 세 축의 badge와 허용된 액션으로 구분된다.

### TEST-108 외부 AI 승인

만료·변경된 target은 실행되지 않고 새 diff 승인을 요구하며 승인 전 Todo는 변하지 않는다.

## 5. 기능 완료 정의

기능은 다음이 모두 연결되어야 완료다.

```text
PRD ID
+ UX 진입점과 성공·취소 흐름
+ 데이터 상태와 제약
+ API 또는 로컬 인터페이스
+ 개인정보 영향
+ 실행 위치와 실패 처리
+ TEST ID와 실행 증거
```

하나라도 없으면 구현 완료가 아니라 설계 누락이다.
