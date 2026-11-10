# WEASHION UI/UX 코드 스니펫 가이드

앱에 사용된 디자인 시스템, 모션 애니메이션, 반응형 레이아웃과 입력 UX를 기능별 코드 뭉치로 정리한 문서입니다. 움직이는 효과뿐 아니라 **정적인 타이포그래피, 편집 구도, 선·면·도식, 3D 외관, 이미지 자산과 디자인 레퍼런스**도 함께 다룹니다.

- 기준: 2026-11-02 현재 작업 트리. 미커밋 코드를 포함하며 특정 커밋의 스냅샷은 아닙니다.
- 각 Swift 코드 블록은 실제 소스의 연속된 구간을 발췌했습니다. 들여쓰기만 정리했으며 설명용 가상 구현은 섞지 않았습니다.
- 일부는 타입이나 함수 본문의 일부분입니다. 주변 상태, import, 모델이 필요하므로 코드 블록 하나만 복사해서 독립 실행하는 예제는 아닙니다.
- 원본 링크의 줄 번호는 이후 수정으로 달라질 수 있습니다. 함께 적힌 타입과 함수 이름을 기준으로 찾으면 됩니다.
- 전체 디자인 의도와 변경 이력은 [디자인 방향 문서](../editorial-design-direction.md)를 참고합니다. 과거 버전과 현재 구현을 혼동하지 않도록 0.16 설명을 우선합니다.
- **정리 범위:** 앱 화면에 영향을 주는 시각 표현의 종류와 구현 표면 전체를 대상으로 합니다. 모든 문구와 좌표를 그대로 전사하는 대신, 같은 역할의 반복 표현은 공통 스니펫과 화면별 인벤토리로 묶습니다.
- **상태 구분:** 실제 구현, 조건부 표시, 런타임 직접 참조가 확인되지 않은 보유 자산, 설계 레퍼런스, 제외·미구현 요소를 구분합니다. 파일이 있다는 이유만으로 현재 화면에 표시된다고 간주하지 않습니다.

## 문서 구성

이 README는 전체 목차와 찾아보기입니다. 시각 요소를 **14개 종류별 상세 문서**로 나누고, 기존 01~48번 항목의 코드·설명·주의사항을 해당 문서로 옮겼습니다. 색·서체·간격이 섞여 있던 26번의 상세 표는 26.1~26.3으로 나눴습니다.

각 상세 문서에는 **요소 분류와 책임, 원문 코드와 구현 설명, 변경·검증 체크리스트, 관련 문서**가 있습니다. 공통 모양은 요소별 문서를, 실제 배치와 레이어 순서는 화면 구도 문서를, 구현 여부와 제외 범위는 인벤토리 문서를 기준으로 읽습니다.

