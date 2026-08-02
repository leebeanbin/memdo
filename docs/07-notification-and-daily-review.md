# 알림과 하루 요약 정책

> 제품 근거: PRD-004~007, PRD-009  
> 화면: [UX 명세](./02-ux-and-screens.md)  
> 상태: [데이터 모델](./04-data-model.md), [공통 용어집](./11-glossary-and-canonical-rules.md)  
> 테스트: TEST-004~009 in [추적표](./12-requirements-traceability.md)

## 1. 제품 정의

하루 요약은 AI 기능이 아니다. 사용자가 정한 시간에 오늘의 상태를 정리하고, 미완료 일정에 대한 명시적 답을 받는 기본 기능이다.

## 2. 설정

```text
enabled
time
days
includeReflection
```

조용한 시간은 하루 요약 설정에 복사하지 않고 `UserPreferences.quietHoursStart/End`를 참조한다.

기본값:

- 비활성
- 사용자가 직접 시간 선택
- 활성화 시 매일
- 한 줄 회고 활성

## 3. 알림 카테고리

### TODO_REMINDER

문구:

```text
곧 시작해요
20:00 운동하기
```

액션:

- 시작했어요
- 10분 뒤
- 건너뛰기

### DAILY_REVIEW

미완료가 있는 경우:

```text
오늘을 정리할 시간이에요
확인할 일정이 3개 있어요.
```

미완료가 없는 경우:

```text
오늘 계획을 모두 정리했어요
하루를 한 문장으로 남겨볼까요?
```

액션:

- 정리하기
- 30분 뒤

### BRIEFING_READY

```text
오늘의 브리핑이 준비됐어요
오늘의 브리핑 4개를 확인해 보세요.
```

기사 제목은 잠금화면 기본 문구에 넣지 않는다.

## 4. 권한 요청 시점

- 첫 앱 실행 시 요청하지 않는다.
- 사용자가 첫 일정 알림 또는 하루 요약 시간을 저장한 직후 요청한다.
- 거절 시 반복 요청하지 않는다.
- 설정 화면에서 현재 시스템 권한과 이동 버튼을 제공한다.

## 5. 하루 요약 대상

```text
scheduledDate == 사용자 현지 오늘
status in planned, in_progress, partial
deletedAt == null
```

제외:

```text
completed
skipped
rescheduled
cancelled
```

## 6. 응답 처리

### 완료

- `status = completed`
- `progress = 100`
- `completedAt = now`
- 남은 알림 취소

### 일부 완료

- `status = partial`
- `progress` 1~99 저장
- UI 빠른 선택은 25·50·75
- 남은 작업은 사용자가 별도 command를 승인할 때만 새 Todo로 생성

### 건너뜀

- `status = skipped`
- 반복 규칙은 유지

### 내일로 이동

- 원본 `status = rescheduled`
- 내일 새 Todo 생성
- 새 ID 부여
- 원본 ID를 `rescheduledFromId`로 연결

### 다른 시간

- 당일 미래 시각 또는 다른 날짜 선택
- 이미 지난 시각 금지
- 해당 일정 알림 재예약

## 7. 재알림

- “30분 뒤”는 하루 한 번만 제공한다.
- 조용한 시간에 들어가면 다음 허용 시간으로 미룬다.
- 사용자가 알림을 무시해도 상태를 변경하지 않는다.
- 다음 날 자동으로 실패나 미완료 판정을 내리지 않는다.

## 8. 타임존과 서머타임

- 요약 시간은 사용자 현지 벽시계 시간으로 저장한다.
- IANA 타임존을 함께 저장한다.
- 타임존 변경 시 다음 알림을 재계산한다.
- 존재하지 않는 현지 시각은 다음 유효 시각으로 이동한다.
- 중복되는 시각은 첫 번째 시각을 기본으로 사용한다.

## 9. 접근성

- 알림 액션을 색상만으로 구분하지 않는다.
- VoiceOver에 일정 제목과 시간을 자연스러운 순서로 제공한다.
- Dynamic Type에서 액션 문구가 잘리지 않게 한다.
- 완료 확인 버튼의 최소 터치 영역을 보장한다.

## 10. 로컬 알림 예약과 복구

```text
rolling window: 오늘 포함 7일
최대 pending request: 48개
정렬: 예정 시각 오름차순, 동률이면 Todo ID
```

- 앱 활성화, Todo·반복 규칙 변경, 타임존 변경, 알림 권한 변경 때 reconciliation한다.
- 앱이 소유한 notification identifier만 취소·재생성한다.
- 48개를 넘으면 가까운 알림부터 유지하고 다음 앱 활성화 때 창을 앞으로 이동한다.
- 알림 액션은 먼저 로컬 DB에 멱등 저장하고 서버 sync를 pending으로 남긴다.
- 로컬 저장 실패 시 상태를 바꾸지 않고 앱을 열어 재시도하도록 안내한다.
- 여러 기기에서 일정 알림은 각 기기의 명시적 알림 활성화 설정을 따른다. 기본은 현재 기기만 활성이다.
