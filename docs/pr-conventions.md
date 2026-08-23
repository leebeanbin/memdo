# PR conventions

1인 프로젝트 기준 최소 규칙. 필요해지면 언제든 추가/수정한다 — 이 파일이 그 갱신 지점.
(`memdo-backend`에도 같은 이름의 문서가 있음 — 두 레포가 분리돼 있어 손으로 나란히 유지.)

## Labels

Type: `feat` / `fix` / `refactor` / `docs` / `chore` / `test` (커밋 prefix와 동일). PR엔 보통 1개.
GitHub 기본 라벨(`bug`/`enhancement`/...)도 남아있음 — 이슈에 자유롭게 사용.

## Assignee

PR 작성자 본인을 항상 assignee로 지정 (`gh pr create --assignee @me`).

## Reviewers

비워둔다 — 1인 프로젝트라 GitHub Reviewers 승인 기능은 쓰지 않는다.
"본인이 봐야 한다"는 PR 템플릿의 Review 체크리스트로 형식화한다.

## Milestone

Sprint 단위로, 그 스프린트를 시작할 때 그때그때 만든다. 이름: "Sprint N" (필요하면 "Sprint N · Epic X").

## Projects

현재 미사용. 필요해지면 별도로 결정.

## CI

`.github/workflows/ci.yml`이 모든 PR에서 자동 실행되고(macOS 러너에서 `xcodegen generate` +
`xcodebuild build`/`test`), `main` 브랜치 보호 규칙이 이 체크 통과를 머지 조건으로 요구한다.
