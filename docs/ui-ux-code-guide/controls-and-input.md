# 버튼, 선택과 입력 컨트롤

[전체 목차](./README.md) · [이전: 반응형 배치, 간격과 표시 컨테이너](./layout.md) · [다음: 저장 피드백, 오류와 진행 상태](./feedback-and-loading.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

눈에 보이는 버튼의 면·선·문자와 실제 조작 영역을 함께 다룹니다. 최소 크기가 다른 주요 CTA, 일반 조작, 입력면을 구분하고, 입력 실패를 해당 항목으로 복구하는 연결까지 유지합니다. 저장 결과의 표시 자체는 [17](./feedback-and-loading.md#snippet-17)에 있습니다.

## 요소 분류와 책임

| 컨트롤 종류 | 기본 표현·크기 | 상태·동작 |
| --- | --- | --- |
| 주요 CTA | 최소 높이 52pt, 반경 3pt | filled / inverted / accented 조합 |
| 일반 조작 | 기본 최소 44pt 조작 영역 | 텍스트·아이콘·밑줄 등 호출부별 표현 |
| 선택 버튼 | 최소 높이 46pt, 버건디 선택면 | 선택 특성, 체크·문구와 비활성 상태 |
| 입력면 | 최소 높이 48pt, Stock 면과 밑줄 | 포커스·오류 선, 여백 탭으로 포커스 |
| 눌림 | 축소 0.97, 명도·불투명도 변화 | Reduce Motion에서는 축소·애니메이션 생략 |
| 오류 항목 이동 | 안내 버튼과 필드 id | 스크롤 대상·focusedField·표시 이름의 대응 |
| 네이티브 컨트롤 | Picker·Slider·Toggle·List·Menu 등 | OS 외형과 커스텀 스타일의 경계 유지 |

## 문서 내 상세 항목

- [03. 주요 행동 버튼의 공통 형태](#snippet-03)
- [05. 버튼 눌림 피드백](#snippet-05)
- [16. 입력칸의 터치 범위와 잘못된 항목으로 이동](#snippet-16)
- [39. 선택 버튼, 입력 포커스와 네이티브 컨트롤의 외형](#snippet-39)

<a id="snippet-03"></a>

## 03. 주요 행동 버튼의 공통 형태

원본: [EditorialStyle.swift / EditorialButtonStyle](../../weashion/weashion/Views/EditorialStyle.swift#L139)

```swift
struct EditorialButtonStyle: ButtonStyle {
    var filled = false
    var inverted = false
    var accented = false

    func makeBody(configuration: Configuration) -> some View {
        let foreground = inverted ? Editorial.paper : accented ? Editorial.accent : Editorial.ink
        let background = inverted ? Editorial.ink : Editorial.paper
        return configuration.label
            .editorialSans(.subheadline, weight: .semibold)
            .tracking(0.1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .foregroundStyle(filled ? background : foreground)
            .background(filled ? foreground : .clear)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(foreground.opacity(filled ? 1 : 0.4), lineWidth: 0.75))
            .clipShape(.rect(cornerRadius: 3))
            .modifier(EditorialPressFeedback(isPressed: configuration.isPressed, scalesOnPress: filled))
            .contentShape(Rectangle())
    }
}
```

- **역할:** 적용, 저장 등의 주요 버튼을 같은 높이, 여백, 테두리로 통일합니다.
- **화면 효과:** 최소 높이 52pt, 모서리 반경 3pt의 비교적 각진 버튼입니다. `filled`, `inverted`, `accented`로 채움과 색상을 조합합니다.
- **연결:** 채움 버튼의 눌림 축소는 [05](#snippet-05)의 `EditorialPressFeedback`이 담당합니다.
- **주의:** 별도의 [EditorialPressStyle](../../weashion/weashion/Views/EditorialStyle.swift#L245)도 있습니다. 일반 버튼의 터치 영역과 피드백까지 바꾸려면 둘을 구분해서 확인합니다.

<a id="snippet-05"></a>

## 05. 버튼 눌림 피드백

원본: [EditorialStyle.swift / EditorialPressFeedback](../../weashion/weashion/Views/EditorialStyle.swift#L272)

```swift
private struct EditorialPressFeedback: ViewModifier {
    let isPressed: Bool
    var scalesOnPress = false
    var dimsWhenDisabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .opacity(!isEnabled && dimsWhenDisabled ? 0.4 : isPressed ? scalesOnPress ? 0.92 : 0.7 : 1)
            .brightness(isEnabled && isPressed && scalesOnPress ? 0.025 : 0)
            .scaleEffect(isPressed && scalesOnPress && !reduceMotion ? EditorialMotion.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: EditorialMotion.pressDuration), value: isPressed)
    }
}
```

- **화면 효과:** 누를 때 조금 작아지고 명도가 바뀝니다. 비활성 상태는 기본적으로 불투명도 0.4로 표현합니다.
- **접근성:** 동작 줄이기에서는 축소와 애니메이션을 생략하되 명도 차이로 상태는 전달합니다.
- **주의:** 실제 버튼 기능은 버튼의 action이 처리합니다. 애니메이션 종료까지 기능을 지연시키는 코드가 아닙니다.

<a id="snippet-16"></a>

## 16. 입력칸의 터치 범위와 잘못된 항목으로 이동

원본: [EditorialStyle.swift / EditorialTextField](../../weashion/weashion/Views/EditorialStyle.swift#L841)

```swift
struct EditorialTextField: View {
    let title: String
    @Binding var text: String
    var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorialEyebrow(text: title)
            TextField(title, text: $text)
                .editorialSans(.body)
                .focused($focused)
                .editorialInput(focused: focused, invalid: invalid)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focused = true })
                .submitLabel(.done)
                .onSubmit { focused = false }
                .accessibilityLabel(title)
        }
    }
}
```

- **역할:** 입력 여백을 눌러도 포커스가 연결되며 키보드의 완료 동작으로 포커스를 해제합니다.
- **시각 표현:** [EditorialInputSurface](../../weashion/weashion/Views/EditorialStyle.swift#L820)가 최소 높이 48pt와 바탕색, 포커스/오류 밑줄을 담당합니다.

원본: [GarmentEditorView.swift / 오류 항목 안내](../../weashion/weashion/Views/GarmentEditorView.swift#L84)

```swift
if let field = firstInvalidField {
    Button {
        withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) {
            proxy.scrollTo(field, anchor: .center)
        }
        focusedField = field
    } label: {
        Label("\(field) 입력 확인하기", systemImage: "exclamationmark.circle")
            .editorialSans(.caption)
            .foregroundStyle(Editorial.error)
            .frame(minHeight: 44)
    }
    .accessibilityIdentifier("reviewInvalidMeasurement")
}
```

- **화면 효과:** 잘못된 항목을 알려주는 버튼을 누르면 해당 입력칸으로 스크롤하고 커서를 연결합니다.
- **연결:** `firstInvalidField`가 안내할 항목을 계산하고, `ScrollViewReader`의 `proxy`가 이동을 처리합니다.
- **주의:** 필드 이름, 스크롤 대상의 id, `focusedField` 값이 일치해야 합니다. 명칭이나 현지화를 바꿀 때 이 연결도 보존해야 합니다.

<a id="snippet-39"></a>

## 39. 선택 버튼, 입력 포커스와 네이티브 컨트롤의 외형

원본: [EditorialStyle.swift / EditorialChoiceStyle.makeBody](../../weashion/weashion/Views/EditorialStyle.swift#L258)

```swift
func makeBody(configuration: Configuration) -> some View {
    configuration.label
        .frame(minWidth: EditorialLayout.minimumControlSize, maxWidth: .infinity, minHeight: 46)
        .foregroundStyle(selected ? Editorial.paper : Editorial.ink)
        .background(selected ? Editorial.accent : .clear)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? Editorial.accent : Editorial.rule, lineWidth: 0.5))
        .clipShape(.rect(cornerRadius: 3))
        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: selected)
        .modifier(EditorialPressFeedback(isPressed: configuration.isPressed, scalesOnPress: true, dimsWhenDisabled: !selected))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
}
```

| 컨트롤 | 눈에 보이는 외형과 사용처 |
| --- | --- |
| 공통 선택 버튼 | 버건디 채움/Paper 글자와 비선택의 얇은 테두리. 샘플·계절·체형 선택 |
| 입력면 | Stock 40%, 최소 높이 48pt, 기본 0.5pt 선 -> 포커스/오류 1.5pt 선 |
| 일반 버튼 | 최소 44pt 영역과 눌림, 밑줄 텍스트 링크와 화살표, 일부 bordered 시스템 버튼 |
| Segmented Picker | 언어, 성별, 체형, 두께, 비교 종류 등. 시스템의 선택 캡슐과 문자 |
| Menu Picker·Menu | 의류/기준 모델/재질 선택, 관리 ellipsis. 시스템 메뉴·선택 표시 |
| Slider | 체형·부위 조절의 트랙·thumb, 끝의 숫자·%. 주로 Accent tint |
| Toggle | 직접 측정 확인, 저장 후 체형 사용, 선택 치수 켜기/끄기 |
| DisclosureGroup | 세부 부위, 날씨 조정, 추가 정보, 계산·사이즈 비교. chevron과 실제 높이 변화 |
| List·Form·Section | 체형 편집·측정 안내의 행, 그룹, 제목과 시스템 구분선. 편집 List는 plain 및 시스템 배경 숨김 |
| sheet·inspector·fullScreenCover | 시스템 패널 모서리·전환, 일부 medium/large detent와 drag indicator |
| alert·confirmationDialog | 오류와 삭제 확인의 시스템 아이콘·버튼 배치, destructive 색상 |
| 키보드·toolbar | decimalPad, URL 키보드, 완료·키보드 닫기, 한 줄 툴바 버튼 |

네이티브 컨트롤은 OS 버전에 따라 모양이 달라질 수 있습니다. 이 앱이 모든 캡슐, 체크, 펼침 표시를 커스텀 Path로 그리는 것은 아닙니다.

## 변경·검증 체크리스트

- 보이는 선이나 아이콘의 크기와 실제 contentShape·최소 터치 크기를 구분해 확인합니다.
- 채움·역상·선택·비활성 조합에서 문구와 선이 사라지지 않는지 확인합니다.
- 눌림 애니메이션이 실제 action을 지연시키지 않는지 확인합니다.
- 입력 여백 탭과 키보드 완료 동작이 포커스와 연결되는지 확인합니다.
- 잘못된 항목 안내의 이름, ScrollView id, focusedField가 같은 항목을 가리키는지 확인합니다.
- 색뿐 아니라 체크·문구·isSelected 특성으로 선택을 전달합니다.
- 시스템 메뉴·패널·키보드의 OS별 외형을 앱의 고정 Path 구현처럼 설명하지 않습니다.

## 함께 보는 문서

- [색상, 배경면과 대비](./colors-and-surfaces.md): 종이색·잉크색·버건디 토큰과 상태색, 역상, 호출부별 불투명도를 구분합니다.
- [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md): 실제 저장 결과, 오류 alert, 늦은 화면 준비 예고와 계산 중 진행선·블러·오버레이를 구분합니다.
- [반응형 배치, 간격과 표시 컨테이너](./layout.md): 폭·글씨 크기·콘텐츠 요구 크기에 따른 열 배치, 그리드, 여백과 sheet/inspector를 구분합니다.
- [의류와 신체의 측정 도식](./measurement-diagrams.md): 의류 치수의 번호·강조선·값과 신체 앞/옆 실루엣·실선·점선·측정 강조를 구분합니다.
