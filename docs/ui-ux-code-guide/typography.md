# 타이포그래피, 캡션과 현지화

[전체 목차](./README.md) · [이전: 색상, 배경면과 대비](./colors-and-surfaces.md) · [다음: 선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

글자를 단순한 문자열이 아니라 위계·리듬·정보 밀도를 만드는 시각 요소로 분류합니다. 기능성 본문과 버튼은 가독성을, 제호와 큰 숫자는 편집 인상을 우선합니다. 줄별 제목의 움직임은 [07](./motion.md#snippet-07)에서 별도로 다룹니다.

## 요소 분류와 책임

| 요소 종류 | 구성과 시각적 역할 | 연결 |
| --- | --- | --- |
| 제호·큰 숫자 | Bodoni Moda 정체·이탤릭, optical size와 weight | 아래 26.2와 [02](#snippet-02) |
| 문장형 제목 | 영문 New York, 한글 나눔명조, 굵은 statement | 서체 역할을 바꾸기 전에 언어·문자 종류 확인 |
| 기능성 문자 | Helvetica Neue와 Pretendard 캐스케이드 | [02](#snippet-02) |
| 메타·치수·단위 | 모노 메타, 고정폭 숫자, 큰 값 옆 작은 단위 | 아래 26.2 |
| 제목 주변 편집 | Eyebrow, FIG. 캡션, N°, 세로 RunningHead | [28](#snippet-28) |
| 언어와 글씨 크기 | Dynamic Type, 줄바꿈, 시스템/한국어/영어/일본어 | [02](#snippet-02), [23](#snippet-23) |

## 문서 내 상세 항목

- [02. 영문과 한글 폰트 연결 및 시스템 글씨 크기](#snippet-02)
- [28. 제목, 번호, 캡션과 세로 러닝헤드](#snippet-28)
- [23. 화면 밖 코드에서도 같은 언어로 문구 생성](#snippet-23)
- [26.2. 서체·조판 전체와 번들 폰트](#visual-rules-type)

<a id="snippet-02"></a>

## 02. 영문과 한글 폰트 연결 및 시스템 글씨 크기

원본: [EditorialFonts.swift / sansDescriptor](../../weashion/weashion/Views/EditorialFonts.swift#L90)

```swift
static func sansDescriptor(weight: Font.Weight) -> UIFontDescriptor {
    var attributes: [UIFontDescriptor.AttributeName: Any] = [.name: latinSansName(for: weight)]
    if sansIsAvailable {
        let hangul = UIFontDescriptor(fontAttributes: [
            .name: sansName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                [NSNumber(value: weightTag): NSNumber(value: sansWeightValue(for: weight))]
        ])
        attributes[UIFontDescriptor.AttributeName(rawValue: kCTFontCascadeListAttribute as String)] = [hangul]
    }
    return UIFontDescriptor(fontAttributes: attributes)
}
```

- **역할:** 기능성 텍스트의 영문과 숫자는 Helvetica Neue를 사용하고, 한글은 Pretendard로 이어지도록 폰트 캐스케이드를 구성합니다.
- **수정 지점:** 영문 서체 선택은 같은 파일의 `latinSansName`, 한글 서체와 가중치는 `sansName`, `sansWeightValue`를 함께 봅니다.

원본: [EditorialFonts.swift / pointSize, sans](../../weashion/weashion/Views/EditorialFonts.swift#L109)

```swift
static func pointSize(for style: Font.TextStyle, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
    let uiStyle = style.uiTextStyle
    let base = UIFont.preferredFont(forTextStyle: uiStyle,
                                    compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
    let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSizeCategory)
    return UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: base, compatibleWith: traits)
}

static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular, dynamicTypeSize: DynamicTypeSize) -> Font {
    Font(sansUIFont(size: pointSize(for: style, dynamicTypeSize: dynamicTypeSize), weight: weight) as CTFont)
}
```

- **역할:** 커스텀 서체를 사용하면서도 본문, 캡션 등의 크기가 시스템 글씨 크기 설정을 따르게 합니다.
- **연결:** [editorialSans](../../weashion/weashion/Views/EditorialStyle.swift#L41)가 환경의 `dynamicTypeSize`를 받아 이 함수를 호출합니다.
- **서체 역할:** 제호와 큰 숫자는 Bodoni Moda, 문장형 영문 헤드라인은 시스템 세리프 New York, 한글 장식 제목은 나눔명조, 굵은 선언문은 기능성 산세리프 계열을 사용합니다.
- **주의:** 모든 장식 글자가 같은 비율로 무제한 확대되는 구조는 아닙니다. 제목은 별도 배율 제한과 접근성 처리를 가집니다.

<a id="snippet-28"></a>

## 28. 제목, 번호, 캡션과 세로 러닝헤드

원본: [EditorialStyle.swift / EditorialRunningHead.body](../../weashion/weashion/Views/EditorialStyle.swift#L511)

```swift
var body: some View {
    Text(text)
        .font(font ?? Font(EditorialFonts.sansUIFont(size: 11, weight: .medium) as CTFont))
        .tracking(tracking)
        .foregroundStyle(color)
        .fixedSize()
        .rotationEffect(.degrees(90), anchor: .topLeading)
        .offset(x: thickness)
        .frame(width: thickness, height: thickness, alignment: .topLeading)
        .accessibilityHidden(true)
}
```

- **화면 효과:** 작은 글자를 90도 돌려 지면 가장자리에서 아래로 늘어뜨립니다. 회전 애니메이션이 아니라 고정 조판입니다.
- **주의:** 회전 후 실제 길이와 레이아웃 프레임이 다르므로 호출부가 공간과 클리핑을 관리합니다.

| 컴포넌트 | 시각 장치 | 원본 |
| --- | --- | --- |
| `EditorialHeading` | 세리프 제목, 작은 부제, 버건디 `N°`와 상단 이중선 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L364) |
| `EditorialPageTitle` | 6×6pt 버건디 사각형, 섹션명, 지면 번호, 큰 제목, 선, 설명. 접근성 글씨에서는 장식 번호 생략 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L426) |
| `EditorialFigureCaption` | 이탤릭 `FIG.` 번호와 작은 산세리프 주석을 같은 기준선에 배치 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L466) |
| `EditorialEyebrow` | caption2, medium, 자간 1.5pt의 작은 섹션 머리말 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L488) |
| `EditorialRunningHead` | 표지와 사이즈 지면의 세로 메타 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L502) |
| `EditorialActionLabel` | 제목·설명·우측 화살표와 하단 얇은 선. 최소 높이 68pt | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L657) |
| `EditorialNavigationTitle` | 시스템 내비게이션 중앙에 커스텀 제목. ASCII는 세리프와 자간, 그 외는 한글 디스플레이 서체 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L799) |
| `EditorialToolbarButton` | 시스템 본문 서체와 한 줄 고정으로 툴바 문구 꺾임 방지 | [구현](../../weashion/weashion/Views/EditorialStyle.swift#L865) |

<a id="snippet-23"></a>

## 23. 화면 밖 코드에서도 같은 언어로 문구 생성

원본: [Localization.swift / L](../../weashion/weashion/Models/Localization.swift#L43)

```swift
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle, locale: L10n.locale)
}
```

- **역할:** 모델, 서비스, String 매개변수처럼 SwiftUI의 자동 현지화만으로 처리되지 않는 곳에서 같은 언어 설정을 적용합니다.
- **연결:** [AppLanguage와 L10n](../../weashion/weashion/Models/Localization.swift)이 시스템, 한국어, 영어, 일본어 선택과 번들을 결정합니다. [ContentView](../../weashion/weashion/ContentView.swift#L72)는 locale을 뷰 환경에도 전달합니다.
- **수정 지점:** 새 UI 문구는 [Localizable.xcstrings](../../weashion/weashion/Localizable.xcstrings)와 함께 관리합니다. 문자열 길이가 달라지므로 큰 글씨와 좁은 화면 배치도 확인합니다.

<a id="visual-rules-type"></a>

## 26.2. 서체·조판 전체와 번들 폰트

[26번 전체 분류](./design-principles.md#snippet-26)에서 이 문서로 옮긴 상세 표입니다.

| 장치 | 구현·역할 | 확인 위치 |
| --- | --- | --- |
| Bodoni Moda 정체·이탤릭 | 제호, 큰 숫자, 사이즈, 폴리오. variable font의 optical size와 weight 적용 | [display](../../weashion/weashion/Views/EditorialFonts.swift#L40) |
| New York 시스템 세리프 | 문장형 영문 헤드라인. 기본 이탤릭 | [headline](../../weashion/weashion/Views/EditorialStyle.swift#L21) |
| 나눔명조 | 한글 편집용 제목, 일부 상품명과 기상 문구 | [hangul](../../weashion/weashion/Views/EditorialFonts.swift#L57) |
| Helvetica Neue + Pretendard | 본문, 버튼, 입력, 한글 기능 텍스트 | [sansDescriptor](../../weashion/weashion/Views/EditorialFonts.swift#L90) |
| 굵은 statement | 강한 한글 제목. 산세리프 black 굵기 | [statement](../../weashion/weashion/Views/EditorialStyle.swift#L28) |
| 작은 모노스페이스 | 호수, 날짜, `SIZE`, `VIEW`, 프레임 구석의 메타 | [헤더](../../weashion/weashion/ContentView.swift#L330), [피팅 프레임](../../weashion/weashion/ContentView.swift#L1098) |
| `monospacedDigit` | 치수나 기온이 바뀌어도 숫자 폭을 안정화 | [치수 행](../../weashion/weashion/ContentView.swift#L1271) |
| `tracking`과 음수 줄 간격 | 대문자 메타의 벌림, 큰 제목의 촘촘한 편집 인상 | [Eyebrow](../../weashion/weashion/Views/EditorialStyle.swift#L488), [Title](../../weashion/weashion/Views/EditorialStyle.swift#L576) |
| 단위의 크기 대비 | 큰 값 옆의 작은 cm·kg·도 기호 | [bodyMetric](../../weashion/weashion/ContentView.swift#L1371) |
| 스케일 제한·줄바꿈 | 큰 장식 문자가 영역을 독점하지 않도록 제한. 의미 있는 설명은 자연 높이 유지 | [EditorialTitle](../../weashion/weashion/Views/EditorialStyle.swift#L549) |

번들 폰트는 [Fonts 폴더](../../weashion/weashion/Resources/Fonts)의 OFL 라이선스 문서와 함께 보관됩니다. 일본어의 가나·한자는 별도 일본어 번들이 아니라 시스템 폰트 폴백을 사용할 수 있습니다.

| 실제 번들 파일 | 역할·권리 문서 |
| --- | --- |
| [BodoniModa-Variable.ttf](../../weashion/weashion/Resources/Fonts/BodoniModa-Variable.ttf) | 정체 디스플레이, opsz 6~96·weight 400~900 범위로 코드에서 제한 |
| [BodoniModa-Italic-Variable.ttf](../../weashion/weashion/Resources/Fonts/BodoniModa-Italic-Variable.ttf) | 이탤릭 디스플레이 |
| [NanumMyeongjo-Regular.ttf](../../weashion/weashion/Resources/Fonts/NanumMyeongjo-Regular.ttf) | 한글 명조 정체 |
| [NanumMyeongjo-Bold.ttf](../../weashion/weashion/Resources/Fonts/NanumMyeongjo-Bold.ttf) | 한글 명조 굵은 제목 |
| [PretendardVariable.ttf](../../weashion/weashion/Resources/Fonts/PretendardVariable.ttf) | 한글 기능 텍스트와 굵은 statement |
| [OFL-BodoniModa.txt](../../weashion/weashion/Resources/Fonts/OFL-BodoniModa.txt) | Bodoni Moda 라이선스 |
| [OFL-NanumMyeongjo.txt](../../weashion/weashion/Resources/Fonts/OFL-NanumMyeongjo.txt) | 나눔명조 라이선스 |
| [OFL-Pretendard.txt](../../weashion/weashion/Resources/Fonts/OFL-Pretendard.txt) | Pretendard 라이선스 |

Helvetica Neue와 New York은 iOS 시스템 서체이며 위 폴더의 별도 폰트 파일이 아닙니다.

## 변경·검증 체크리스트

- 제호·장식 제목·본문·버튼 중 어떤 서체 역할을 바꾸는지 확인합니다.
- 라틴 서체만 바꾸고 한글 캐스케이드나 가중치 매핑을 빠뜨리지 않습니다.
- Dynamic Type에서 의미 있는 설명은 자연 높이를 유지하고, 장식 제목의 배율 제한과 구분합니다.
- 숫자가 바뀌는 치수 행의 고정폭 처리, 큰 숫자와 단위의 기준선을 확인합니다.
- 90도 세로 조판은 고정 배치이며, 회전 후 길이가 원래 레이아웃 프레임과 다르다는 점을 확인합니다.
- 한국어·영어·일본어의 문구 길이와 시스템 폴백을 확인하고 문자열 카탈로그를 함께 관리합니다.
- 줄별 제목 애니메이션을 바꾸면 [07](./motion.md#snippet-07)의 통합 접근성 제목과 모션 비활성 조건도 확인합니다.

## 함께 보는 문서

- [모션, 등장과 화면 전환](./motion.md): 모션 토큰, 스크롤 리빌, 제목 등장, 글자 교체, 스윕·패럴랙스와 소개·실행 전환을 모았습니다.
- [반응형 배치, 간격과 표시 컨테이너](./layout.md): 폭·글씨 크기·콘텐츠 요구 크기에 따른 열 배치, 그리드, 여백과 sheet/inspector를 구분합니다.
- [의류와 신체의 측정 도식](./measurement-diagrams.md): 의류 치수의 번호·강조선·값과 신체 앞/옆 실루엣·실선·점선·측정 강조를 구분합니다.
- [이미지 자산, 폰트 파일과 아이콘](./assets-and-icons.md): 실제 연결된 브랜드·스플래시·앱 아이콘, 보유 벡터, SF Symbols와 디자인 리소스 위치를 정리합니다.
