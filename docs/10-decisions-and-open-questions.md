# 결정 기록과 미결정 사항

> 전체 문맥: [제품 뇌 지도](./00-product-brain-map.md)  
> 결정 영향 확인: [문서 변경 규칙](./13-document-governance.md)  
> 구현 전 미결정 항목은 해소 후 관련 PRD·UX·데이터·API·테스트 문서에 반영한다.

## 확정 결정

| ID | 결정 | 이유 |
|---|---|---|
| ADR-001 | 하루 요약은 AI가 아닌 규칙 기반 기능 | 예측 오류와 비용 없이 일관되게 동작 |
| ADR-002 | 완료 여부는 사용자 응답으로만 변경 | 신뢰와 데이터 정확성 |
| ADR-003 | 요약 시간은 사용자 직접 선택 | 알림 피로 방지 |
| ADR-004 | 로컬 알림을 일정·요약의 기본 전달 방식으로 사용 | 오프라인 동작과 단순성 |
| ADR-005 | 반복 규칙과 실제 Todo를 분리 | 예외 일정과 규칙 수정 지원 |
| ADR-006 | AI 계획은 draft/commit 2단계 | 승인 없는 저장 방지 |
| ADR-007 | UI 커스텀은 디자인 토큰과 프리셋 | 관리 가능한 개인화 |
| ADR-008 | iOS 내부 Agent는 MCP를 거치지 않음 | 내부 Application API로 충분; 외부 client는 ADR-065 적용 |
| ADR-009 | 최소 iOS 17 | 인터랙티브 위젯 단순화 |
| ADR-010 | 초기 작업은 PostgreSQL 안에서 처리 | ADR-062에 따라 custom claim table 대신 pgmq 사용 |
| ADR-011 | 키셋 커서 동기화 | 깊은 OFFSET과 동률 누락 방지 |
| ADR-012 | 외부 공급자는 도메인 포트 뒤에 격리 | 공급자 이름과 오류가 제품 전반에 퍼지는 것 방지 |
| ADR-013 | 하루 요약은 로컬 알림 우선 | 오프라인 동작과 정해진 시각 처리 |
| ADR-014 | 50명 규모에는 캐시·파티셔닝·읽기 복제본 미사용 | 데이터 규모와 운영 복잡도 불균형 |
| ADR-015 | 일정 검색은 원본 todos + pg_trgm으로 시작 | 별도 조회 테이블과 검색 서버 불필요 |
| ADR-016 | MVP Agent는 Responses API 직접 오케스트레이션 | 단일 Agent와 작은 도구 집합에 충분 |
| ADR-017 | Agent 도구는 조회·제안만 허용 | 실제 쓰기는 사용자 승인 Command API로 분리 |
| ADR-018 | 기본 격리 수준은 READ COMMITTED + optimistic version | 50명 규모의 충돌 특성과 구현 단순성 |
| ADR-019 | 외부 API 호출은 DB 트랜잭션 밖에서 수행 | 장기 lock과 장애 전파 방지 |
| ADR-020 | Google 이벤트는 Todo가 아닌 외부 미러로 저장 | 출처·권한·완료 상태 책임 분리 |
| ADR-021 | UI 분류는 entryKind·sourceProvider·ownership 세 축 | 출처와 의미를 한 필드에 혼합하지 않음 |
| ADR-022 | 외부 AI 쓰기는 proposal과 승인 링크로 처리 | Codex 세션 밖에서도 사용자가 diff를 검토 |
| ADR-023 | MCP는 Google read-only 통합 이후 구현 | 신뢰할 내부 데이터 경로를 먼저 검증 |
| ADR-024 | 앱은 Swift 6, 서버·MCP·웹은 TypeScript 5.x | 언어 수를 최소화하고 플랫폼 네이티브 유지 |
| ADR-025 | 파일럿 cloud는 Supabase Free 중심 | Auth·Postgres·RLS·Functions·Cron 통합 |
| ADR-026 | 승인 웹은 Vite + vanilla TypeScript + Cloudflare Pages | 작은 화면에 React 불필요 |
| ADR-027 | 서버 관찰은 Grafana Cloud, iOS crash는 Sentry | 관리형 무료 서비스로 운영 부담 축소 |
| ADR-028 | Supabase Free backup은 암호화 dump + R2 | Free plan 자동 백업 부재 보완 |
| ADR-029 | 동기화 충돌은 version + 409 | 기존 last-write-wins 문구 폐기 |
| ADR-030 | ~~MVP의 `계정 없이 시작`은 Supabase anonymous session을 사용~~ (ADR-071로 폐기) | 로그인 선택지 단순화 결정으로 신규 익명 세션 진입 제거 |
| ADR-031 | 하루 요약 시간은 사용자가 직접 선택 | 임의 기본값으로 알림 피로를 만들지 않음 |
| ADR-032 | 일부 완료는 퍼센트만 기록하고 잔여 Todo는 명시적 선택으로 생성 | 사용자 의도 없는 일정 증식을 막음 |
| ADR-033 | 미응답 일정은 자동 실패 처리하지 않고 다음 날 미정리 영역에 유지 | 사실이 아닌 완료·실패 판정을 피함 |
| ADR-034 | MVP 뉴스는 OpenAI Responses API의 web search 사용 | 별도 뉴스 공급자 계약·SDK 없이 출처 URL이 있는 3~5개 브리핑을 검증 |
| ADR-035 | Supabase 리전은 Seoul `ap-northeast-2` | 초기 한국 사용자 지연과 데이터 위치를 단순화 |
| ADR-036 | MVP AI 모델은 고정 평가셋을 통과한 model ID를 환경 변수 한 곳에서 고정 | 출시 시점의 가용 모델·비용·구조화 출력 품질을 확인하고 교체 범위를 제한 |
| ADR-037 | 삭제 이력만 있고 활성·완료 Todo가 없는 날은 `needs_planning` | 별도 `cleared` 상태 없이 다시 계획할 수 있게 함 |
| ADR-038 | 모든 Todo command는 body의 `baseVersion`으로 충돌 검사 | sync와 일반 API의 동시성 방식을 하나로 통일 |
| ADR-039 | 직접 재예약은 전용 원자적 command 사용 | 원본 `rescheduled`와 새 Todo 생성을 함께 보장 |
| ADR-040 | MVP Todo는 일정당 로컬 reminder 하나만 지원 | 다중 Reminder 엔터티와 서버 예약 복잡도 제거 |
| ADR-041 | 모든 미완료 Todo는 하루 요약 대상 | Todo별 review 토글과 중복 설정 제거 |
| ADR-042 | 부분 완료는 1~99, UI 빠른 선택은 25·50·75 | 데이터 유연성과 단순 UX를 함께 유지 |
| ADR-043 | 로컬 UUID를 계정 전환 후 그대로 업서트하고 내용 병합은 하지 않음 | 오탐 중복 제거와 ID 재작성 방지 |
| ADR-044 | DailyPlan은 날짜별 PUT으로 직접 편집 | 의도·분위기·회고가 AI에 종속되지 않게 함 |
| ADR-045 | 테마와 색상은 고정 token enum, 자유 HEX는 제외 | 위젯·접근성·구버전 fallback 보장 |
| ADR-046 | 뉴스 브리핑은 사용자가 정한 현지 시각에 하루 최대 1회 | 자동 브리핑 요구와 비용 상한을 명확히 함 |
| ADR-047 | 반복 preset은 daily·weekdays·weekly·biweekly·monthly·yearly, custom RRULE은 이에 필요한 검증 subset만 허용 | UI의 실제 선택지와 서버 규칙을 일치시키고 임의 RFC 5545 전체 구현은 피함 |
| ADR-048 | 로컬 알림은 향후 7일·최대 48개 rolling window | OS 예약 한도에 여유를 두고 앱 활성화 시 재조정 |
| ADR-049 | P1 기능도 PRD→UX→데이터→API→TEST 추적을 완료한 뒤 구현 | 후속 기능의 계약 누락 방지 |
| ADR-050 | UI v1은 Cloud Milk 토큰, 공통 FloatingTabBar, 주간·월간 설정형 위젯으로 고정 | 앱·위젯·시안 간 시각적 불일치 방지 |
| ADR-051 | 최상위 탭만 하단 내비게이션을 표시하고 시트·상세 화면은 숨김 | 정보 계층과 뒤로가기 문맥을 명확히 유지 |
| ADR-052 | 탭 선택은 0.18초 easeOut, 시트는 시스템 전환, 저장·완료에만 가벼운 햅틱 사용 | 모션을 일관되게 제한하고 접근성·피로도를 보호 |
| ADR-053 | ADR-050의 커스텀 FloatingTabBar를 네이티브 `TabView`와 iOS 26 Liquid Glass로 대체 | 시스템 안전 영역·축소 동작·접근성을 직접 재구현하지 않음 |
| ADR-054 | 검색 탭을 제거하고 캘린더의 네이티브 pull-down `searchable`로 통합 | 검색은 목적지가 아니라 일정 탐색 도구이며 하단 탭 복잡도를 줄임 |
| ADR-055 | 접근성 Dynamic Type에서는 행동 그룹·일정 행·시간 설정을 세로 재배치하고 장식 아이콘을 생략 | 글자를 축소하지 않고 읽기·터치 우선순위를 보존 |
| ADR-056 | ADR-054의 상단 pull-down 검색을 iOS 26 축소형 툴바 검색으로 대체 | 검색이 비핵심 기능일 때 큰 상단 필드를 없애고 탭 시 확장·닫기 시 축소되는 시스템 Liquid Glass 동작을 사용 |
| ADR-057 | ADR-056의 분리된 툴바 검색을 캘린더 헤더의 인라인 검색 모드로 대체 | 시스템 툴바 아이콘이 커스텀 제목과 분리되고 탭 전환 시 표시 상태가 선점되어 위치·빈 공간을 안정적으로 통제할 수 없었음 |
| ADR-058 | ADR-007·045·050의 색상 프리셋을 대체해 UI 기본 면은 semantic 흑백, 브랜드 보라는 로고·eyebrow·할 일·Agent 근거에만 사용 | Notion/Google Calendar와 같은 낮은 시각 소음, 시스템 Light/Dark 적응, 기능 상태와 장식의 분리 |
| ADR-059 | 일정 항목의 정규 유형은 `event`와 `task`이며, 마감은 Task의 nullable `dueAt`이다. `milestone` 유형은 사용하지 않는다 | Notion의 date range와 Google Calendar의 Event/Task/Deadline 방식을 조합하고 의미 중복을 제거 |
| ADR-060 | AI 전용 페이지를 제거하고 3개 콘텐츠 탭(오늘·캘린더·설정) 옆에 문맥형 Agent 액션을 둔다 | 탭 선택을 가로채 현재 콘텐츠를 유지한 채 Agent 시트만 열어 AI를 모든 계획 흐름의 보조 입력으로 유지 |
| ADR-061 | 좌우 스와이프는 오늘의 날짜·캘린더의 월 이동에만 사용하고 최상위 탭 전환에는 사용하지 않는다 | 캘린더 범위 이동·시스템 뒤로가기 제스처와 충돌 방지 |
| ADR-062 | 비동기 전달은 Supabase Queues(`pgmq`)를 사용하고 Kafka·RabbitMQ는 사용하지 않는다 | 50명 규모에서 durable delivery와 재시도를 PostgreSQL 운영면 안에서 해결 |
| ADR-063 | Redis는 Upstash REST를 AI·MCP rate limit, 짧은 lock, 만료 상태에만 사용한다 | 원본 일정과 일반 조회 cache를 분리해 Redis 장애의 제품 영향 제한 |
| ADR-064 | 의미 검색은 같은 PostgreSQL의 `pgvector`로 시작하고 외부 vector DB는 사용하지 않는다 | RLS·관계 필터·백업을 한 저장소에서 유지 |
| ADR-065 | MCP는 Memdo API의 외부 어댑터이며 DB에 직접 연결하지 않는다 | iOS와 외부 AI가 같은 Query·Proposal·Command 권한 경로 공유 |
| ADR-066 | LLM 경계는 OpenAI production adapter와 llama.cpp local adapter로 구성한다 | 모델 교체와 로컬 개발을 허용하되 API 호환성을 과장하지 않음 |
| ADR-067 | SQL migration을 schema 원본으로 유지하고 ORM은 trusted worker에 제한한다 | RLS·RPC·pgmq·pgvector를 ORM schema와 이중 관리하지 않음 |
| ADR-068 | 인덱스 최적화와 데이터 송신 최적화를 별도 예산·지표로 관리한다 | 인덱스는 DB 탐색 비용을 줄이지만 payload 크기를 직접 줄이지 않음 |
| ADR-069 | UI·Domain·DTO·DB row는 경계에서 명시적으로 변환한다 | 화면 편의를 서버 계약으로 누출하지 않고 버전 변화 격리 |
| ADR-070 | 서버 enum은 안정 영문 code, 사용자 문구는 iOS String Catalog로 관리한다 | 한국어 raw value와 고정 timezone이 글로벌 동작을 막지 않게 함 |
| ADR-071 | 로그인 화면과 신규 계정 진입은 Google·GitHub로 제한하고 계정 없는 시작을 제공하지 않는다 | 인증 선택과 데이터 소유권을 명확히 하고 로그인 화면의 인지 부하를 줄임 |

