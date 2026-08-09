# UI 그리드·모달 감사

기준 기기: iPhone 15 시뮬레이터  
기준일: 2026-08-09
상태: 2차 공통 정합화 완료 · 전체 상태별 실기 점검 진행 중

## 공통 그리드

- 페이지의 제목, 섹션 제목, 목록 외곽선은 좌우 `18pt` 콘텐츠 축을 공유한다.
- 오늘·캘린더·설정 헤더는 같은 NavigationStack 상단 인셋에서 시작한다.
- 페이지 간격은 `MemdoPage`, 오늘 화면은 동일한 `MemdoMetrics.pagePadding`으로 소유한다.
- 일정·브리핑·오늘 요약 결정 행은 `12pt inset + 44pt 선행 열 + 8pt 간격`을 공유한다. 완료 원·시간축·브리핑 번호는 같은 중심축, 제목과 구분선은 같은 본문 시작축에 놓인다.
- 오늘 주간 인덱스와 월간 캘린더는 `MemdoScheduleCountDots`를 공유한다. 미완료 일정 수를 1–3개 점으로 축약하고 정확한 수는 선택 날짜 헤더와 VoiceOver 값에 둔다.
- 컴포넌트 내부 간격은 `4 / 8 / 12 / 16 / 20 / 24 / 28 / 32pt`를 사용한다. 페이지·섹션 밀도용 `18pt` 외곽 축과 `10pt` 섹션 내부 간격은 이름이 있는 역할 토큰으로만 허용한다. 선 두께, 밀도 점, 잠금화면 위젯처럼 시스템 크기 제약이 있는 장식도 예외다.
- 설정 열린 행 그룹의 외곽은 섹션 제목과 같은 `18pt` 축, 모든 행은 그룹 안쪽 `12pt` 축을 공유한다.
- 하단 탭 바는 네이티브 `TabView`가 소유하며 콘텐츠는 `72pt` 하단 여유를 둔다.

## Glass 제어 규칙

- Liquid Glass는 검색·필터·키워드 입력·헤더 액션·Agent composer와 하단 내비게이션에만 사용하고 일정·브리핑·설정 콘텐츠에는 적용하지 않는다.
- 캘린더 검색은 아이콘형 Glass 진입 버튼, Glass 검색 필드, 네이티브 segmented 범위 선택으로 이어진다.
- 월 필터는 우측 모서리에 고립시키지 않고 월 이동 제어 옆에 배치하며 현재 필터 이름을 항상 표시한다.
- 월간 그리드는 카드 없이 상하 Divider 사이에 두고 `8/10pt` 간격을 사용하며 이전·다음 달 버튼은 각각 `44×44pt`를 보장한다.
- 설정은 행마다 카드를 만들거나 비상호작용 Glass 패널로 감싸지 않는다. 입력처럼 직접 조작하는 표면만 interactive Glass를 사용한다.
- iOS 26에서는 interactive 조작층에 네이티브 `glassEffect`를 적용하고, 이전 버전은 material과 outline으로 대체한다. 긴 검색·입력 표면은 `12pt`, 44pt 아이콘 조작은 `22pt`를 사용한다.

## 곡률·형태 감사

- 네이티브 `Button`, `Menu`, `Picker`, `DatePicker`, `Toggle`, `sheet`, 탭바와 toolbar의 곡률은 시스템이 소유한다. 외형을 맞추기 위한 `clipShape`를 덧씌우지 않는다.
- Memdo 커스텀 표면은 `8 / 12 / 16 / 22 / 28pt / Capsule` 토큰만 사용한다. 각각 아이콘 배경 / 입력 / 콘텐츠 강조 / 큰 그룹 / 위젯·브랜드 표면 / 짧은 선택·상태를 뜻한다.
- 중첩된 둥근 표면은 `inner radius + inset = outer radius`를 만족해야 한다. 같은 반경을 부모와 자식에 복사하지 않는다.
- 인접한 입력과 버튼, 같은 행동 그룹의 버튼은 외곽 높이와 곡률 단계가 같아야 한다. 중요도는 크기 차이가 아니라 fill·label·배치로 표현한다.
- `RoundedRectangle`은 `.continuous`를 사용한다. 일회성 숫자 반경은 금지하며, 예외는 시스템 규격 또는 승인된 로고 geometry만 허용한다.
- Capsule은 날짜 선택, 필터 선택, 짧은 상태처럼 내용 길이에 따라 폭이 변해야 하는 요소에만 쓴다. 일반 카드와 긴 입력 필드를 pill로 만들지 않는다.

검수 시 `rg "cornerRadius|RoundedRectangle|Capsule|clipShape"`로 사용처를 찾고 토큰, 중첩 계산, 시스템 소유 여부를 확인한다.