- [전체 구조와 읽는 순서](#overview)
- [종류별 상세 문서](#categories)
- [변경 목적별 빠른 찾기](#quick-find)
- [원문 01~48 항목 전체 찾아보기](#snippet-index)
- [재분류 범위와 검증 원칙](#migration-scope)

<a id="overview"></a>

## 전체 구조와 읽는 순서

| 계층 | 중심 파일 | 담당하는 것 |
| --- | --- | --- |
| 디자인 규칙 | [EditorialStyle.swift](../../weashion/weashion/Views/EditorialStyle.swift) | 색상, 공통 컴포넌트, 모션 상수, 레이아웃 기준 |
| 폰트 | [EditorialFonts.swift](../../weashion/weashion/Views/EditorialFonts.swift) | 번들 서체, 한글 폰트 캐스케이드, 시스템 글씨 크기 대응 |
| 화면 조립 | [ContentView.swift](../../weashion/weashion/ContentView.swift) | 오늘, 피팅룸, 내 체형, 내비게이션, 표지와 화면 준비 |
| 목적별 화면 | [Views 폴더](../../weashion/weashion/Views) | 최초 설정, 보관함, 치수 편집, 소개와 설정 |
| 3D 조작 연결 | [WEASHIONSceneView.swift](../../weashion/weashion/Views/WEASHIONSceneView.swift) | 렌더 표면과 마네킹 회전, 확대 제스처 |

처음 읽는다면 [01 색상](./colors-and-surfaces.md#snippet-01) -> [04 모션 상수](./motion.md#snippet-04) -> [06 등장 효과](./motion.md#snippet-06) -> [11 레이아웃 기준](./layout.md#snippet-11) -> [18 화면 준비](./feedback-and-loading.md#snippet-18) 순서를 권장합니다.

용어를 간단히 구분하면 다음과 같습니다.

- **디자인 토큰:** 색상, 시간, 간격처럼 여러 화면에서 공유하는 기준값.
- **ViewModifier:** 기존 뷰에 스타일이나 동작을 덧붙이는 SwiftUI 구성 방식.
- **리빌(reveal):** 콘텐츠가 가려진 영역이나 화면 밖에서 나타나는 효과.
- **스태거(stagger):** 여러 요소의 등장 시작 시간을 조금씩 다르게 두는 방식.
- **패럴랙스(parallax):** 스크롤할 때 배경을 콘텐츠와 다른 속도로 움직이는 효과.
- **Dynamic Type:** 사용자가 설정한 시스템 글씨 크기에 맞춰 텍스트를 조절하는 기능.
- **Reduce Motion:** 시스템의 '동작 줄이기' 접근성 설정.

<a id="categories"></a>

## 종류별 상세 문서

<a id="visual-direction"></a>

### 01. [디자인 원칙과 레퍼런스](./design-principles.md)

에디토리얼 레퍼런스를 화면의 구도·위계·조작 원칙으로 해석한 기준입니다.

**옮긴 원문 항목:** [25](./design-principles.md#snippet-25), [26](./design-principles.md#snippet-26).

<a id="design-system"></a>

### 02. [색상, 배경면과 대비](./colors-and-surfaces.md)

종이색·잉크색·버건디 토큰과 상태색, 역상, 호출부별 불투명도를 구분합니다.

**옮긴 원문 항목:** [01](./colors-and-surfaces.md#snippet-01).

**추가 분류:** [26.1. 팔레트 전체와 면의 합성](./colors-and-surfaces.md#visual-rules-colors).

### 03. [타이포그래피, 캡션과 현지화](./typography.md)

서체의 역할, 한글 폴백, 크기 대응, 제목·캡션·세로 조판과 다국어 문구를 다룹니다.

**옮긴 원문 항목:** [02](./typography.md#snippet-02), [28](./typography.md#snippet-28), [23](./typography.md#snippet-23).

**추가 분류:** [26.2. 서체·조판 전체와 번들 폰트](./typography.md#visual-rules-type).

<a id="editorial-details"></a>

### 04. [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md)

이중선, 스튜디오 워터마크·빛 면·타원, 상품 컷아웃과 아카이브 그래픽을 다룹니다.

**옮긴 원문 항목:** [27](./editorial-graphics.md#snippet-27), [29](./editorial-graphics.md#snippet-29), [34](./editorial-graphics.md#snippet-34).

<a id="motion"></a>

### 05. [모션, 등장과 화면 전환](./motion.md)

모션 토큰, 스크롤 리빌, 제목 등장, 글자 교체, 스윕·패럴랙스와 소개·실행 전환을 모았습니다.

**옮긴 원문 항목:** [04](./motion.md#snippet-04), [06](./motion.md#snippet-06), [07](./motion.md#snippet-07), [08](./motion.md#snippet-08), [09](./motion.md#snippet-09), [10](./motion.md#snippet-10), [21](./motion.md#snippet-21), [22](./motion.md#snippet-22).

<a id="responsive"></a>

### 06. [반응형 배치, 간격과 표시 컨테이너](./layout.md)

폭·글씨 크기·콘텐츠 요구 크기에 따른 열 배치, 그리드, 여백과 sheet/inspector를 구분합니다.

**옮긴 원문 항목:** [11](./layout.md#snippet-11), [12](./layout.md#snippet-12), [13](./layout.md#snippet-13), [14](./layout.md#snippet-14), [15](./layout.md#snippet-15).

**추가 분류:** [26.3. 실제 코드의 선·면·간격](./layout.md#visual-rules-layout).

<a id="interaction"></a>

### 07. [버튼, 선택과 입력 컨트롤](./controls-and-input.md)

CTA·선택 버튼·눌림·입력 포커스·오류 이동과 시스템 컨트롤의 외형·동작을 다룹니다.

**옮긴 원문 항목:** [03](./controls-and-input.md#snippet-03), [05](./controls-and-input.md#snippet-05), [16](./controls-and-input.md#snippet-16), [39](./controls-and-input.md#snippet-39).

<a id="visible-states"></a>

### 08. [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md)

실제 저장 결과, 오류 alert, 늦은 화면 준비 예고와 계산 중 진행선·블러·오버레이를 구분합니다.

**옮긴 원문 항목:** [17](./feedback-and-loading.md#snippet-17), [18](./feedback-and-loading.md#snippet-18), [38](./feedback-and-loading.md#snippet-38).

<a id="screens"></a>

<a id="visible-screens"></a>

### 09. [화면별 구도, 내비게이션과 선택면](./screen-composition.md)

표지·날씨 지면·피팅룸·체형·편집·소개 화면의 배치와 헤더·내비게이션·선택면을 연결합니다.

**옮긴 원문 항목:** [30](./screen-composition.md#snippet-30), [31](./screen-composition.md#snippet-31), [33](./screen-composition.md#snippet-33), [37](./screen-composition.md#snippet-37).

### 10. [날씨 배경과 대기 그래픽](./weather-graphics.md)

맑음·흐림·비·눈·어두운 배경의 팔레트와 해·구름·비·눈·하단 베일의 정적 레이어를 다룹니다.

**옮긴 원문 항목:** [20](./weather-graphics.md#snippet-20), [32](./weather-graphics.md#snippet-32).

### 11. [의류와 신체의 측정 도식](./measurement-diagrams.md)

의류 치수의 번호·강조선·값과 신체 앞/옆 실루엣·실선·점선·측정 강조를 구분합니다.

**옮긴 원문 항목:** [35](./measurement-diagrams.md#snippet-35), [36](./measurement-diagrams.md#snippet-36).

<a id="rendering"></a>

### 12. [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md)

SceneKit 출력과 RealityKit 형상·재질 연결, 카메라·조명·몸·의류 외관과 회전·확대를 다룹니다.

**옮긴 원문 항목:** [19](./rendering-and-gestures.md#snippet-19), [40](./rendering-and-gestures.md#snippet-40), [41](./rendering-and-gestures.md#snippet-41), [42](./rendering-and-gestures.md#snippet-42), [43](./rendering-and-gestures.md#snippet-43).

<a id="visual-assets"></a>

### 13. [이미지 자산, 폰트 파일과 아이콘](./assets-and-icons.md)

실제 연결된 브랜드·스플래시·앱 아이콘, 보유 벡터, SF Symbols와 디자인 리소스 위치를 정리합니다.

**옮긴 원문 항목:** [44](./assets-and-icons.md#snippet-44), [45](./assets-and-icons.md#snippet-45).

<a id="references"></a>

<a id="visual-inventory"></a>

### 14. [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md)

경계값 테스트, 전체 시각 타입·효과·형상 생성 경로와 미구현·미확인 요소를 한곳에서 찾습니다.

**옮긴 원문 항목:** [24](./validation-and-inventory.md#snippet-24), [46](./validation-and-inventory.md#snippet-46), [47](./validation-and-inventory.md#snippet-47), [48](./validation-and-inventory.md#snippet-48).

<a id="quick-find"></a>

## 변경 목적별 빠른 찾기

| 바꾸려는 것 | 먼저 볼 스니펫 |
| --- | --- |
| 전체 색감과 글꼴 | [01](./colors-and-surfaces.md#snippet-01), [02](./typography.md#snippet-02) |
| 버튼 모양과 눌림 | [03](./controls-and-input.md#snippet-03), [05](./controls-and-input.md#snippet-05) |
| 등장 속도와 제목 연출 | [04](./motion.md#snippet-04), [06](./motion.md#snippet-06), [07](./motion.md#snippet-07) |
| 사이즈 글자와 탭 장식 | [08](./motion.md#snippet-08), [09](./motion.md#snippet-09) |
| 스크롤 배경 움직임 | [10](./motion.md#snippet-10) |
| 한 열/두 열과 화면 여백 | [11](./layout.md#snippet-11), [12](./layout.md#snippet-12) |
| 편집 패널, 목록, 도식 배치 | [13](./layout.md#snippet-13), [14](./layout.md#snippet-14), [15](./layout.md#snippet-15) |
| 입력 오류, 저장 안내 | [16](./controls-and-input.md#snippet-16), [17](./feedback-and-loading.md#snippet-17) |
| 화면 준비 중 안내 | [18](./feedback-and-loading.md#snippet-18) |
| 마네킹 회전과 확대 | [19](./rendering-and-gestures.md#snippet-19) |
| 날씨, 소개, 실행 화면 | [20](./weather-graphics.md#snippet-20), [21](./motion.md#snippet-21), [22](./motion.md#snippet-22) |
| 언어와 회귀 검증 | [23](./typography.md#snippet-23), [24](./validation-and-inventory.md#snippet-24) |
| 디자인 레퍼런스, 색·서체·간격의 역할 | [25](./design-principles.md#snippet-25), [26](./design-principles.md#snippet-26) |
| 선, 캡션, 세로 제목, 스튜디오 장식 | [27](./editorial-graphics.md#snippet-27), [28](./typography.md#snippet-28), [29](./editorial-graphics.md#snippet-29) |
| 표지, 내비게이션, 날씨 지면 | [30](./screen-composition.md#snippet-30), [31](./screen-composition.md#snippet-31), [32](./weather-graphics.md#snippet-32), [33](./screen-composition.md#snippet-33) |
| 상품 아트워크, 의류·신체 측정 도식 | [34](./editorial-graphics.md#snippet-34), [35](./measurement-diagrams.md#snippet-35), [36](./measurement-diagrams.md#snippet-36) |
| 체형·설정·편집 화면의 전체 구도 | [37](./screen-composition.md#snippet-37) |
| 로딩, 선택, 네이티브 컨트롤 | [38](./feedback-and-loading.md#snippet-38), [39](./controls-and-input.md#snippet-39) |
| 3D 외관과 실제 형상 변화 | [40](./rendering-and-gestures.md#snippet-40), [41](./rendering-and-gestures.md#snippet-41), [42](./rendering-and-gestures.md#snippet-42), [43](./rendering-and-gestures.md#snippet-43) |
| 로고, 스플래시, 앱 아이콘, SF Symbols | [44](./assets-and-icons.md#snippet-44), [45](./assets-and-icons.md#snippet-45) |
| 전체 구현 표면, 효과 목록, 미구현 구분 | [46](./validation-and-inventory.md#snippet-46), [47](./validation-and-inventory.md#snippet-47), [48](./validation-and-inventory.md#snippet-48) |

<a id="snippet-index"></a>

## 원문 01~48 항목 전체 찾아보기

항목 번호는 원문과 대응시키기 위한 식별자이며 파일의 읽는 순서는 아닙니다. 숫자 링크를 누르면 이동한 문서의 해당 항목으로 바로 이동합니다.

| 번호 | 원문 주제 | 종류별 상세 문서 |
| --- | --- | --- |
| [01](./colors-and-surfaces.md#snippet-01) | 종이색, 잉크색, 버건디를 공유하는 색상 토큰 | [색상, 배경면과 대비](./colors-and-surfaces.md) |
| [02](./typography.md#snippet-02) | 영문과 한글 폰트 연결 및 시스템 글씨 크기 | [타이포그래피, 캡션과 현지화](./typography.md) |
| [03](./controls-and-input.md#snippet-03) | 주요 행동 버튼의 공통 형태 | [버튼, 선택과 입력 컨트롤](./controls-and-input.md) |
| [04](./motion.md#snippet-04) | 모션의 속도, 이동량, 감속 곡선 | [모션, 등장과 화면 전환](./motion.md) |
| [05](./controls-and-input.md#snippet-05) | 버튼 눌림 피드백 | [버튼, 선택과 입력 컨트롤](./controls-and-input.md) |
| [06](./motion.md#snippet-06) | 스크롤 등장과 마스크 진입 | [모션, 등장과 화면 전환](./motion.md) |
| [07](./motion.md#snippet-07) | 큰 제목을 줄마다 드러내기 | [모션, 등장과 화면 전환](./motion.md) |
| [08](./motion.md#snippet-08) | 사이즈 글자의 상하 교체 컴포넌트: 현재 직접 사용 미확인 | [모션, 등장과 화면 전환](./motion.md) |
| [09](./motion.md#snippet-09) | 탭을 바꿀 때 헤더를 통과하는 띠 | [모션, 등장과 화면 전환](./motion.md) |
| [10](./motion.md#snippet-10) | 표지의 스크롤 패럴랙스 | [모션, 등장과 화면 전환](./motion.md) |
| [11](./layout.md#snippet-11) | 한 열과 두 열을 결정하는 공통 기준 | [반응형 배치, 간격과 표시 컨테이너](./layout.md) |
| [12](./layout.md#snippet-12) | 같은 콘텐츠를 가로 또는 세로로 배치 | [반응형 배치, 간격과 표시 컨테이너](./layout.md) |
| [13](./layout.md#snippet-13) | 치수 편집을 sheet 또는 inspector로 표시 | [반응형 배치, 간격과 표시 컨테이너](./layout.md) |
| [14](./layout.md#snippet-14) | 상품 보관함의 가변 그리드 | [반응형 배치, 간격과 표시 컨테이너](./layout.md) |
| [15](./layout.md#snippet-15) | 치수 도식과 설명이 실제로 들어가는 배치 선택 | [반응형 배치, 간격과 표시 컨테이너](./layout.md) |
| [16](./controls-and-input.md#snippet-16) | 입력칸의 터치 범위와 잘못된 항목으로 이동 | [버튼, 선택과 입력 컨트롤](./controls-and-input.md) |
| [17](./feedback-and-loading.md#snippet-17) | 실제 저장 성공과 오류를 구분하는 피드백 | [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md) |
| [18](./feedback-and-loading.md#snippet-18) | 화면 준비가 늦을 때만 다음 지면 예고 | [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md) |
| [19](./rendering-and-gestures.md#snippet-19) | 마네킹 회전과 페이지 스크롤의 제스처 구분 | [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md) |
| [20](./weather-graphics.md#snippet-20) | 날씨별 시각 디자인 | [날씨 배경과 대기 그래픽](./weather-graphics.md) |
| [21](./motion.md#snippet-21) | 브랜드 소개 페이지의 전환 | [모션, 등장과 화면 전환](./motion.md) |
| [22](./motion.md#snippet-22) | 실행 스플래시와 본문 전환 | [모션, 등장과 화면 전환](./motion.md) |
| [23](./typography.md#snippet-23) | 화면 밖 코드에서도 같은 언어로 문구 생성 | [타이포그래피, 캡션과 현지화](./typography.md) |
| [24](./validation-and-inventory.md#snippet-24) | 접근성 및 반응형 경계값을 검증하는 테스트 | [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md) |
| [25](./design-principles.md#snippet-25) | 어떤 레퍼런스를 어떤 시각 요소로 해석했는가 | [디자인 원칙과 레퍼런스](./design-principles.md) |
| [26](./design-principles.md#snippet-26) | 색, 서체, 선과 간격의 시각적 역할 | [디자인 원칙과 레퍼런스](./design-principles.md) |
| [27](./editorial-graphics.md#snippet-27) | 이중 구분선의 형태와 그려지는 효과 | [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md) |
| [28](./typography.md#snippet-28) | 제목, 번호, 캡션과 세로 러닝헤드 | [타이포그래피, 캡션과 현지화](./typography.md) |
| [29](./editorial-graphics.md#snippet-29) | 스튜디오의 W, 빛 면, 바닥 그림자와 모서리 표시 | [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md) |
| [30](./screen-composition.md#snippet-30) | 표지의 겹침과 가장자리 편집 | [화면별 구도, 내비게이션과 선택면](./screen-composition.md) |
| [31](./screen-composition.md#snippet-31) | 헤더, 하단 바, 사이즈와 착장 슬롯의 선택면 | [화면별 구도, 내비게이션과 선택면](./screen-composition.md) |
| [32](./weather-graphics.md#snippet-32) | 날씨 배경을 구성하는 모든 그래픽 레이어 | [날씨 배경과 대기 그래픽](./weather-graphics.md) |
| [33](./screen-composition.md#snippet-33) | 날씨 지면의 큰 숫자, 사진 같은 크롭과 겹친 제목 | [화면별 구도, 내비게이션과 선택면](./screen-composition.md) |
| [34](./editorial-graphics.md#snippet-34) | 상품 아카이브와 설명용 의류 컷아웃 | [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md) |
| [35](./measurement-diagrams.md#snippet-35) | 의류 치수 도식의 번호, 강조선과 숫자 | [의류와 신체의 측정 도식](./measurement-diagrams.md) |
| [36](./measurement-diagrams.md#snippet-36) | 신체 측정 안내의 실루엣, 실선과 점선 | [의류와 신체의 측정 도식](./measurement-diagrams.md) |
| [37](./screen-composition.md#snippet-37) | 체형, 최초 설정, 편집과 설정 화면의 시각 구조 | [화면별 구도, 내비게이션과 선택면](./screen-composition.md) |
| [38](./feedback-and-loading.md#snippet-38) | 진행선, 장면 블러와 계산 상태 오버레이 | [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md) |
| [39](./controls-and-input.md#snippet-39) | 선택 버튼, 입력 포커스와 네이티브 컨트롤의 외형 | [버튼, 선택과 입력 컨트롤](./controls-and-input.md) |
| [40](./rendering-and-gestures.md#snippet-40) | 실제 렌더 표면과 SceneKit 재질 연결 | [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md) |
| [41](./rendering-and-gestures.md#snippet-41) | 카메라, 회전·확대, 조명과 바닥 | [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md) |
| [42](./rendering-and-gestures.md#snippet-42) | 마네킹과 의류의 재질, 음영, 안팎 표면 | [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md) |
| [43](./rendering-and-gestures.md#snippet-43) | 실제 실루엣과 외관을 결정하는 모델 리소스 | [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md) |
| [44](./assets-and-icons.md#snippet-44) | 보유한 브랜드·스플래시·앱 아이콘 자산 전체 | [이미지 자산, 폰트 파일과 아이콘](./assets-and-icons.md) |
| [45](./assets-and-icons.md#snippet-45) | SF Symbols와 동적인 아이콘 선택 | [이미지 자산, 폰트 파일과 아이콘](./assets-and-icons.md) |
| [46](./validation-and-inventory.md#snippet-46) | 직접 그리는 코드와 형상을 만드는 코드의 연결 | [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md) |
| [47](./validation-and-inventory.md#snippet-47) | 움직임과 화면 효과의 전체 빠른 인덱스 | [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md) |
| [48](./validation-and-inventory.md#snippet-48) | 참고 자산, 미구현 요소와 검증 한계 | [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md) |

<a id="migration-scope"></a>

## 재분류 범위와 검증 원칙

- 원문의 48개 번호 항목과 57개 코드 블록을 유지합니다. 26번의 상세 표와 번호 없는 리소스·파일·책임 경계 안내도 해당 종류별 문서로 옮겼습니다.
- 원본 Swift·SVG 발췌, 실제 값, 주의사항과 상대 경로를 보존합니다. 코드를 독립 실행 예제로 바꾸거나 새 앱 기능을 추가한 것은 아닙니다.
- 문서 사이의 번호 참조는 이동한 항목의 링크로 연결하고, 기존 README의 명시적 분류 앵커도 유지합니다.
- 이번 작업은 원문 재분류입니다. 앱 소스를 새로 조사하거나 빌드·UI 테스트·실기기 검수를 실행한 결과로 기존 구현 설명을 갱신한 것이 아닙니다.
- 원문의 코드 블록 보존, 항목 누락, 문서 탐색, 상대 경로와 이미지 src를 확인합니다. 실행 검증의 범위와 한계는 [검증·전체 인벤토리](./validation-and-inventory.md#snippet-24)와 [미구현·검증 한계](./validation-and-inventory.md#snippet-48)에 있습니다.
