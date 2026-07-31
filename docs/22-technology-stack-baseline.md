# 기술 스택 기준선

상태: 확정  
적용 범위: 50명 파일럿과 MVP  
변경 방법: ADR 추가 후 이 문서와 배포·OpenAPI·엔지니어링 문서를 함께 수정

## 1. 프로그래밍 언어

| 영역 | 언어 | 기준 |
|---|---|---|
| iOS 앱·위젯 | Swift | Swift 6 language mode |
| 서버 API·작업 | TypeScript | TypeScript 5.x |
| MCP 서버 | TypeScript | TypeScript 5.x |
| 승인 웹 | TypeScript | TypeScript 5.x |
| DB·RLS·migration | SQL | PostgreSQL SQL |
| CI·설정 | YAML·Shell | 최소 스크립트 |

Python, Kotlin, Go를 동시에 도입하지 않는다. OpenAI Agents SDK Python은 MVP에서 사용하지 않는다.

## 2. iOS 기준선

```text
Deployment Target: iOS 17
Language: Swift 6
UI: SwiftUI
Local Database: SwiftData
Dependency Manager: Swift Package Manager
```

Apple 프레임워크:

- WidgetKit
- App Intents
- UserNotifications
- EventKit
- AuthenticationServices
- OSLog
- MetricKit
- CryptoKit

외부 패키지:

- Sentry Cocoa: crash와 성능 오류 수집

추가하지 않는 패키지:

- 별도 UI 프레임워크
- 별도 DI 프레임워크
- 별도 네트워크 라이브러리
- 별도 로컬 DB

네트워크는 `URLSession`, 의존성 주입은 initializer, 로깅은 `Logger`를 사용한다.

## 3. 서버 기준선

```text
Cloud: Supabase Free
Runtime: Supabase Edge Runtime
Language: TypeScript
Runtime Compatibility: Deno
Database: Managed PostgreSQL
Auth: Supabase Auth
Scheduler: Supabase Cron
Region: Seoul ap-northeast-2
```

필수 패키지:

- `@supabase/supabase-js`
- `openai`
- `zod`

라우팅 프레임워크는 처음부터 추가하지 않는다. Edge Function은 기능별 진입점과 공통 모듈로 시작한다. 경로 수와 middleware 중복이 실제로 커질 때 Hono 같은 경량 router를 검토한다.

## 4. 승인 웹

```text
Language: TypeScript
Build: Vite
UI: HTML + CSS + TypeScript
Hosting: Cloudflare Pages Free
Auth: Supabase Auth
```

승인·거절·로그인 복귀 화면만 필요하므로 React를 넣지 않는다. 화면이 세 개 이상의 복잡한 상태 흐름으로 커질 때만 프레임워크를 재검토한다.

Cloudflare Pages가 제공할 정적 파일:

```text
approval page
privacy policy
terms
support
.well-known/apple-app-site-association
```

## 5. MCP 서버

Phase C에서만 배포한다.

```text
Language: TypeScript
Runtime: Cloudflare Workers
Transport: Streamable HTTP
Hosting: Workers Free
Business Logic: Memdo API 호출
```

MCP Worker는 DB에 직접 연결하지 않는다. OAuth 검증, 도구 schema, Memdo API 변환만 담당한다.

## 6. 데이터와 저장소

```text
Primary DB: Supabase PostgreSQL
App local data: SwiftData
Widget snapshot: App Group JSON
Backup object storage: Cloudflare R2 Standard
```

초기 미사용:

- Redis
- Kafka
- Elasticsearch
- 별도 vector DB
- 읽기 복제본
- materialized view
- 테이블 파티셔닝

## 7. 외부 서비스

| 목적 | 선택 |
|---|---|
| AI 계획·뉴스 검색·요약 | OpenAI Responses API, `gpt-5.6-luna` |
| Google 일정 | Google Calendar API |
| Apple 일정 | EventKit |
| Push | APNs |
| 서버 관찰 | Grafana Cloud Free |
| iOS crash | Sentry Developer Free |
| 소스·PR | GitHub |
| iOS CI | Xcode Cloud |
| 서버·문서 CI | GitHub Actions |

뉴스는 MVP에서 Responses API의 `web_search` 도구를 사용한다. 기사 제목·매체·게시 시각·원문 URL을 보존하고, 출처 없는 항목은 버린다. 정식 뉴스 API나 RSS 수집기는 호출 비용 또는 검색 품질이 전환 기준을 넘기 전에는 추가하지 않는다.

## 8. 무료 클라우드 배치

### Supabase Free

사용:

- Auth
- PostgreSQL
- RLS
- Edge Functions
- Cron

50명에는 충분하지만 다음 제한을 운영 문서에 반영한다.

- DB 500MB
- Free 프로젝트 inactivity pause
- 자동 백업 없음
- API·DB 로그 보존 1일
- metrics endpoint 없음

### Cloudflare Free

사용:

- Pages: 승인 웹과 Universal Link 파일
- Workers: 향후 MCP
- R2: 암호화 DB dump

### Grafana Cloud Free

사용:

- Prometheus 호환 metrics
- Loki logs
- Tempo traces
- synthetic API checks

직접 Prometheus와 Grafana 서버를 운영하지 않는다.

### CI

- GitHub Actions: OpenAPI·문서·TypeScript·SQL 검증
- Xcode Cloud: iOS build·unit test·TestFlight

GitHub macOS runner로 iOS를 매 commit 빌드하지 않는다. iOS는 Xcode Cloud의 포함 시간을 사용한다.

## 9. 비용이 발생하는 항목

완전 무료 프로젝트라고 가정하지 않는다.

- Apple Developer Program
- OpenAI API 사용량
- 도메인 등록
- 무료 티어 초과
- 출시 안정성을 위한 Supabase Pro 전환

OpenAI에는 월 예산 한도와 사용자별 호출 한도를 설정한다.

기본 서버 설정:

```text
MYDAY_OPENAI_MODEL=gpt-5.6-luna
MYDAY_NEWS_PROVIDER=openai_web_search
```

모델명은 코드에 직접 쓰지 않는다. 출시 전 고정 평가셋에서 정확도와 구조화 출력 성공률을 확인하고, 기준 미달이면 같은 환경 변수만 더 강한 모델로 바꾼다.

## 10. 환경

```text
local
staging
production
```

Supabase Free의 활성 프로젝트 2개 제한 때문에:

- local: Docker 기반 Supabase CLI
- staging: Free project 1
- production: Free project 2

PR별 DB branch는 사용하지 않는다.

Cloudflare:

- PR preview: Pages preview deployment
- production: main branch

## 11. 버전 고정

저장소에 다음을 둔다.

```text
.swift-version
.xcode-version
deno.json
package.json
package-lock.json
supabase/config.toml
```

문서에는 major 기준만 기록하고 exact patch는 저장소 파일이 정답이다.

## 12. 전환 기준

### Supabase Pro

다음 중 하나면 즉시 검토:

- 실제 사용자 데이터로 공개 출시
- 자동 백업과 복구 SLA 필요
- DB 350MB 초과
- egress 70% 초과
- 1일 로그 보존으로 장애 분석 불가

공개 출시는 “검토”가 아니라 Pro 전환 완료를 필수 게이트로 한다. Free는 내부 50명 파일럿까지만 사용한다.

### 유료 Grafana

- 무료 ingestion 70% 초과
- 14일 이상 로그 보존 필요
- 관찰 사용자 3명 초과

### 별도 작업 큐

[데이터 파이프라인](./17-data-pipeline.md)의 확장 조건을 따른다.