## 제품 이름

문서에서는 임시 이름 `Memdo`를 사용한다. 상표와 App Store 중복 확인 후 변경한다.

## 구현 전 미결정 항목

없음. [정합성 감사](./26-document-consistency-audit.md)의 GAP-001~017은 ADR-037~049와 관련 계약 문서에 반영했다. 구현 중 새 선택지가 생기면 임시 상수나 주석으로 남기지 않고 ADR 후보로 등록한다.

## 출시 전 외부 검토

- 개인정보 변호사 또는 전문 검토
- App Store Review Guidelines
- 뉴스 콘텐츠 이용 조건
- OpenAI 데이터 처리 설정
- Supabase 데이터 보존과 백업 설정
- APNs 인증 키 운영 절차

출시 게이트 기본값:

| 항목 | 기본 결정 | 책임 | 기한 |
|---|---|---|---|
| 제품명·도메인 | 개발명 `Memdo`; 상표 확인 전 Store 제출 금지 | Founder | TestFlight 외부 배포 30일 전 |
| 출시 국가 | 대한민국부터 시작 | Founder | 개인정보 처리방침 작성 전 |
| 아동 대상 | 만 14세 미만 대상 아님 | Founder | App Store Connect 입력 전 |
| 법률 문서 | 외부 전문가 검토 없이는 공개 출시 금지 | Founder | 공개 출시 30일 전 |
| Supabase 요금제 | 내부 50명은 Free, 실제 공개 사용자 데이터 전 Pro 전환 | Tech Lead | 공개 출시 7일 전 |
