# Memdo

AI 일정 제안, 개인 캘린더, 하루 요약, 홈·잠금화면 위젯을 결합한 iOS 앱입니다.

## 현재 상태

이 시점(2026-08-17)에서 계획된 개발 범위를 마쳤다. 아래는 최종 상태다.

- UI/UX 디자인 기준선: 확정
- 기준 기기: iPhone 15 (`393×852pt`)
- 최소 지원 버전: iOS 17 (Agent·Live Activity 등 일부 기능은 iOS 26+에서 전체 동작)
- iOS 일정 조회·생성·수정·재예약·반복·검색과 Widget snapshot: 원격 백엔드 왕복 검증 완료
- 오프라인 outbox: 네트워크 끊김 중 생성·수정·삭제를 큐에 저장하고 재연결 시 자동 재전송
- Apple·Google·GitHub 로그인: UI·callback 구현 완료, 자격 증명 구성 완료. 익명 세션 경로는 실제
  계정으로 검증됨; 세 provider 각각의 실기기 로그인 왕복은 출시 전 재확인 필요
  (`memdo-backend/docs/auth-social-login.md` 참고)
- **Google Calendar 연동**: 읽기 전용 미러(연결·해제·재인증), Today/캘린더 통합 타임라인에 출처 배지로 표시
- **운동 기록**: Supabase 백엔드(workout_logs + Edge Function) 배포 완료, HealthKit 자동 가져오기, 새 일정 시트 분류에 통합
- **Dynamic Island Live Activity**: 일정 시작 전(카운트다운) → 진행 중(종료까지) → 완료(체크) 3단계 표시, 운동 전용 Live Activity 별도 지원
- **사용자 정의 카테고리**: 이름·이모지·색상으로 나만의 일정 분류 추가, 서버 동기화
- **홈·잠금화면 위젯**: 오늘 위젯(소형·중형·잠금화면) + 달력 위젯(주간·월간)
- **오늘의 브리핑**: 관심 키워드 기반 RSS 수집 + 온디바이스 AI 요약 (서버를 거치지 않음)
- **Slack 알림**: 사용자가 발급한 Incoming Webhook URL을 Keychain에 저장해 일정 생성·완료 알림 전송
- **Memdo Agent**: 온디바이스(Apple FoundationModels, Reflection 포함 대화·일정 제안·빈 시간 찾기)와
  클라우드(사용자 BYOK OpenRouter 키, streaming, 모델 선택) 두 경로 모두 구현 완료. 기존 ChatGPT
  Plus/Claude Pro·Max 같은 구독 재사용은 API 미제공 또는 서드파티 도구에 대한 이용약관 위반이라 채택하지 않았다.
- 계정 없는 시작: 익명 게스트 자동 로그인 후 계정 연결로 승격
- 공유 확장(Share Extension): 외부 앱에서 운동 기록 공유
- 미구현: Memdo Remote MCP(Codex/ChatGPT 등 외부 AI 연동), 비 Apple-Intelligence 기기용 온디바이스
  fallback 모델(스코프만 확정), 운영 dashboard·자동 백업

원래 설계와 실제 구현이 갈라진 지점은 [`docs/10-decisions-and-open-questions.md`](docs/10-decisions-and-open-questions.md)의
ADR-073~075와, [`../memdo-backend/docs/roadmap.md`](../memdo-backend/docs/roadmap.md)의
"원래 설계와 실제 구현이 달라진 부분"을 따른다.

## 먼저 읽기

1. [제품 뇌 지도](docs/00-product-brain-map.md)
2. [제품 요구사항](docs/01-product-requirements.md)
3. [최종 UI/UX 기준선](apps/ios/Memdo/DESIGN.md)
4. [기술 아키텍처](docs/03-technical-architecture.md)
5. [데이터 모델과 ERD](docs/04-data-model.md)
6. [API 명세](docs/05-api-spec.yaml)
7. [구현·커밋 규칙](docs/16-engineering-and-commit-rules.md)
8. [백엔드 구현 실행 계획](docs/30-backend-implementation-plan.md)

전체 문서 순서는 [문서 인덱스](docs/README.md)를 따릅니다.

## iOS 프로젝트

```text
apps/ios/Memdo/
├── Memdo/                 앱 화면과 디자인 토큰
├── MemdoWidget/           홈·잠금화면 위젯
├── Memdo.xcodeproj
├── DESIGN.md              UI/UX 단일 기준 문서
└── project.yml
```

Xcode에서 `apps/ios/Memdo/Memdo.xcodeproj`를 열어 `Memdo` 스킴을 실행합니다.

## 최종 디자인 시안

최종 승인 시안은 [`design/previews`](design/previews)에만 보관합니다. `outputs`는 디자인 탐색 과정의 산출물이며 저장소에서 제외합니다.
