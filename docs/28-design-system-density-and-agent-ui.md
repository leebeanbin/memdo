# 디자인 시스템·밀도·Agent UI 계약

상태: 구현 기준선

기준일: 2026-08-02

상위 문서: [제품 요구사항](./01-product-requirements.md), [페이지별 UI/UX 계약](./27-page-ui-ux-contract.md)

구현 토큰: [iOS 디자인 기준선](../apps/ios/Memdo/DESIGN.md)

이 문서는 Memdo를 수정하는 사람과 Codex가 화면마다 다른 취향을 덧붙이지 않도록 사용자의 디자인 방향, 밀도 규칙, 컴포넌트 계약과 검수 기준을 한곳에 고정한다. 페이지의 기능과 상태는 `27`, 수치와 SwiftUI 구현은 `iOS DESIGN`, 밀도에 관한 판단은 이 문서를 따른다.

## 1. 사용자가 원하는 제품 인상

Memdo는 기능이 적은 앱이 아니라, 필요한 기능을 필요한 순간에만 보여주는 개인 캘린더다.

- Notion Calendar와 Google Calendar처럼 기본 화면은 차갑고 조용해야 한다.
- 사용자가 조금 배워야 하더라도 화면을 버튼 설명서처럼 만들지 않는다.
- 한눈에는 단순하지만 탭, 길게 누르기, 메뉴, 시트 안에는 전문 기능이 있어야 한다.
- AI 페이지를 따로 순회하게 하지 않고 현재 일정 문맥에서 Agent를 사용할 수 있어야 한다.
- AI는 전면의 캐릭터나 거대한 카드가 아니라 입력기, 짧은 제안, 실행 상태로 존재해야 한다.
- Black & White semantic color를 기본으로 하고 브랜드 보라는 2% 이내의 근거·선택 표시에만 사용한다.
- 카드, 큰 버튼, 설명문을 추가해서 빈 공간을 메우지 않는다.
- 일정이 많아도 모든 내용을 한 번에 펼치지 않는다.
- Light/Dark, Dynamic Type, VoiceOver에서도 같은 위계와 의미가 유지되어야 한다.

## 2. 참고한 공개 패턴과 적용 범위

코드와 외형을 복제하거나 새 UI 프레임워크를 추가하지 않는다. 공개 구현에서 검증된 정보 구조만 SwiftUI 네이티브 컴포넌트로 옮긴다.