## Apple 리소스 감사

- 디자인 시안은 Apple의 최신 iOS/iPadOS UI Kit와 비교하되, 구현은 네이티브 SwiftUI 컴포넌트를 기준으로 한다.
- 앱 아이콘은 App Icon Template과 Icon Composer, 기능 아이콘은 SF Symbols를 사용한다.
- 시스템 서체는 번들 에셋이 아니라 Dynamic Type을 지원하는 SwiftUI system font로 사용한다.
- Product Bezel과 기술별 마케팅 로고는 앱 UI 자산과 분리한다.
- Apple 공식 리소스가 없는 Google·GitHub·Slack 로고는 각 공급자의 공식 브랜드 에셋과 사용 규칙을 따른다.

## 2026-08-09 네이티브 셸 정합화 결과

- 앱 코드의 커스텀 곡률을 `MemdoMetrics`의 역할 토큰으로 통합하고 숫자를 직접 넣은 `RoundedRectangle`을 제거했다.
- interactive Glass fallback은 같은 modifier를 공유하되 긴 검색·Agent 입력은 `fieldRadius`, 44pt 아이콘 조작은 `groupRadius`를 사용한다.
- 오늘의 intention prompt는 브랜드 그라데이션과 흰색 장식 원을 제거하고 semantic Surface·Brand Soft만 사용한다.
- 캘린더 필터는 고립된 Glass 원 대신 현재 필터명이 보이는 네이티브 `Menu`로 바꿨다.
- 선택 날짜가 비어 있을 때의 큰 `ContentUnavailableView`는 일정 행과 같은 선행 열·본문 열을 쓰는 compact 상태 행으로 바꿨다.
- 오늘 요약의 오늘·7일·30일 빈 상태도 같은 44pt 선행 열의 compact 행으로 통일했다.
- 브리핑·캘린더·검색·요약의 빈/오류 상태는 공통 `MemdoStatusRow`를 사용해 아이콘 중심축과 본문 시작축의 화면별 편차를 제거했다.
- Agent 빠른 요청은 `44pt 선행 열 + 8pt 간격 + 12pt inset`으로 다시 배치하고 구분선을 본문 시작축에 맞췄다.
- 버튼 라벨을 강제로 축소하던 `minimumScaleFactor`를 제거해 Dynamic Type에서 글자 크기보다 레이아웃이 먼저 적응하게 했다.
- 시트 안의 오늘 요약은 탭바용 72pt 하단 여백을 사용하지 않는다.
- 일정 상세는 수정 옆 더보기 메뉴에서 삭제하고 `confirmationDialog`로 확인한다.
- 검색 요청 중에는 결과 없음 대신 compact 진행 행을 표시한다.
- 신규 anonymous session 진입을 제거하고 Apple·Google·GitHub 로그인 화면을 실제 인증 진입점으로 고정했다.
- iOS 26.5 `Memdo iPhone 15`에서 오늘·캘린더·검색·필터 메뉴를 다시 실행하고 탭바 겹침, 터치 대상, 선택 상태를 확인했다.

## 전환 규칙

- 탭 전환은 `TabView`, 화면 계층은 `NavigationStack`, 모달은 `sheet`와 `confirmationDialog`의 시스템 전환을 사용한다.
- 일정 추가·상세·요약·Agent는 서로 다른 정보 계층이므로 임의의 zoom/matched transition을 붙이지 않는다.
- 날짜 이동, 일정 펼침, 검색 전환, 오류 토스트처럼 필요한 짧은 커스텀 동작만 유지한다.
- `Reduce Motion`이 켜지면 위 커스텀 이동 애니메이션은 비활성화한다. 시스템 전환은 운영체제 설정을 따른다.

## 모달 높이 규칙

| 유형 | 시작 높이 | 대상 |
|---|---|---|
| 긴 입력·권한 검토 | large | 새 일정, 일정 상세·수정, Google Calendar, Slack, AI 데이터 접근, 개인정보 |
| 짧은 읽기·선택 | medium | 브리핑 상세, 검색 필터, 일정 이동 |
| 문맥형 도구 | medium + large | Agent, 날짜별 일정 목록 |
| 하루 전체 검토 | large | 오늘 요약 |
| 파괴적 확인 | confirmation dialog | 일정 삭제 |
| 한 줄 입력 | alert | 새 캘린더 이름 |

긴 `Form`과 권한 시트는 핵심 입력 또는 CTA가 잘리지 않도록 처음부터 large로 연다. 짧은 시트만 medium을 유지한다.

## 실기 검사표

