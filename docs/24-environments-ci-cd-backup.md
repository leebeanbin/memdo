# 환경·CI/CD·백업·복구

> 기술 스택: [기술 스택 기준선](./22-technology-stack-baseline.md)  
> 커밋 규칙: [엔지니어링 규칙](./16-engineering-and-commit-rules.md)

## 1. 저장소

GitHub private repository 하나를 사용한다.

```text
apps/ios
apps/approval-web
services/mcp
supabase/functions
supabase/migrations
docs/product
.github/workflows
```

## 2. 환경

| 환경 | DB·API | Web | 목적 |
|---|---|---|---|
| local | Supabase CLI | Vite local | 개발 |
| staging | Supabase Free project 1 | Pages preview/staging | 통합 검증 |
| production | Supabase Free project 2 | Pages production | 50명 파일럿 |

Free production 프로젝트는 내부 50명 파일럿 전용이다. 실제 공개 사용자 데이터를 받기 7일 전까지 Supabase Pro 전환과 자동 백업 복원 연습을 완료한다.

## 3. 비밀

저장 위치:

- Supabase project secrets
- Cloudflare encrypted secrets
- Xcode Cloud environment variables
- GitHub Actions encrypted secrets

금지:

- `.env` commit
- Xcode project file에 서버 key
- 클라이언트의 Supabase service-role key
- 문서와 CI 로그에 token 출력

환경 변수 이름은 [외부 API 네이밍](./15-external-integrations-and-naming.md)을 따른다.

## 4. GitHub Actions

PR마다 Linux runner:

```text
Markdown link check
OpenAPI YAML parse
OpenAPI lint
TypeScript format/typecheck/test
Supabase local migration reset
SQL unit/RLS tests
secret scan
```

main merge:

```text
staging migration
staging Edge Functions
approval web deployment
synthetic smoke test
manual production approval
production migration
production Edge Functions
```

무료 GitHub Actions 2,000분을 보호하기 위해:

- path filter
- dependency cache
- 중복 실행 취소
- iOS build 제외

## 5. Xcode Cloud

PR:

- build
- unit test

main:

- build
- unit/UI test
- archive
- TestFlight internal

Apple Developer Program의 월 25시간 포함량을 기준으로 긴 UI matrix를 매 commit 실행하지 않는다.

## 6. Cloudflare Pages

- PR preview deployment
- main production deployment
- 승인 웹 smoke test
- `apple-app-site-association` 검증

Pages는 GitHub integration으로 자동 배포한다.

## 7. DB migration

- Supabase CLI migration 파일만 사용
- remote Dashboard에서 직접 schema 변경 금지
- PR에서 `supabase db reset`
- main merge 후 staging 적용
- smoke test 후 production 적용
- 이미 배포한 migration 수정 금지
- 실패는 새로운 forward-fix migration

파괴 변경:

```text
expand
→ backfill
→ application switch
→ contract
```

한 배포에서 컬럼 삭제와 코드 전환을 동시에 하지 않는다.

## 8. 배포 순서

호환 가능한 순서:

```text
1. additive DB migration
2. server code
3. approval web
4. iOS
5. cleanup migration
```

iOS 구버전이 남아 있으므로 API 필드를 즉시 제거하지 않는다.

## 9. 무료 DB 백업

Supabase Free는 자동 백업이 없으므로 매일 논리 백업한다.

```text
GitHub Actions scheduled workflow
→ supabase db dump
→ age 또는 AES-256-GCM 암호화
→ Cloudflare R2 Standard upload
→ SHA-256 checksum
→ backup manifest 기록
→ Grafana backup age metric
```

R2:

- private bucket
- public access 차단
- 14개 daily backup 유지
- 8개 weekly backup 유지
- 오래된 daily 자동 삭제

암호화 key는 R2와 다른 secret store에 둔다.

## 10. 복구

월 1회 staging에서 복구 훈련:

```text
새 local/staging DB
→ schema migration
→ encrypted dump download
→ decrypt
→ restore
→ row counts·RLS·핵심 query 검증
```

파일럿 목표:

```text
RPO: 24시간
RTO: 4시간
```

공개 출시에서 더 작은 RPO가 필요하면 Supabase Pro/PITR을 검토한다.

## 11. 배포 롤백

- web/Worker: 이전 Cloudflare deployment
- Edge Function: 이전 commit 재배포
- iOS: server-side feature flag로 기능 차단
- DB: down migration보다 forward fix

## 12. Feature flags

DB 설정으로 다음을 끌 수 있게 한다.

```text
ai_planning
news_briefing
google_calendar_write
remote_mcp
```

Google read-only와 기본 Todo는 하나의 global flag 장애에 묶지 않는다.

## 13. 비용 방지

- GitHub budget alert와 초과 사용 차단
- Cloudflare usage notification
- Grafana usage dashboard
- OpenAI 일·월 예산
- Supabase usage 70/90% 알림
