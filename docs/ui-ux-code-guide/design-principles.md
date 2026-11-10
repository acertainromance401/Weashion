# 디자인 원칙과 레퍼런스

[전체 목차](./README.md) · [다음: 색상, 배경면과 대비](./colors-and-surfaces.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

색이나 효과를 고르기 전에 화면의 목적을 판단하는 문서입니다. 레퍼런스에서 받아들인 것은 구도와 리듬이며, 브랜드 로고·사진·문구의 복제를 허용하는 근거가 아닙니다. 과거 설계 기록과 현재 구현이 다르면 현재 연결된 코드와 승인된 범위를 우선합니다.

## 요소 분류와 책임

| 구분 | 받아들이는 시각 원리 | 적용할 때 지킬 경계 |
| --- | --- | --- |
| 패션 에디토리얼 | 큰 제목, 작은 캡션, 넓은 여백과 가는 선 | 모든 화면을 큰 표지처럼 만들지 않음 |
| 아방가르드 편집 | 비대칭, 크롭, 제한적인 겹침 | 입력칸과 버튼의 판독성·조작성을 해치지 않음 |
| 절제된 고급감 | 제한된 색과 반복되는 정렬 | 정보를 작고 흐리게 숨기는 방식으로 구현하지 않음 |
| 표지 | 환경과 개인 실루엣을 한 장면으로 읽기 | 감상과 빠른 착장 조작을 함께 유지 |
| 피팅룸 | 같은 몸에서 다른 사이즈 비교 | 장식 변화와 실제 피팅 결과를 구분 |
| 편집 지면 | 번호·단위·도식·입력의 대응 | 정확한 값과 오류 복구를 우선 |

## 문서 내 상세 항목

- [25. 어떤 레퍼런스를 어떤 시각 요소로 해석했는가](#snippet-25)
- [26. 색, 서체, 선과 간격의 시각적 역할](#snippet-26)

<a id="snippet-25"></a>

## 25. 어떤 레퍼런스를 어떤 시각 요소로 해석했는가

근거: [디자인 방향과 레퍼런스 대응표](../editorial-design-direction.md#L118), [현재 승인된 디자인 기준](../editorial-design-direction.md#L37).

아래는 저장소의 설계 문서에 기록된 레퍼런스입니다. 외부 서비스의 현재 화면을 새로 조사하거나, 특정 브랜드의 자산을 앱에서 사용한다는 뜻은 아닙니다.

| 레퍼런스·방향 | 받아들인 시각 원리 | 현재 코드에서 읽을 수 있는 연결 | 복제하거나 보장하지 않는 것 |
| --- | --- | --- | --- |
| High Fashion Editorial | 큰 세리프·명조, 여백, 얇은 선과 캡션 | [EditorialTitle, EditorialHeading, EditorialFigureCaption](../../weashion/weashion/Views/EditorialStyle.swift#L364) | 모든 화면을 큰 표지처럼 구성하지 않음 |
| Avant-Garde Editorial | 비대칭, 크롭, 제한적인 겹침, 엇갈린 열 | [표지](../../weashion/weashion/ContentView.swift#L464), [하늘판과 선언문](../../weashion/weashion/ContentView.swift#L660) | 입력 필드와 버튼까지 회전·겹침으로 읽기 어렵게 만들지 않음 |
| Minimal Luxury | 제한된 색, 선·면 중심의 위계, 절제된 반복 조작 | [공통 스타일](../../weashion/weashion/Views/EditorialStyle.swift), [치수 편집](../../weashion/weashion/Views/GarmentEditorView.swift) | 정보를 작고 흐리게 숨기는 것을 의미하지 않음 |
| Ralph Lauren 진입 화면 | 배경을 채우는 분위기, 하단 카피·CTA, 간결한 진행 표시 | [EditorialWelcomeView](../../weashion/weashion/Views/EditorialWelcomeView.swift) | 해당 브랜드의 로고·사진·문구는 사용 근거가 아님 |
| Opal 메인 구성 | 중앙 피사체와 주변 정보, 주요 행동과 하단 내비게이션의 관계 | [ContentView](../../weashion/weashion/ContentView.swift) | 둥근 카드·알약 버튼 외형을 그대로 복제하지 않음 |
| 날씨 뒤의 개인 마네킹 | 환경과 개인 실루엣을 한 장면처럼 읽기 | [WeatherBackdrop 위의 마네킹](../../weashion/weashion/ContentView.swift#L464) | 날씨 추천이 실제 착장에 모두 적용됐다는 의미가 아님 |
| 3열 스타일링 지면 | 큰 문자·번호, 비교 리듬과 반복 정렬 | [사이즈 노트](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L166) | 현재 구현을 고정 3열이나 세 가지 코디로 간주하지 않음. 현재 사이즈 노트는 행 중심 구성 |
| 비대칭·컷아웃 지면 | 도식 주변 여백, 문자와 그림의 크기 대비 | [상품 아트워크](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L310) | 컷아웃을 실제 상품 사진이나 정확한 비율로 간주하지 않음 |
| 사각 모델 프레임 지면 | 피사체 경계, 얇은 프레임, 캡션 연결 | [편집 미리보기 프레임](../../weashion/weashion/Views/GarmentEditorView.swift#L168) | 모든 3D 뷰에 두꺼운 테두리를 강제하지 않음 |
| 엇갈린 코트·치수 주석 지면 | 실루엣, 번호, 주석의 대응 | [GarmentMeasurementPlate](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L26) | 도식이 해당 상품의 실제 형상이라는 뜻이 아님 |

**현재 편집 원칙:** 표지는 감상과 빠른 조작, 피팅룸은 같은 몸의 비교, 편집 화면은 정확한 입력을 우선합니다. 레퍼런스는 구도와 리듬의 근거이며 브랜드 자산이나 문구의 복제 근거가 아닙니다.

<a id="snippet-26"></a>

## 26. 색, 서체, 선과 간격의 시각적 역할

근거: [실제 색상 토큰](../../weashion/weashion/Views/EditorialStyle.swift#L3), [서체 구현](../../weashion/weashion/Views/EditorialFonts.swift), [설계상의 색·조판·간격 규칙](../editorial-design-direction.md#L542).

색·서체·간격의 상세 표는 요소별 수정 지점이 분명하도록 다음 문서로 나눴습니다. 원문의 26번 항목을 세 하위 분류로 옮긴 것이며 값을 새로 정의한 것은 아닙니다.

| 하위 분류 | 상세 문서 | 다루는 내용 |
| --- | --- | --- |
| 26.1 색상·표면 | [팔레트 전체와 면의 합성](./colors-and-surfaces.md#visual-rules-colors) | 토큰별 색과 역할, 역상, 호출부별 불투명도 |
| 26.2 서체·조판 | [서체·조판 전체와 번들 폰트](./typography.md#visual-rules-type) | 서체 역할, 숫자·단위·자간, 파일과 라이선스 |
| 26.3 선·면·간격 | [실제 코드의 선·면·간격](./layout.md#visual-rules-layout) | 여백, 최대 폭, 선, 모서리, 블러와 안전 영역 |

## 변경·검증 체크리스트

- 변경 대상이 표지·비교·입력 중 어느 목적을 가지는지 먼저 정합니다.
- 레퍼런스를 외형 전체의 복제가 아니라 크기 대비·여백·정렬 같은 원리로 설명할 수 있는지 확인합니다.
- 장식의 겹침과 회전이 실제 정보나 터치 영역을 가리지 않는지 확인합니다.
- 과거 설계 수치가 아니라 [26](#snippet-26)에서 연결한 현재 토큰과 호출부를 확인합니다.
- 계획된 기능, 보유 자산, 실제 표시 중인 구현을 [48](./validation-and-inventory.md#snippet-48)의 기준으로 구분합니다.

## 함께 보는 문서

- [색상, 배경면과 대비](./colors-and-surfaces.md): 종이색·잉크색·버건디 토큰과 상태색, 역상, 호출부별 불투명도를 구분합니다.
- [타이포그래피, 캡션과 현지화](./typography.md): 서체의 역할, 한글 폴백, 크기 대응, 제목·캡션·세로 조판과 다국어 문구를 다룹니다.
- [화면별 구도, 내비게이션과 선택면](./screen-composition.md): 표지·날씨 지면·피팅룸·체형·편집·소개 화면의 배치와 헤더·내비게이션·선택면을 연결합니다.
- [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md): 경계값 테스트, 전체 시각 타입·효과·형상 생성 경로와 미구현·미확인 요소를 한곳에서 찾습니다.