| 화면·시트 | 진입 | 검사 결과 |
|---|---|---|
| 오늘 | 탭 | 18pt 외곽 축과 일정·브리핑의 공통 44pt 선행 열·본문 열 재확인 |
| 새 일정 | 오늘/캘린더의 + | large 시작, 날짜·시간·장소·알림·반복·노트까지 스크롤 문맥 확인. 값이 있어도 알림 라벨 유지 |
| 일정 상세·수정 | 일정 행 | large 시작, 닫기/수정 및 저장/취소 위치 유지 |
| 장소 | 일정 편집의 장소 | 부모 NavigationStack을 재사용하고 정상적인 뒤로가기 제공 |
| 오늘 요약 | 완료 링 | large, 완료·내일·더보기 열과 삭제 확인 흐름 확인 |
| 일정 이동 | 요약 행 더보기 | medium, 취소/이동과 DatePicker 확인 |
| Agent | 하단 Agent | medium + large, 빠른 요청의 선행 열·본문 열·구분선과 composer 안전 영역 재확인 |
| 캘린더 | 탭 | 월간 그리드와 선택일 열린 행이 18pt 외곽 축 사용, 필터를 오늘 행동 옆에 배치 |
| 날짜별 일정 | 날짜 길게 누르기 | iPhone 15 실기 확인. 단순 탭은 선택일만 변경하고, 길게 누르면 medium 시트가 열리며 상단 +로 스크롤 없이 새 일정 진입 가능 |
| 검색 | 캘린더 검색 | 아이콘형 Glass 진입·검색 필드·segmented 범위가 페이지 축 유지, compact 빈 상태와 결과 헤더 정렬 재확인 |
| 검색 필터 | 검색 결과 필터 | medium, 단일 완료 동작 유지 |
| 브리핑 키워드 | 설정 | medium/large, 직접 입력·최대 5개 선택·완료 |
| Google Calendar | 설정 | large, 권한 원칙과 연결 CTA 동시 확인 |
| Slack | 설정 | large, 실제 MVP 범위·권한·금지 동작 확인 |
| AI 데이터 접근 | 설정 | large, 보는 정보·보지 않는 정보·실행 원칙 확인 |
| 개인정보 | 설정 | large, 보관·철회·정책 고지 확인 |
| 브리핑 상세 | 브리핑 행 | medium, 닫기와 스크롤 읽기 흐름 확인 |
| 위젯 | 시스템 위젯 갤러리 | Today Small/Medium, Calendar Medium/Large 실기 확인. 잠금화면 3종은 빌드·Preview 등록 확인, 실제 잠금화면 배치는 미검증 |

## 세부 컴포넌트 감사

| 범주 | 확인 대상 | 결과 |
|---|---|---|
| 공통 뼈대 | `MemdoPage`, `MemdoSection`, `MemdoPageHeader`, `MemdoStatusRow` | 페이지 축, 섹션 간격, 44pt 선행 열과 본문 시작축 통일 |
| 공통 조작 | 아이콘 버튼, disclosure 행, 선택 행, 메뉴, toolbar | 커스텀 아이콘 조작은 최소 44×44pt, 나머지는 네이티브 Button/Menu/toolbar 크기 사용 |
| 일정 목록 | 완료 버튼, 시간축, 제목·메타, disclosure, 구분선 | 완료 원과 시간축이 같은 선행 열, 제목·구분선이 같은 본문 열 사용 |
| 오늘 | 완료 링, 날짜 선택, intention, 일정 접기·펼치기, 브리핑 | 날짜 조작 최소 52pt, 정확한 일정 수는 접근성 값으로 제공, 커스텀 애니메이션은 Reduce Motion 대응 |
| 캘린더·검색 | 월 이동, 날짜 셀, 일정 수 점, 필터, Glass 검색, segmented 범위 | 날짜 셀 최소 44pt, 검색 닫기·취소 경로와 compact 로딩/빈 상태 확인 |
| 일정 상세 | 닫기, 수정, 더보기, 완료 토글, 정보 행 | iPhone 15에서 실제 시트 확인. 정보 라벨·값 정렬과 작은 완료 조작 유지, 삭제는 confirmation dialog 사용 |
| 일정 편집 | 제목, 분류, DatePicker, 종일 Toggle, 마감, 장소, 알림, 반복, 노트·Agent | 네이티브 Form 제어 재사용, 상·하단 실제 스크롤 확인, Agent 변경은 저장 전 확인 문구 제공 |
| Agent·오늘 요약 | 빠른 요청, composer, 완료·이동·더보기 | 같은 44pt 선행 열과 8pt 본문 간격 사용, 접근성 글자 크기에서 인접 액션 간격 8pt 확보 |
| 설정·연결 | 계정, 시간, 키워드, 연결 행·badge, Google 진행/오류 | 행 최소 높이 유지. 연결 중 ProgressView와 텍스트를 함께 표시하고 오류는 색상뿐 아니라 경고 아이콘으로 구분 |
| 로그인 | Apple·Google·GitHub 공급자 버튼, 로딩·오류 | 공급자 버튼 52pt, 로딩 표시, 오류 아이콘·문구 제공. 익명 진입 제거 |
| 위젯 | 잠금화면 3종, 홈 Today/Calendar 4종 | SF Symbols·system font 사용. 월간 셀의 7pt 숫자를 점으로 바꾸고 정확한 수는 접근성 라벨에 유지 |

