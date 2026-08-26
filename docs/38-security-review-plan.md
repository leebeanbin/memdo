# 38. Security Review Plan (Personal Team Dogfood Window)

> 기존 보안 테스트 항목: [`08-test-and-release-plan.md` §6](./08-test-and-release-plan.md#6-보안개인정보-테스트)(체크리스트만, 실행 계획은 없었음)
> 개인정보 정책: [`06-privacy-consent-ai-policy.md`](./06-privacy-consent-ai-policy.md)
> 병행 진행: [`37-founder-dogfooding-protocol.md`](./37-founder-dogfooding-protocol.md)(UX/기능 검증, 이 문서와는 별개 관심사)

## 범위

4개 영역을 다룬다: **(A) 코드 레벨 감사, (B) 의존성/공급망 점검, (C) 라이브 API 침투 테스트,
(D) 기기 로컬 보안**. `08` §6은 이미 존재하는 체크리스트 항목(RLS 우회, 다른 사용자 UUID 접근,
동의 철회, 로그 민감정보, 번들 API 키, 위젯 숨김, 계정 삭제)을 그대로 유지한다 — 이 문서는 그
항목들을 대체하지 않고, **어떻게/언제/누가 실행하는지**를 추가한다.

**중요한 구분**: A/B/D는 로컬 코드/설정 감사라 안전하게 바로 진행 가능하다. **C(라이브 API
침투 테스트)는 실제 프로덕션 Supabase 프로젝트를 대상으로 하므로, 이 세션의 기존 원칙(프로덕션에
영향을 줄 수 있는 명령은 사전 승인 없이 실행하지 않음)에 따라 **각 테스트 항목마다 실행 직전에
명시적 승인을 받는다** — 한 번의 승인이 이 문서 전체를 미리 승인한 것으로 간주하지 않는다.

## A. 코드 레벨 감사

`memdo`(iOS)와 `memdo-backend`(Supabase/Deno) 양쪽 코드를 정적으로 읽고 감사한다. 실행 인프라
변경 없음.

- [x] **RLS 강제 여부** — 이미 확인: `force row level security`가 있는 마이그레이션 12개 전부에
  `alter table ... force row level security` 존재(2026-08-26 확인, `grep`으로 전수 검사). 앞으로
  새 테이블 추가 시 이 패턴이 깨지지 않는지 PR 리뷰 시 확인하는 습관으로 유지(자동화된 CI 체크는
  이번 범위 밖).
- [x] **인증/인가 경로 감사(1차, 2026-08-26)** — 공격자 관점으로 확인:
  - Google Calendar OAuth 콜백(`google-calendar-callback`, `verify_jwt=false`) — Memdo
    세션/JWT 없이 Google이 직접 리다이렉트하는 요청이라 `state`가 유일한 인증 근거인데, 이게
    1회용 nonce로 `delete ... returning`(원자적 소비) + 만료 체크까지 되어 있어 재사용/추측
    공격이 막힘. 값도 최소한만 노출(`status`/`reason`만, 토큰 없음).
  - Apple/Google/GitHub 로그인은 `MemdoApp.swift`가 `ASWebAuthenticationSession`을 사용 —
    콜백을 iOS가 발신 앱에만 격리해서 전달하므로, 아래에서 발견한 `memdo://` 커스텀 스킴 문제의
    영향을 받지 않음.
  - `apple-auth-contract.ts`에 `console.*` 호출이 아예 없음 — private key가 로그로 새어나갈
    코드 경로 자체가 없음(grep 전수 확인).
  - **새로 발견(낮은 심각도)**: `memdo://`는 Associated Domains/Universal Link가 아니라 순수
    custom URL scheme(`Info.plist` `CFBundleURLSchemes`) — 이론상 다른 앱이 같은 스킴을 등록해
    가로챌 수 있음. 로그인은 위처럼 보호되고, 이 스킴으로 실제 오가는 값(캘린더 연결 콜백 status,
    알림 딥링크)엔 토큰/secret이 없어 실질 피해는 낮음. 고치려면 유료 Program + 도메인 필요 —
    지금 고칠 가치는 낮음, 기록만 하고 넘어감.
  - 남은 범위: `account`/`agent-key`/`apple-auth-token-exchange` 외 나머지 함수들의 `user_id`
    신뢰 경로 전수 확인은 아직 안 함(표본만).
- [x] **secret 취급 일관성(2026-08-26)** — Vault RPC 4개(`vault_create/read/update/
  delete_secret`)가 `SECURITY DEFINER` + `set search_path = ''`(search_path 인젝션을 통한
  권한 상승 방지) + `revoke ... from public, authenticated, anon` 후 `service_role`에만
  `grant`하는 패턴으로 정의됨(`202608090004_google_calendar_mirror.sql`) — anon/authenticated
  키가 유출돼도 이 RPC들을 직접 호출해 다른 사용자의 secret을 읽을 수 없음. `user_api_keys`/
  `apple_oauth_tokens`/`google_calendar_connections` 전부 동일 패턴으로 확인.
- [ ] **에러 로깅 정제 여부** — `apple-auth-contract.ts`는 `error instanceof Error ?
  error.message : String(error)` 패턴(안전)을 쓰는 반면, `agent-key/index.ts`의 여러
  `console.error`(예: 25, 79, 96, 111, 123줄)는 `JSON.stringify({..., error})`로 **캐치된 에러
  객체 전체**를 로그로 남긴다. 현재 호출 지점에서 이 `error`는 Postgres/PostgREST/Vault RPC 에러
  객체(`{message, code, details, hint}`)라 API 키 원문이 포함될 가능성은 낮다고 판단되지만(Vault
  RPC 에러가 입력 파라미터를 echo하지 않음), `error.message`만 남기는 안전한 패턴으로 통일하는
  걸 권장 — **P2, dogfooding 중 여유 있을 때 정리, 급하지 않음**.
- [ ] **입력 검증** — 모든 mutation 엔드포인트가 zod 스키마로 파싱하는지(`*.safeParse`) 표본
  확인 — 이미 다수 확인됨(`accountDeletionRequestSchema`, `appleTokenExchangeRequestSchema`,
  `agentKeySaveSchema` 등), 나머지 함수 표본 점검.
- [x] **CORS 설정(2026-08-26)** — `_shared/http.ts`에 CORS 헤더 자체가 없음. 취약점 아님 —
  native 클라이언트 전용 백엔드고 cookie가 아니라 bearer JWT를 쓰므로 브라우저 CORS는 애초에
  이 시스템의 보안 경계가 아님.
- [ ] **rate limit 우회 가능성** — `agent-cloud-chat`의 rate limit(`resolveRateLimitPerHour`)이
  우회 가능한 경로가 없는지 확인(실제 다수 요청을 보내야 하므로 §C 라이브 테스트 표에 포함, 승인
  후 진행).
- [ ] **번들에 secret 없음 재확인** — `08` §6에 이미 있는 "앱 번들에 API 키 없음" 항목을 이번에
  `strings`/grep으로 Release 빌드 산출물에 대해 재실행(Epic K 이후 코드가 늘었으므로 재확인 가치
  있음).

## B. 의존성/공급망 점검

- [x] **iOS SPM 의존성 8개 확인**(`Package.resolved`, 2026-08-26): `supabase-swift 2.54.1`,
  `swift-asn1 1.7.1`, `swift-clocks 1.1.0`, `swift-concurrency-extras 1.4.1`,
  `swift-crypto 4.5.1`, `swift-http-types 1.6.0`, `xctest-dynamic-overlay 1.11.0`,
  `yams 6.2.2` — 전부 Apple/Point-Free/Supabase/jpsim 등 알려진 유지보수 조직, 수상한 출처 없음.
- [ ] **알려진 취약점 확인** — 위 8개 패키지에 대해 GitHub Security Advisories(각 repo의
  Security 탭) 또는 `gh api`로 CVE 유무 확인. Swift Package Manager 자체에는 `npm audit` 같은
  내장 스캐너가 없으므로 수동 확인.
- [ ] **버전 최신성** — 각 패키지가 현재 실제 릴리스 대비 얼마나 뒤처졌는지 확인(치명적 보안
  패치가 있는데 안 올라간 게 없는지만 — 기능 업그레이드 목적 아님).
- [ ] **memdo-backend Deno import 감사** — `deno.json`의 import map(`@supabase/supabase-js`,
  `zod` 등)이 pin된 버전인지, 알려진 취약점이 있는지 확인.
- [ ] **자동화 여부 결정(제안, 이번에 만들지 않음)** — GitHub Dependabot을 두 저장소에
  활성화할지 여부는 별도 결정 — 이번 문서 범위에서는 수동 1회 점검만 하고, 자동화는 필요성이
  확인되면 별도로 진행(v1.0 로드맵의 "미리 만들지 않는다" 원칙과 동일).

## C. 라이브 API 침투 테스트 — **각 항목 실행 전 개별 승인 필요**

프로덕션 Supabase 프로젝트를 대상으로 하므로, **테스트 전용 계정(본인의 실제 계정이 아닌)**으로
진행한다. 아래 항목은 실행 계획일 뿐 — 승인 없이는 어느 것도 실행하지 않는다.

| 테스트 | 방법 | 기대 결과 |
|---|---|---|
| 다른 사용자 UUID로 접근 | 계정 A로 인증한 JWT로 계정 B의 `todos`/`preferences` 등에 GET 요청 | RLS에 의해 빈 결과 또는 403 |
| RLS 우회 시도 | anon key로 service-role 전용 함수(`account` DELETE 등) 직접 호출 | 인증 실패(401/403) |
| JWT 변조 | 만료/서명 조작된 JWT로 요청 | 거부 |
| `DELETE /account`에 confirmation 없이 요청 | `{}` 바디로 호출 | 400(zod 스키마 거부, `accountDeletionRequestSchema`) |
| rate limit 우회 | `agent-cloud-chat`에 짧은 시간 내 다수 요청 | 설정된 시간당 한도에서 차단 |
| Apple revoke fail-open 검증 | 저장된 refresh token을 의도적으로 무효화한 뒤 계정 삭제 요청 | Apple revoke 실패해도 계정/데이터 삭제는 정상 완료(설계된 fail-open 동작 재확인) |

이 표의 각 행은 실제로 실행하기 전에 대화에서 "이 항목 지금 실행해도 돼"라는 명시적 승인을
받는다. 실행 결과는 `dogfood-log.md`에 `DATA_INTEGRITY` 또는 `BUG` 카테고리로 기록한다.

## D. 기기 로컬 보안

- [x] **Keychain 미사용 확인**(2026-08-26, grep): `Memdo/` 어디에도 `Keychain`/`kSecClass` 참조
  없음 — OpenRouter BYOK 키는 서버(Vault)에만 저장되고 기기에 캐시되지 않는다(기존 세션에서
  확인된 사실, 이번에 코드로 재확인).
  App Group(`UserDefaults(suiteName:)`)에 저장되는 데이터가 스케줄 제목/시간 등 일반 데이터뿐이고
  인증 토큰/API 키가 저장되지 않는지 재확인(`MemdoWidgetSchedule.swift`의 `MemdoWidgetSnapshot`
  구조체 필드 확인 — 이미 위젯 관련 조사에서 스케줄 데이터만 담는 것으로 확인됨).
- [ ] **Personal Team 빌드 특이사항**: `personal-team-dogfood` 브랜치는 App Groups 자체가
  꺼져 있어(`36` 참고) 오히려 로컬 데이터 공유 표면이 **main보다 줄어든** 상태 — 이 브랜치
  고유의 새로운 로컬 보안 노출은 없음(위젯이 아예 데이터를 받지 못하므로).
- [ ] **UserDefaults.standard 폴백 확인**: App Group을 못 쓸 때 `@AppStorage`가
  `UserDefaults.standard`로 폴백하는 항목(`hideContentKey` 등)이 기기의 다른 앱에서 접근
  가능한 값이 아닌지 확인(iOS 앱 샌드박싱상 다른 앱은 애초에 접근 불가 — 이론적 확인 차원).

## 실행 순서 제안

1. A(코드 감사) → B(의존성) 먼저 진행 — 로컬 작업, 승인 불필요, dogfooding과 병행 가능.
2. D(기기 로컬 보안)는 A와 병행 가능.
3. C(라이브 API 테스트)는 A/B가 끝난 뒤, 테스트 계정을 준비하고 항목별로 승인받으며 진행.

## 결과 반영

발견된 이슈는 `dogfood-log.md`에 기록하고, `37`의 triage policy를 그대로 따른다 — P0/P1
correctness/data-loss 성격이면 즉시 수정, 그 외는 severity에 따라 v1.0 polish 또는 백로그로
분류한다. 이 문서 자체의 체크박스는 실제로 확인/수정된 항목만 `[x]`로 갱신한다.
