# UI ↔ 백엔드 계약·구현 범위 감사

상태: 2026-08-03 원격 통합 검증 반영  
대상 UI: `apps/ios/Memdo/Memdo/*.swift`, `MemdoWidget/*.swift`  
대상 백엔드: `../memdo-backend/supabase`  
목적: 화면에 보이는 기능, 데이터 모델, OpenAPI, 물리 스키마, 단계별 구현의 불일치를 구현 전에 차단한다.

## 1. 판정 규칙

각 기능은 아래 다섯 층이 같은 의미일 때만 완료다.

```text
SwiftUI 입력·표시
→ iOS Domain Model
→ API DTO
→ Application Command / Query
→ PostgreSQL Schema
```

- UI만 있고 API가 없으면 `계약 대기`다.
- OpenAPI에 있고 현재 migration에 없지만 이후 단계가 명시돼 있으면 `단계 대기`다.
- 같은 값을 서로 다른 타입·단위로 표현하면 `계약 오류`다.
- 버튼이 빈 closure 또는 fixture만 변경하면 `시연 UI`이며 완료로 표시하지 않는다.
- 구현과 문서가 다르면 구현을 정답으로 간주하지 않고 이 표에서 차이로 기록한다.

## 2. 전수 대조 결과

| UI 기능 | 정규 계약 | 현재 백엔드 | 판정 | 처리 단계 |
|---|---|---|---|---|
| 오늘 날짜 이동·일정 개수 | 날짜 범위 `GET /todos` + 로컬 날짜 projection | 실제 날짜·인증 repository 원격 검증 | 일치 | B2 완료 |
| Event/Task 생성 | `POST /todos` | iPhone 15 POST 201·재실행 복원 검증 | 일치 | B2 완료 |
| 일정 상세·수정·삭제 | `PATCH/DELETE /todos/{id}` | PATCH 200·version 2 검증, 삭제 실환경 대기 | 부분 일치 | B3 통합 테스트 |
| 완료·다른 날짜 이동 | 동일 PATCH, 재예약 RPC 예정 | 단일 일정 변경 연결, 원자적 재예약 미구현 | 부분 일치 | B3 |
| 개인·업무·사용자 캘린더 | `/calendars` | 조회만 구현 | 부분 일치 | B2~B3 |
| 시작·종료·종일·마감 | `TodoInput` | 스키마·POST와 iOS DTO/client 구현 | 부분 일치 | B2 인증 연결 |
| 느슨한 시간대 | `timeBucket`, Task의 nullable start/end | 시간 없는 Task와 시간 추가·제거 UI 구현 | 일치 | B2 인증 연결 |
| 알림 | `reminderOffsetMinutes: Int?` | 정수 분 계약 | typed picker와 정수 Domain 값으로 수정 | B2 API 연결 |
| 장소 검색 | 구조화 `Location` | 구조화 스키마 지원 | MapKit 좌표·주소·provider 구조체로 수정 | B2 API 연결 |
| 반복 | `ScheduleRule`, RRULE subset | UI preset만 있고 DB/API 실행 없음 | 단계 대기 | B5 |
| 검색 | 제목·메모·장소 + 구조 필터 | UI 로컬 검색, 서버 미구현 | 계약 보완 필요 | B7 |
| Google 일정 필터 | `CalendarSource`, `CalendarEntry` mirror | 샘플 Google 일정만 있음 | 시연 UI | B8 |
| 하루 요약·미완료 처리 | `DailyReview`, `ReviewResponse` | 로컬 fixture 처리 | 단계 대기 | B6 |
| 지난 7일·30일 요약 | `/insights/weekly` + 기간 집계 | 로컬 계산만 있음 | 계약 보완 필요 | B6 이후 |
| 요약·계획 알림 시간 | `UserPreferences` | Settings 로컬 `@State`뿐 | 단계 대기 | B6 |
| 브리핑 키워드·3~5개 뉴스 | BriefingKeyword/DailyBriefing | fixture 제거, 연결 대기 상태 표시 | 단계 대기 | B9 |
| 상시 Agent·노트 도구 | AgentRun/PlanDraft/Proposal | 고정 응답으로만 동작 | 시연 UI | B10 |
| AI 동의·데이터 관리 | ConsentRecord/export/delete | 설명 시트만 있음 | 단계 대기 | B10·B13 |
| Google·Slack 연결 버튼 | DataConnection/OAuth | 버튼 action이 비어 있음 | 시연 UI | B8·B11 |
| 위젯과 딥링크 | App Group WidgetSnapshot | 앱 조회 결과 snapshot 연결, delta sync 미구현 | 부분 일치 | B4 |
| Google·GitHub·Apple 로그인 | Supabase Auth | anonymous session·화면·callback 완료, Google/GitHub credential과 Apple 대기 | 부분 일치 | B1·B13 |

