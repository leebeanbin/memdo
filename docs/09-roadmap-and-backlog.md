# 로드맵과 백로그

> 범위 기준: [제품 요구사항](./01-product-requirements.md)  
> 선행 결정: [결정 기록](./10-decisions-and-open-questions.md)  
> 각 Phase 완료 증거: [요구사항 추적표](./12-requirements-traceability.md), [테스트 계획](./08-test-and-release-plan.md)

## Phase 0 — 기술 검증

- SwiftUI 앱
- SwiftData Todo
- 잠금화면 위젯
- App Group 스냅샷
- Universal Link
- 로컬 알림
- 알림 액션

완료 조건:

> 위젯에서 일정을 보고 탭해 잠금 해제 후 상세 화면으로 이동하며, 지정 시간 알림에서 완료 처리가 된다.

## Phase 1 — 로컬 MVP

- 오늘 화면
- 빈 계획 상태
- 직접 일정 CRUD
- 오전·오후·저녁·언제든
- 반복 일정
- 하루 요약 시간
- 미완료 일정 확인
- 테마 프리셋
- 위젯 개인정보 숨김

## Phase 2 — 계정과 동기화

- Sign in with Apple
- PostgreSQL
- RLS
- 커서 동기화
- 여러 기기
- 계정 및 데이터 삭제

## Phase 3 — 선택적 AI

- 계획 초안
- 자연어 일정 변환
- 사용자 승인 commit
- AI 데이터 범위 동의
- 실행 기록
- AI 기능 전체 끄기

## Phase 4 — 뉴스

- 관심사
- 최신 기사 검색
- 출처와 원문 링크
- 3~5개 요약
- 브리핑 알림
- 뉴스 개인화 동의

## Phase 5 — 외부 캘린더

- EventKit
- 바쁜 시간만 읽기
- 제목 읽기 선택
- 외부 일정 쓰기 별도 동의
- 충돌 안내

## 출시 후 검토

- 주간 회고
- Apple Watch
- App Shortcuts
- 자체 MCP
- 다른 AI 클라이언트 연결

## 만들지 않을 것

- 다중 Agent
- 벡터 DB
- 자유 배치 UI 편집기
- 조직 협업
- 프로젝트 관리
- 센서 기반 완료 추측
- 사용자 승인 없는 자동 삭제
