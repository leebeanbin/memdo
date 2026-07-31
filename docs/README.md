# Memdo 제품 기획 문서

버전: 0.2  
기준일: 2026-07-30  
상태: MVP 기획 기준선

## 제품 한 문장

사용자가 원하는 하루의 분위기를 정하고, 부담 없이 계획하며, 정한 시간에 하루를 정리하는 개인형 데일리 캘린더.

## 핵심 결정

- 전문 캘린더가 아니라 `오늘` 중심의 개인 캘린더다.
- 일정이 비어 있으면 계획을 강요하지 않고 시작 질문을 보여준다.
- 하루 요약 시간은 사용자가 직접 정한다.
- 요약 시 미완료 일정을 하나씩 확인하고 사용자의 답으로만 상태를 변경한다.
- AI는 계획 초안, 자연어 입력, 뉴스 요약에 사용한다.
- 일정 완료 여부는 AI가 추측하지 않는다.
- 반복 일정과 알림은 AI 없이도 정상 작동하는 기본 기능이다.
- AI 데이터 접근과 자동 행동은 기능별로 별도 동의를 받는다.

## 시작 방법

이 문서 묶음은 독립 파일 모음이 아니라 서로 연결된 제품 지식 그래프다.

처음 읽는 사람은 반드시 [제품 뇌 지도](./00-product-brain-map.md)에서 시작한다. 용어가 낯설면 [공통 용어집](./11-glossary-and-canonical-rules.md)을 먼저 열고, 기능을 변경할 때는 [요구사항 추적표](./12-requirements-traceability.md)와 [문서 운영 규칙](./13-document-governance.md)을 따른다.

## 문서 체계

| 순서 | 문서 | 역할 |
|---:|---|---|
| 00 | [제품 뇌 지도](./00-product-brain-map.md) | 전체 관계와 읽기 경로 |
| 01 | [제품 요구사항](./01-product-requirements.md) | 왜, 무엇을 만드는가 |
| 02 | [UX 흐름과 화면](./02-ux-and-screens.md) | 사용자는 어떻게 경험하는가 |
| 03 | [기술 설계](./03-technical-architecture.md) | 어디서 어떻게 실행하는가 |
| 04 | [데이터 모델과 ERD](./04-data-model.md) | 어떤 상태를 기억하는가 |
| 05 | [API 명세](./05-api-spec.yaml) | 앱과 서버의 계약 |
| 06 | [개인정보·동의·AI 정책](./06-privacy-consent-ai-policy.md) | 무엇을 허용하고 보호하는가 |
| 07 | [알림과 하루 요약](./07-notification-and-daily-review.md) | 시간 기반 행동과 상태 전이 |
| 08 | [테스트 및 출시 기준](./08-test-and-release-plan.md) | 무엇으로 완료를 증명하는가 |
| 09 | [로드맵과 백로그](./09-roadmap-and-backlog.md) | 어떤 순서로 만드는가 |
| 10 | [결정 기록](./10-decisions-and-open-questions.md) | 왜 이 선택을 했는가 |
| 11 | [공통 용어집](./11-glossary-and-canonical-rules.md) | 같은 말을 같은 뜻으로 사용 |
| 12 | [요구사항 추적표](./12-requirements-traceability.md) | 요구사항부터 테스트까지 연결 |
| 13 | [문서 운영 규칙](./13-document-governance.md) | 지식 그래프를 유지하는 방법 |
| 14 | [DB 성능·운영](./14-database-performance-and-operations.md) | 조회·쓰기·인덱스·운영 기준 |
| 15 | [외부 API 통합](./15-external-integrations-and-naming.md) | 공급자 경계와 네이밍 |
| 16 | [엔지니어링·커밋 규칙](./16-engineering-and-commit-rules.md) | 코드와 변경 관리 |
| 17 | [데이터 파이프라인](./17-data-pipeline.md) | 동기화·작업 큐·외부 처리 |
| 18 | [일정 검색 파이프라인](./18-todo-search-pipeline.md) | 직접·Agent 검색의 공통 경로 |
| 19 | [트랜잭션 경계](./19-transaction-boundaries.md) | 원자성·동시성·보상 결정 |
| 20 | [AI Agent 설계](./20-ai-agent-architecture.md) | 모델·도구·승인·확장 구조 |
| 21 | [Integration Hub](./21-integration-hub-google-calendar-mcp.md) | Google Calendar·MCP·승인 링크·UI 인덱싱 |
| 22 | [기술 스택 기준선](./22-technology-stack-baseline.md) | 언어·런타임·무료 클라우드 확정 |
| 23 | [관찰 가능성](./23-observability-and-alerting.md) | Grafana·Sentry·metrics·alerts |
| 24 | [환경·CI/CD·백업](./24-environments-ci-cd-backup.md) | 배포·migration·R2 복구 |
| 25 | [API 계약 완성도](./25-api-contract-completeness.md) | 공통 오류·rate limit·버전 규칙 |
| 26 | [전체 문서 정합성 감사](./26-document-consistency-audit.md) | 미결정·충돌·구현 전 보완 항목 |
| UI | [최종 UI/UX 기준선](../apps/ios/Memdo/DESIGN.md) | 확정 색상·화면·내비게이션·위젯·모션 |

## MVP 성공 조건

- 사용자가 60초 안에 첫 일정을 만들 수 있다.
- 잠금화면 위젯에서 오늘 상태를 확인하고 해당 화면으로 이동할 수 있다.
- 사용자가 정한 시간에 하루 요약 알림을 받을 수 있다.
- 미완료 일정에 대해 완료·건너뜀·내일로 이동·시간 변경을 선택할 수 있다.
- 알림이나 AI 권한을 거절해도 기본 일정 기능을 사용할 수 있다.
- AI가 승인 없이 일정을 저장하거나 완료 처리하지 않는다.