## 3. 즉시 고쳐야 하는 모델 불일치

### 3.1 iOS 일정 모델

현재 `ScheduleDetail`은 화면 시연 모델이다. 서버 연결 때 다음 타입을 그대로 네트워크 모델로 사용하지 않는다.

| 현재 UI 필드 | 서버 정규 값 | 결정 |
|---|---|---|
| `isDone: Bool` | `status` + `progress` + `completedAt` | Domain에서 명시적 상태 enum 사용 |
| `reminder: String` | `reminderOffsetMinutes: Int?` | UI 표시 문자열은 formatter가 생성 |
| `location: String` | name/address/coordinate/provider/providerId | 구조화 값 객체로 교체 |
| `repeatRule` | nullable `scheduleRuleId` + 별도 ScheduleRule | 저장 시 preset을 규칙 command로 변환 |
| `calendar.provider` | Memdo calendar와 external source 분리 | 외부 이벤트를 Todo calendar로 위장하지 않음 |
| `day: Int` | 사용자 timezone의 `scheduledDate` | Domain은 분리 완료, 화면 fixture와 sample 생성 제거 필요 |
| 없음 | `timeBucket` | Task가 시간 없음/오전/오후/저녁/언제든을 표현하도록 Domain에 추가 |
| `source` 계산값 | manual/ai/recurring/imported + sourceProvider | 생성 출처와 표시 공급자를 분리 |

추가 코드 감사:

- 장소 선택은 현재 Apple MapKit 검색 결과를 합친 문자열로 저장한 뒤 Google Maps 검색 URL만 연다. B2에서는 MapKit 결과를 `provider=apple_maps`, 좌표·주소와 함께 저장하고 Google Maps는 좌표 기반 외부 열기로만 사용한다. Google Places API는 별도 필요성이 생기기 전에는 추가하지 않는다.
- Daily Summary의 삭제 문구가 30일 soft delete 정책과 충돌해 이번 감사에서 “목록에서 삭제”로 수정했다. 복구 UI가 생기기 전에는 영구 삭제나 복구 가능을 모두 약속하지 않는다.
- Today/Calendar/DailySummary와 일부 Widget은 2026-07 fixture, 한국어 요일 배열, `ko_KR` locale을 직접 사용한다. B2의 실제 Clock/locale 전환 전에는 production data 연결을 완료로 보지 않는다.
- Widget의 timeline 갱신은 이번 감사에서 `Calendar.date(byAdding:.day)`로 수정했다. 일정과 개수는 아직 정적이므로 B4에서 App Group snapshot으로 교체한다.
- Widget URL은 현재 `memdo://` custom scheme만 사용하지만 정규 계약은 Universal Link다. domain 연결 전에는 scheme fallback을 허용하고 B4에서 두 URL을 같은 `AppRouter` route로 검증한다.
- Daily Summary는 Bool 완료 여부만으로 지난 작업을 “놓침”으로 분류한다. `skipped/rescheduled/cancelled/partial` 상태가 연결되기 전에는 서버 집계와 동일하다고 볼 수 없다.

### 3.2 검색 계약

UI 문구와 실제 검색은 제목·메모·장소를 약속한다. 따라서 서버 검색의 정규 대상도 다음으로 고정한다.

```text
title
note
location_name
location_address
```

첫 인덱스는 `title`의 `pg_trgm`만 만든다. 날짜·사용자 범위로 먼저 줄인 뒤 메모·장소를 검사하고, p95가 200ms를 넘을 때 결합 GIN 인덱스를 검토한다. 인덱스를 만들기 전과 후에 같은 대표 쿼리의 `EXPLAIN (ANALYZE, BUFFERS)` 증거를 PR에 첨부한다.

## 4. DTO와 책임 분리 기준

DTO 패턴은 경계에서만 사용한다. 한 데이터를 이름만 바꿔 감싼 타입을 여러 개 만들지 않는다.

### iOS

```text
TodoResponseDTO        API JSON decode 전용
Schedule              앱 도메인 상태와 불변 조건
LocalScheduleRecord   SwiftData 저장 전용
ScheduleMapper        DTO ↔ Domain ↔ Local 변환
ScheduleRepository    로컬 우선 저장·sync 조정
```