고정 크기 텍스트 검색 결과 11pt 미만은 제거했다. 남은 `.system(size:)` 두 곳은 `@ScaledMetric`으로 확대되는 브랜드 페이지 제목이며, 데이터·상태 텍스트는 Dynamic Type 스타일을 사용한다.

## 구현과 연동 준비 상태

- 오늘·캘린더·설정·Agent·일정 상세/편집·날짜별 일정·오늘/7일 요약과 홈 화면 위젯 4종은 iPhone 15 시뮬레이터에서 직접 진입하거나 시스템 갤러리로 확인했다.
- 장소·연결·개인정보·키워드·검색 필터 시트는 코드 진입점과 공통 시스템 컨테이너를 확인했으며 모든 내부 상태의 실기 검증은 남아 있다.
- 일정 추가·수정·완료·날짜 이동은 공통 `ScheduleStore`에 반영된다. 검색·캘린더·오늘은 같은 일정 모델을 읽는다.
- 장소 검색은 MapKit 로컬 검색을 사용한다.
- Google Calendar와 Slack은 권한·범위·연결 전 설명 UI까지 구현했다. 실제 연결 CTA는 OAuth 클라이언트와 서버 콜백이 준비될 때까지 의도적으로 비활성화한다.
- Agent 응답과 브리핑 데이터는 현재 연결 준비 상태다. 백엔드 연결 전 UI 구현 완료와 서비스 통합 완료를 혼동하지 않는다.

## 남은 검증 게이트

- 잠금화면 Inline/Circular/Rectangular 실제 배치와 시스템 틴트
- 로그인·홈/잠금화면 위젯의 Dark Mode 실기 확인
- VoiceOver 실제 읽기 순서
- 일정 4개 이상, 검색 다건, 쓰기 실패·네트워크 실패 상태
- 장소 검색 결과/없음, 반복 생성, 알림 선택, 빠른 추가 분석 중/결과
- Google Calendar·Slack·AI 데이터·개인정보·키워드 시트의 실제 스크롤과 닫기 흐름

## 2026-08-09 상태별 실기 검증

- Dark Mode에서 오늘·캘린더·검색·설정·Agent·Google Calendar 시트를 직접 열었다. 설정 Toggle의 전역 흑백 tint 때문에 켜진 트랙과 손잡이가 모두 흰색이던 결함을 확인했고, 공통 `memdoToggle`의 Brand tint로 수정했다.
- Dynamic Type은 AX5에서 오늘·캘린더·검색·설정·일정 상세/수정·오늘 요약·Agent를 직접 확인했다. 주간 레일 제스처 충돌, 월 헤더 충돌, 연결 배지 충돌, 편집 제목 잘림을 수정했다.
- 앱 검수 기준은 `Medium`, 앱 지원 상한은 약 200%에 해당하는 AX3로 고정했다. 월간 그리드처럼 공간 관계가 정보인 요소는 `.large` 상한과 VoiceOver 값을 함께 유지한다.
- Agent composer의 중복 `.bar` 재질을 제거하고 하나의 interactive Glass 입력 표면만 남겼다. 전송은 44pt 터치 영역 안의 `arrow.up.circle.fill`로 바꾸고 비활성/활성 색상과 접근성 이름을 확인했다.
- 로그인 화면은 세 공급자 버튼의 52pt 높이, 동일 곡률, Google 컬러 G 20pt와 16pt 선행 여백, 오류의 아이콘·문구 병행, 내용이 넘칠 때만 스크롤되는 구조를 코드로 확인했다. 실제 화면은 로그인된 세션을 보존하기 위해 미검증으로 남긴다.
- 실제 저장 일정 `test`가 날짜·월간 개수·검색 결과에 동일하게 나타나고 상세/수정으로 진입하는 것을 확인했다.

## 변경 시 회귀 기준

새 페이지는 `MemdoPage`, 새 섹션은 `MemdoSection`, 새 시트는 `memdoSheetPresentation`을 먼저 사용한다. 임의의 페이지 수평 패딩이나 중첩 `NavigationStack`을 추가하지 않는다. iPhone 15에서 기본·스크롤·키보드·Dynamic Type 상태를 확인한 뒤 병합한다.