| 참고 | 확인한 패턴 | Memdo 적용 | 적용하지 않는 것 |
|---|---|---|---|
| [Apple HIG: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai) | AI 표시, 사용자 통제, 개인정보 설명, 비 AI 대안 | `Agent` 라벨, 실행 전 승인, 권한 범위, 기본 일정 기능 유지 | AI가 사용자를 대신해 승인하는 흐름 |
| [assistant-ui](https://github.com/assistant-ui/assistant-ui) | Thread, Composer, Action Bar, inline approval을 분리한 조합형 구조 | 고정 composer, 결과와 승인 UI 분리, 접근성 우선 | React 패키지 또는 화면 복제 |
| [Vercel Chatbot](https://github.com/vercel/chatbot) | 입력 중심의 조용한 기본 상태, 필요할 때만 구조화 결과 표시 | 빈 상태의 소수 빠른 요청, 응답 후 제안 목록 숨김 | 전체 채팅 제품화, 대화 목록 탭 |
| [CopilotKit](https://github.com/CopilotKit/CopilotKit) | 앱 상태를 공유하는 Agent, human-in-the-loop, generative UI | 현재 탭 문맥, 일정 변경안 승인, 도구 상태 행 | 매 응답마다 임의 UI 생성 |

X의 시각 시안은 출처·접근성·상태 계약을 확인하기 어려워 직접 기준으로 삼지 않는다. GitHub 원본과 Apple HIG를 우선한다.

## 3. 화면 밀도 원칙

### 3.1 위계 예산

한 화면에서 동시에 강하게 보여주는 위계는 최대 네 단계다.

1. 페이지 제목 또는 현재 날짜
2. 사용자가 지금 판단할 핵심 내용
3. 다음 행동 하나
4. 메타데이터

같은 강도의 제목, 카드, 컬러 면이 다섯 개 이상 반복되면 위계를 다시 나눈다. 설명을 추가하기 전에 삭제, 병합, 메뉴 이동을 먼저 검토한다.

### 3.2 선택 예산

- 한 번의 판단에 바로 보이는 선택은 최대 5개다.
- 기본 화면의 주요 행동은 1개다.
- 한 행의 전면 행동은 최대 2개다. 나머지는 `Menu`로 이동한다.
- 파괴 행동은 기본 화면에 노출하지 않고 `Menu → confirmationDialog`를 사용한다.
- 같은 목적의 진입점은 한 화면에 두지 않는다.

### 3.3 정보 공개 순서

```text
제목·핵심 상태
→ 자주 쓰는 직접 행동
→ 반복 행 최대 3개
→ 더 보기 또는 Menu
→ 상세·편집 Sheet
→ 파괴·외부 전송 확인
```

## 4. 카드 배치 계약

카드는 장식이 아니라 독립된 내용 경계를 표현한다.

### 4.1 카드를 쓸 수 있는 경우

- 여러 행이 하나의 선택 날짜나 하나의 결과 집합에 속한다.
- 배경에서 분리해야 조작 영역이 명확해진다.
- 빈 날의 첫 질문처럼 화면의 유일한 강조 행동이다.
- 달력처럼 내부 좌표계가 하나의 독립 도구다.

### 4.2 카드를 쓰지 않는 경우

- 제목·설명·숫자만 있는 상태 요약
- 섹션 제목 바로 아래의 단일 문장
- 설정의 반복 행 전체
- Agent의 빠른 요청, 응답 문장, 실행 상태
- 이미 카드 안에 있는 하위 요소
- 화면 하단을 채우기 위한 중복 진입점

### 4.3 카드 예산

| 화면 | 첫 viewport | 전체 화면 | 허용 카드 |
|---|---:|---:|---|
| 오늘 | 일정 있음 0, 빈 날 1 | 일정 있음 0, 빈 날 1 | 빈 날 intention prompt만 허용 |
| 캘린더 | 0 | 0 | 월간 그리드와 일정 모두 열린 행 구조 |
| 검색 | 0 | 0 | 검색 입력만 조작층 Glass, 결과는 열린 행 구조 |
| 오늘 요약 | 0 | 0 | 분석 기준선과 결정 행 사용 |
| 설정 | 0 | 0 | 행과 Divider 사용 |
| Agent | 0 | 0 | 열린 레이아웃과 하단 composer 사용 |

추가 카드를 넣어야 한다면 기존 카드와 책임이 겹치는지 먼저 확인한다. 카드 안에 카드를 넣지 않는다.

### 4.4 크기

- 화면 좌우 여백: `18pt`
- 섹션 간격: `18pt`
- 섹션 제목과 내용: `10pt`
- 카드 반경: `16pt`
- 카드 내부 여백: 기본 `12–16pt`
- 일반 반복 행: 시각 높이 `44–56pt`
- 본문은 기본 두 줄 이내, 메타데이터는 기본 한 줄이다.
- 터치 영역은 시각 크기와 무관하게 최소 `44×44pt`다.

## 5. 컴포넌트 계약

### 페이지와 섹션

| 컴포넌트 | 책임 | 금지 |
|---|---|---|
| `MemdoPage` | 공통 배경, 스크롤, 탭바 하단 여유 | 페이지별 임의 좌우 여백 |
| `MemdoPageHeader` | eyebrow, 26pt 제목, 한 줄 설명, 선택적 아이콘 행동 | 카드 배경, 두 개 이상 행동 |
| `MemdoSection` | 제목, 개수·상태, 선택적 아이콘 행동 | 긴 도움말, 별도 카드 제목 반복 |
| `memdoRowGroup` | 반복 행의 상하 Divider 경계 | 카드 배경과 중첩 표면 |
| `memdoFloatingSurface` | 떠 있는 interactive Glass 조작층 | 일정·뉴스·설정 콘텐츠 |
| `memdoSystemList` | Form/List의 배경과 compact 섹션 밀도 | 커스텀 폼 재구현 |

### 버튼

| 역할 | 표현 | 사용 수 |
|---|---|---:|
| Primary | `.borderedProminent` | 화면 또는 시트당 최대 1 |
| Secondary | `.bordered` | primary 옆 최대 1 |
| Inline | `.plain` 텍스트 또는 아이콘 | 섹션 행동, 탐색 |
| Choice | `MemdoChoiceButton` | 2–5개 짧은 선택 |
| Overflow | `Menu` + `ellipsis` | 이동·삭제 등 저빈도 행동 |

버튼을 작게 보이게 하려고 44pt 터치 영역을 줄이지 않는다. 버튼 라벨은 한 줄이며, 접근성 글자 크기에서는 가로 행동을 세로로 재배치한다.

### 목록과 빈 상태

- 반복 항목은 카드 여러 개가 아니라 한 그룹 안의 행으로 만든다.
- 일정은 기본 3개까지만 보여주고 나머지는 `MemdoDisclosureRow`로 연다.
- 빈 상태는 `ContentUnavailableView` 또는 유일한 intention prompt를 사용한다.
- 빈 상태를 다시 카드로 감싸지 않는다.

### 시트와 모달

| 목적 | 시스템 표현 |
|---|---|
| 추가·상세·편집·Agent·요약·연결 설명 | `sheet` + `NavigationStack` |
| 설정·입력 | `Form` 또는 `List` |
| 삭제·되돌릴 수 없는 실행 | `confirmationDialog` |
| 짧은 오류·한 단계 결정 | `alert` |

- 같은 기능은 같은 toolbar 위치와 `취소/저장`, `닫기/수정` 문법을 쓴다.
- `.medium`은 읽기와 짧은 선택, `.large`는 Form과 긴 검토에 사용한다.
- 일정 날짜를 짧게 탭할 때는 시트를 열지 않는다. 선택만 바꾼다.
- 하단 시트는 시스템 전환과 drag indicator를 사용하고 뒤 콘텐츠가 비치지 않는 semantic background를 쓴다.
- 모든 `Form`과 `List`는 `memdoSystemList`를 사용해 compact 시스템 섹션 간격을 공유한다. 시스템 입력 카드 모양은 유지하되 별도 장식 Glass를 중첩하지 않는다.

## 6. Agent UI 계약

Agent는 별도 AI 페이지가 아니라 현재 앱 문맥 위에 열리는 command surface다.

### 6.1 기본 구조

```text
현재 문맥 라벨
→ 한 줄 질문과 실행 원칙
→ 빈 상태에서만 빠른 요청 3개
→ 응답 또는 구조화 변경안
→ 하단 고정 composer
```

- 빠른 요청은 카드가 아닌 44pt 행으로 표시한다.
- 사용자가 요청하면 빠른 요청 목록은 사라지고 결과에 공간을 양보한다.
- Agent 응답은 말풍선 피드가 아니라 짧은 본문과 3pt 브랜드 기준선으로 표시한다.
- composer는 키보드와 함께 고정되며 현재 콘텐츠를 과도하게 가리지 않는다.
- draft와 응답은 시트 재진입에도 유지하며, 초기화는 명시적인 `새 대화`로만 수행한다.
- 무의미한 회전, 빠른 morph, 자동 이동 애니메이션을 쓰지 않는다.

### 6.2 생성형 UI 허용 범위

Agent가 임의의 화면을 만드는 것이 아니라 정해진 데이터 유형에 맞는 UI만 선택한다.

| 결과 유형 | UI |
|---|---|
| 설명·요약 | 짧은 텍스트 |
| 조회 진행 | compact status row |
| 일정 생성·수정 | 변경 필드 diff + 승인/취소 |
| 충돌 | 충돌 일정 행 + 대안 시간 |
| 외부 전송 | 대상·내용 preview + 승인/취소 |
| 실패 | 오류 원인 + 재시도 |

### 6.3 사용자 통제

- 일정 생성·수정·삭제, Slack 전송, 외부 캘린더 쓰기는 항상 승인 대기 상태를 거친다.
- 승인 UI에는 대상, 바뀌는 필드, 외부 전송 여부를 표시한다.
- 읽기 권한이 없으면 Agent는 권한을 우회하지 않고 설정 경로를 안내한다.
- AI를 쓰지 않아도 일정 생성, 수정, 알림, 반복은 동작해야 한다.

## 7. 페이지별 검수 결과와 고정 위계

| 화면 | 고정 위계 | 카드 수 | 주요 행동 | 저빈도 기능 위치 |
|---|---|---:|---|---|
| 오늘 | 날짜 → 날짜 레일 → 일정/빈 날 → 브리핑 | 0 | 일정 `+` | 요약은 헤더 완료 링 |
| 캘린더 | 월 → 월간 그리드 → 선택 날짜 일정 | 0 | 일정 `+` | 필터 Menu, 날짜 long press |
| 검색 | 검색 입력 → scope → 필터 상태 → 결과 | 0 | 결과 선택 | 상세 필터 Sheet, 분석은 공통 Agent |
| 오늘 요약 | 기간 → 완료 수 → Agent 분석 → 결정 또는 완료·놓침 기록 | 0 | Agent와 정리·오늘의 완료 원 | 다른 날짜·삭제는 Menu |
| 설정 | 하루 → 연결·권한 → 키워드 → 개인정보 | 0 | 직접 설정 | 연결 설명 Sheet |
| Agent | 문맥 → 요청/결과 → composer | 0 | 보내기 | 변경안 승인 UI |

### 이번 감사에서 제거한 중복

- 오늘 하단의 두 번째 요약 카드: 헤더 완료 링과 책임 중복
- 검색 결과의 별도 AI 요약 카드와 시트: 공통 Agent와 책임 중복
- 설정 섹션의 반복 카드 배경: 섹션 제목과 Divider로 경계가 충분함
- 캘린더 월간·선택일 카드와 검색 결과 카드: 공간 구조와 Divider만으로 경계가 충분함
- 설정의 비상호작용 Glass 패널: Glass는 조작층에만 남기고 키워드 입력을 interactive Glass로 변경
- Agent 빠른 요청과 응답의 카드 배경: command surface의 우선순위를 흐림
- 브리핑 상세의 선정 이유 카드: 단일 설명이므로 열린 인라인 근거로 변경

## 8. 시트·모달 전수 규칙표

| 시트 | 기본 컨테이너 | Detent | 주요 toolbar/action | 상태 계약 |
|---|---|---|---|---|
| Agent | `ScrollView` + composer | medium/large | 새 대화, 닫기, 보내기 | empty/result/approval/error |
| 새 일정 | `Form` | medium/large | 취소/추가 | invalid input은 추가 비활성 |
| 일정 상세 | `Form` | medium/large | 닫기/수정 | 수정 시 취소/저장 |
| 날짜 일정 | `List` | medium/large | 닫기 | empty/list/add |
| 오늘 요약 | `MemdoPage` | large | 기간 전환, Agent, 오늘의 완료 원·내일 | empty/today/history/complete |
| 다른 날짜 이동 | `Form` | medium | 취소/이동 | DatePicker |
| 브리핑 상세 | `ScrollView` | medium | 닫기 | source/reason/impact |
| 검색 필터 | `Form` | medium | 적용 | reset/active |
| Google·Slack 연결 | `List` | medium | 닫기 | 설명/권한/미연결 |
| AI 동의·개인정보 | `List` | medium/large | 닫기 | 읽음/안 읽음/철회 원칙 |
| 장소 선택 | `List` + `.searchable` | navigation | 시스템 back | idle/loading/result/empty |

## 9. Codex 구현 규칙

화면을 변경할 때 다음 순서로 판단한다.

1. 이 요소가 없어도 사용자가 목적을 달성하는가? 가능하면 삭제한다.
2. 기존 `MemdoPage`, `MemdoSection`, `ScheduleRow`, 네이티브 Form/List로 해결되는가?
3. 같은 책임의 버튼, 카드, 시트가 이미 있는가?
4. 기본 화면이 아니라 Menu나 Sheet에 둘 기능인가?
5. iPhone 15에서 첫 viewport의 카드 예산을 넘는가?
6. 44pt, Dynamic Type, VoiceOver 이름과 Reduce Motion을 지키는가?

새 공통 컴포넌트는 두 화면 이상에서 같은 책임과 상태를 반복할 때만 만든다. 이름은 외형이 아니라 책임을 나타낸다. 예를 들어 `PurpleCard`가 아니라 `ScheduleRow`, `AgentComposer`를 사용한다.

## 10. 완료 기준

- [ ] 첫 viewport의 카드 예산을 지킨다.
- [ ] 한 화면의 primary action이 하나다.
- [ ] 한 행의 전면 행동이 두 개 이하다.
- [ ] 반복 콘텐츠가 card-per-item이 아니다.
- [ ] 중복 진입점이 없다.
- [ ] 시트는 표의 컨테이너와 toolbar 문법을 따른다.
- [ ] Agent의 실행과 외부 전송은 승인 전 상태를 변경하지 않는다.
- [ ] Light/Dark, iPhone 15, Larger Text, VoiceOver에서 의미가 유지된다.
- [ ] 코드 변경과 함께 `27`, `DESIGN`, 이 문서의 계약 충돌을 확인한다.
- [ ] 빌드와 핵심 상호작용을 Simulator에서 검증한다.

## 11. 미구현이지만 계약이 확정된 Agent 상태

현재 SwiftUI 프로토타입은 빠른 요청, 응답, composer까지 구현한다. 실제 API 연결 단계에서 아래 UI를 같은 구조 안에 추가한다.

- tool 진행 상태 행
- 일정 diff와 승인/취소
- Slack 대상·메시지 preview와 승인/취소
- 충돌 대안 시간
- 재시도 가능한 오류

이 상태를 위해 별도 Agent 페이지, 대화 탭, 새로운 카드 프레임워크를 추가하지 않는다.