- SwiftUI View는 `Schedule`만 읽고 사용자 intent를 전달한다.
- View가 `URLSession`, SwiftData, API DTO를 직접 사용하지 않는다.
- `ReminderOption`, `LocationValue`, `ScheduleStatus`가 검증과 표시 단위의 정답이다.
- DTO의 서버 enum을 알 수 없으면 decode 전체를 실패시키지 않고 `unknown(rawValue)` 또는 명시적 호환 오류로 처리한다.

### 서버

```text
HTTP handler
→ zod Request DTO 검증
→ command/query 함수
→ Supabase query 또는 SQL RPC
→ Response DTO mapper
```

- DB `snake_case` row를 API `camelCase`로 내보내는 변환은 `_shared/*-contract.ts` 한 곳에 둔다.
- 상태 전이, 멱등성, version 검사는 mapper가 아니라 command/RPC가 담당한다.
- 사용자 JWT/RLS 경로는 Supabase client를 유지한다.
- Drizzle ORM은 복잡한 trusted worker 쿼리가 실제로 생길 때만 사용한다. SQL migration이 schema의 유일한 원본이며 Drizzle migration을 병행하지 않는다.
- Repository interface, DI container, factory는 두 구현 또는 명확한 테스트 대역이 생기기 전에는 만들지 않는다.

## 5. 전송량과 조회 성능을 따로 관리한다

인덱스는 DB가 행을 찾는 비용을 줄이고 네트워크 payload를 직접 줄이지 않는다.

### DB 조회

- 실제 `WHERE + ORDER BY` 순서와 같은 복합·부분 인덱스
- FK 인덱스와 RLS 필터 선두 `user_id`
- OFFSET 금지, `(updated_at,id)` 또는 화면별 안정 cursor
- 매 단계 대표 쿼리 EXPLAIN 저장
- `pg_stat_statements`로 느린 쿼리와 사용되지 않는 인덱스 점검

### 데이터 송신

- 초기 전체 sync 뒤에는 `(updatedAt,id)` delta만 전송
- Todo 목록과 검색 결과는 서로 다른 최소 DTO 사용
- 페이지 50개, sync 200개 상한
- tombstone은 전체 삭제 객체 대신 id/version/deletedAt만 전송
- `GET /days`, preferences, briefing에 ETag/If-None-Match 적용
- provider 원본 payload, embedding, 내부 audit 필드는 iOS로 전송하지 않음
- 응답 byte, 반환 행 수, 압축 여부를 route template 기준으로 측정

## 6. 반복 로직과 글로벌화

### 반복 로직

- 검증은 zod/DB constraint/Domain invariant의 책임을 구분한다.
- 같은 상태 전이와 날짜 계산을 두 화면에 복사하지 않는다.
- 두 군데 이상에서 같은 책임으로 반복될 때만 shared helper/component로 올린다.
- 범용 `BaseRepository`, `BaseDTO`, `Utils` 파일은 만들지 않는다.

### 글로벌화

- Swift 사용자 문자열은 String Catalog(`Localizable.xcstrings`) 키로 관리한다.
- enum raw value에 한국어 표시 문자열을 저장하지 않고 안정 영문 code와 localized label을 분리한다.
- 날짜·시간·숫자는 `FormatStyle`, 사용자 locale/calendar/timezone으로 표시한다.
- 서버 날짜는 ISO 8601, 현지 날짜는 `YYYY-MM-DD`, timezone은 IANA ID로 저장한다.
- 주 시작 요일과 12/24시간제는 locale을 따르고 도메인 계산에 한국 기준 상수를 넣지 않는다.
- 검색 정규화는 Unicode NFC, 대소문자·공백 정규화를 적용하되 원문은 보존한다.
- Agent 요청에는 locale, timezone, response language를 명시하고 도메인 enum은 번역하지 않는다.
- 최소 검증 locale은 `ko-KR`, `en-US`; timezone은 `Asia/Seoul`, `America/Los_Angeles`; DST 경계 테스트를 포함한다.

## 7. 기능 PR의 완료 게이트

```text
UI 진입·빈/로딩/오류/성공 상태
+ Domain model과 불변 조건
+ Request/Response DTO와 OpenAPI
+ migration/RLS/index/transaction
+ 최소 payload와 pagination
+ metric/log/trace 이름
+ ko-KR/en-US 및 timezone 테스트
+ 실행 가능한 contract/integration/iOS test
```

하나라도 빠지면 해당 로드맵 항목은 `완료`가 아니다.
