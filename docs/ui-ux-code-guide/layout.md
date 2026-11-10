# 반응형 배치, 간격과 표시 컨테이너

[전체 목차](./README.md) · [이전: 모션, 등장과 화면 전환](./motion.md) · [다음: 버튼, 선택과 입력 컨트롤](./controls-and-input.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

기기 이름 대신 실제 콘텐츠 폭과 글씨 크기를 기준으로 배치합니다. 전역 700pt 기준, horizontalSizeClass, ViewThatFits의 크기 검사는 서로 대체할 수 없는 별도 판단입니다. 선·면·간격의 실제 수치도 이 문서에 모았습니다.

## 요소 분류와 책임

| 배치 종류 | 판단 기준 | 적용 결과 |
| --- | --- | --- |
| 메인·체형 설정 열 | 실제 폭 700pt 이상이며 접근성 글씨가 아님 | 좌우 배치, 그 외 위아래 |
| 콘텐츠 높이 | viewport 높이와 min/max 제한 | 표지·마네킹 영역의 과도한 축소·확대 방지 |
| 편집 패널 | horizontalSizeClass가 regular인지 | sheet 또는 측면 inspector |
| 상품 그리드 | 최소 230pt, 최대 460pt의 adaptive 열 | 공간에 맞는 열 수, 접근성 글씨에서는 한 열 |
| 치수 도식+설명 | 실제 가로 후보가 들어가는지 | ViewThatFits 또는 세로 흐름 |
| 바깥 여백·선·모서리 | 화면별 현재 상수와 호출부 | 모든 화면·컨트롤에 하나의 수치를 강제하지 않음 |

## 문서 내 상세 항목

- [11. 한 열과 두 열을 결정하는 공통 기준](#snippet-11)
- [12. 같은 콘텐츠를 가로 또는 세로로 배치](#snippet-12)
- [13. 치수 편집을 sheet 또는 inspector로 표시](#snippet-13)
- [14. 상품 보관함의 가변 그리드](#snippet-14)
- [15. 치수 도식과 설명이 실제로 들어가는 배치 선택](#snippet-15)
- [26.3. 실제 코드의 선·면·간격](#visual-rules-layout)

<a id="snippet-11"></a>

## 11. 한 열과 두 열을 결정하는 공통 기준

원본: [EditorialStyle.swift / EditorialLayout](../../weashion/weashion/Views/EditorialStyle.swift#L224)

```swift
enum EditorialLayout {
    static let minimumControlSize: CGFloat = 44

    static func usesColumns(width: CGFloat, accessibility: Bool) -> Bool {
        width >= 700 && !accessibility
    }

    static func margin(wide: Bool) -> CGFloat {
        wide ? 48 : 20
    }

    static func stageHeight(viewportHeight: CGFloat, wide: Bool) -> CGFloat {
        min(wide ? 600 : 440, max(wide ? 400 : 280, viewportHeight - (wide ? 360 : 430)))
    }

    /// Leave room for the product, size rail and primary action on an ordinary phone viewport.
    static func coverHeight(viewportHeight: CGFloat, wide: Bool) -> CGFloat {
        min(wide ? 660 : 500, max(wide ? 440 : 280, viewportHeight - 350))
    }
}
```

- **판단 기준:** 기기 이름이 아니라 실제 사용 가능한 콘텐츠 폭 700pt를 기준으로 합니다. 접근성 글씨 크기이면 폭이 넓어도 한 열입니다.
- **높이 보정:** `min`과 `max`로 마네킹 영역이 너무 작거나 커지지 않게 제한합니다.
- **연결:** [mainLayout](../../weashion/weashion/ContentView.swift#L102)의 `GeometryReader`가 실제 너비와 높이를 읽어 위 함수에 전달합니다. 메인 콘텐츠의 최대 폭은 1180pt입니다.
- **수정 지점:** 700pt 기준을 바꾸면 [24](./validation-and-inventory.md#snippet-24)의 경계값 테스트도 함께 바뀌어야 합니다. 모든 화면이 이 함수를 공유하는 것은 아니므로 소개 화면의 자체 기준도 확인합니다.

<a id="snippet-12"></a>

## 12. 같은 콘텐츠를 가로 또는 세로로 배치

원본: [BodySetupView.swift / 레이아웃 선택 부분](../../weashion/weashion/Views/BodySetupView.swift#L30)

```swift
let wide = EditorialLayout.usesColumns(width: geometry.size.width,
                                       accessibility: dynamicTypeSize.isAccessibilitySize)
let layout = wide
    ? AnyLayout(HStackLayout(alignment: .top, spacing: 36))
    : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
```

- **역할:** `AnyLayout`으로 배치 방식만 선택하고 이어지는 `layout` 본문에서 마네킹과 입력 영역을 배치합니다.
- **화면 효과:** 넓으면 좌우, 좁거나 글씨가 크면 위아래로 흐릅니다.
- **주의:** 이 코드만으로 모든 하위 상태나 렌더러 재사용이 보장되는 것은 아닙니다. 별도의 identity 분기와 3D 상태 소유권을 함께 봐야 합니다.
- **관련 화면:** [GarmentEditorView](../../weashion/weashion/Views/GarmentEditorView.swift#L56)도 공통 폭 기준을 사용하지만 가로/세로 뷰를 조건 분기로 구성합니다.

<a id="snippet-13"></a>

## 13. 치수 편집을 sheet 또는 inspector로 표시

원본: [ContentView.swift / 상품 편집 표시](../../weashion/weashion/ContentView.swift#L181)

```swift
.sheet(isPresented: garmentEditorPresentation(inspector: false)) {
    garmentEditor(profile: profile)
}
.inspector(isPresented: garmentEditorPresentation(inspector: true)) {
    garmentEditor(profile: profile)
        .inspectorColumnWidth(min: 340, ideal: 400, max: 460)
}
```

- **역할:** 같은 편집 기능을 좁은 환경에서는 시스템 sheet, 넓은 환경에서는 측면 inspector로 엽니다.
- **판단 기준:** [usesInspector](../../weashion/weashion/ContentView.swift#L42)는 `horizontalSizeClass == .regular`를 사용합니다.
- **중요한 구분:** 본문 2열의 700pt 기준과 패널 표시의 size class 기준은 서로 다릅니다.
- **수정 지점:** [garmentEditorPresentation](../../weashion/weashion/ContentView.swift#L241)의 Binding이 어느 표시 경로를 활성화할지 제어합니다. 두 경로를 무조건 동시에 열면 안 됩니다.

<a id="snippet-14"></a>

## 14. 상품 보관함의 가변 그리드

원본: [ProductLibraryView.swift / 상품 목록](../../weashion/weashion/Views/ProductLibraryView.swift#L46)

```swift
LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
          ? [GridItem(.flexible(), alignment: .leading)]
          : [GridItem(.adaptive(minimum: 230, maximum: 460), spacing: 28, alignment: .leading)],
          alignment: .leading, spacing: 36) {
    ForEach(Array(room.library.products.enumerated()), id: \.element.id) { index, product in
        productTile(product, index: index)
    }
}
```

- **화면 효과:** 일반 글씨에서는 최소 열 너비 230pt를 기준으로 공간에 맞는 열 수를 만듭니다.
- **접근성:** 큰 글씨에서는 무조건 한 열로 바꿔 상품명과 사이즈 설명을 읽기 쉽게 합니다.
- **수정 지점:** 타일 크기는 `adaptive` 범위, 좌우 간격은 GridItem의 `spacing`, 행 간격은 LazyVGrid의 `spacing`이 담당합니다.

<a id="snippet-15"></a>

## 15. 치수 도식과 설명이 실제로 들어가는 배치 선택

원본: [EditorialGarmentSpread.swift / GarmentMeasurementPlate](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L39)

```swift
ViewThatFits(in: .horizontal) {
    HStack(alignment: .center, spacing: 36) {
        diagram.frame(width: 280)
        measurementNotes.frame(minWidth: 240)
    }
    .frame(minWidth: 560)
    VStack(alignment: .leading, spacing: 24) {
        diagram
        measurementNotes
    }
}
```

- **역할:** 후보를 위에서부터 검사해 가로 공간에 들어가는 첫 배치를 선택합니다.
- **화면 효과:** 공간이 충분하면 도식과 치수를 나란히, 부족하면 위아래로 보여줍니다.
- **접근성:** 바깥 조건에서 접근성 글씨는 이 가로 후보를 건너뛰고 세로 흐름을 사용합니다.
- **주의:** 700pt 전역 기준과 달리 이 부분은 콘텐츠의 요구 크기를 보고 적응합니다. 두 방식은 사용 목적이 다릅니다.

<a id="visual-rules-layout"></a>

## 26.3. 실제 코드의 선·면·간격

[26번 전체 분류](./design-principles.md#snippet-26)에서 이 문서로 옮긴 상세 표입니다.

| 요소 | 현재 구현 예 |
| --- | --- |
| 작은/넓은 메인 바깥 여백 | 20 / 48pt. 설계 문서의 초기 후보 32~40pt와 혼동하지 않음 |
| 메인 콘텐츠 최대 폭 | 1180pt. 상품 목록 1080pt, 설정 760pt 등 화면별 별도 제한 존재 |
| 본문 열 간격 | 메인 spread는 40pt 또는 32pt. 각 화면은 별도 간격 사용 |
| 구분선 | 보통 0.5pt, 이중선은 1pt + 0.5pt, 간격 3pt |
| 선택·포커스 선 | 1.5~2pt 강조. 선 너비와 실제 터치 범위는 별개 |
| 모서리 | CTA·입력 관련 일부 면 3pt, 체형 배지 2pt, 선택 탭 5pt, 하단 바 9pt |
| 그림자·블러 | 스튜디오의 2D 타원 블러 12pt, 하늘의 구름 블러, 계산 중 장면 블러 5pt |
| 안전 영역 | 하단 조작바, 상단 저장 안내, sheet·inspector 및 키보드의 시스템 영역 |

**주의:** '직각 중심 디자인'은 현재 모든 모서리가 0이라는 뜻이 아닙니다. 실제 수치는 소스를 우선합니다.

## 변경·검증 체크리스트

- 일반 글씨에서 699pt와 700pt, 넓은 폭에서 접근성 글씨의 한 열 배치를 확인합니다.
- 기기 모델이 아니라 GeometryReader가 전달하는 실제 사용 가능 크기를 기준으로 판단합니다.
- 열 분기와 sheet/inspector의 size class 분기를 하나로 합치지 않습니다.
- 가로·세로 전환에서 선택·입력·3D 상태의 소유권과 identity를 확인합니다.
- 키보드·안전 영역·저장 안내·하단 조작바가 필요한 콘텐츠 공간을 가리지 않는지 확인합니다.
- 치수 도식은 700pt만 보지 말고 도식+설명의 실제 요구 크기와 큰 글씨 분기를 확인합니다.
- 레이아웃 경계값을 바꾸면 [24](./validation-and-inventory.md#snippet-24)의 판단 함수 테스트와 관련 UI 테스트를 함께 검토합니다.

## 함께 보는 문서

- [타이포그래피, 캡션과 현지화](./typography.md): 서체의 역할, 한글 폴백, 크기 대응, 제목·캡션·세로 조판과 다국어 문구를 다룹니다.
- [버튼, 선택과 입력 컨트롤](./controls-and-input.md): CTA·선택 버튼·눌림·입력 포커스·오류 이동과 시스템 컨트롤의 외형·동작을 다룹니다.
- [화면별 구도, 내비게이션과 선택면](./screen-composition.md): 표지·날씨 지면·피팅룸·체형·편집·소개 화면의 배치와 헤더·내비게이션·선택면을 연결합니다.
- [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md): 경계값 테스트, 전체 시각 타입·효과·형상 생성 경로와 미구현·미확인 요소를 한곳에서 찾습니다.
