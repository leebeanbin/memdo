# Memdo

AI 일정 제안, 개인 캘린더, 하루 요약, 홈·잠금화면 위젯을 결합한 iOS 앱입니다.

## 현재 상태

- UI/UX 디자인 기준선: 확정
- 기준 기기: iPhone 15 (`393×852pt`)
- 최소 지원 버전: iOS 17
- iOS 일정 조회·생성·수정과 Widget snapshot: 원격 백엔드 왕복 검증 완료
- Google·GitHub 로그인: 앱 UI와 callback 구현 완료, OAuth client ID/secret 발급 대기
- **운동 기록**: Supabase 백엔드(workout_logs + Edge Function) 배포 완료, 새 일정 시트 분류에 통합
- **Dynamic Island Live Activity**: 일정 시작 전(카운트다운) → 진행 중(종료까지) → 완료(체크) 3단계 표시
- **사용자 정의 카테고리**: 이름·이모지·색상으로 나만의 일정 분류 추가
- **홈·잠금화면 위젯**: 오늘 위젯(소형·중형·잠금화면) + 달력 위젯(주간·월간)
- AI 실행, 브리핑, 외부 캘린더 동기화: 설계 완료·구현 예정

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
