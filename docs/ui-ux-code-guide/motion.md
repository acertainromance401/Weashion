# 모션, 등장과 화면 전환

[전체 목차](./README.md) · [이전: 선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md) · [다음: 반응형 배치, 간격과 표시 컨테이너](./layout.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

시간 기반 전환, 스크롤 위치에 연결된 이동, 고정 회전은 서로 다른 종류입니다. 효과의 존재와 현재 호출 여부도 구분합니다. 눌림 피드백은 [05](./controls-and-input.md#snippet-05), 선 리빌은 [27](./editorial-graphics.md#snippet-27), 실제 준비 중 진행선은 [38](./feedback-and-loading.md#snippet-38)에서 다룹니다.

## 요소 분류와 책임

| 모션 종류 | 트리거·시간 | 경계 |
| --- | --- | --- |
| 공통 시간·곡선 | 눌림 100ms, 상태 220ms, 피드백 160ms 등 | editorial 곡선 함수 자체가 접근성 분기를 포함하지는 않음 |
| 스크롤 리빌 | 실제 노출 18%, 기본 48pt 이동 | 뷰 상태가 유지되는 동안 한 번. 재생 수명과 identity 확인 |
| 제목 줄 등장 | 명시적 줄바꿈, 줄당 640ms·80ms 간격 | 자동으로 감긴 모든 시각적 줄을 추적하는 기능이 아님 |
| 문자 교체 | 표지 interpolate, 별도 상하 교체 컴포넌트 | 상하 교체 컴포넌트의 현재 직접 호출은 미확인 |
| 장식 스윕 | 지면 변경, 440ms | 화면 준비 완료나 3D 이동을 제어하지 않음 |
| 패럴랙스 | 스크롤 위치, 표지 ±10pt·하늘판 ±16pt | 반복 타이머가 아니며 배경에 국한 |
| 소개·실행 전환 | 소개 8pt+페이드, 스플래시 준비+최소 시간 | 스플래시와 일반 지면 준비의 시간 정책은 다름 |

## 문서 내 상세 항목

- [04. 모션의 속도, 이동량, 감속 곡선](#snippet-04)
- [06. 스크롤 등장과 마스크 진입](#snippet-06)
- [07. 큰 제목을 줄마다 드러내기](#snippet-07)
- [08. 사이즈 글자의 상하 교체 컴포넌트: 현재 직접 사용 미확인](#snippet-08)
- [09. 탭을 바꿀 때 헤더를 통과하는 띠](#snippet-09)
- [10. 표지의 스크롤 패럴랙스](#snippet-10)
- [21. 브랜드 소개 페이지의 전환](#snippet-21)
- [22. 실행 스플래시와 본문 전환](#snippet-22)

<a id="snippet-04"></a>

## 04. 모션의 속도, 이동량, 감속 곡선

원본: [EditorialStyle.swift / EditorialMotion 상수](../../weashion/weashion/Views/EditorialStyle.swift#L161)

```swift
static let pressDuration = 0.1
static let transitionDuration = 0.22
static let feedbackDuration = 0.16
static let titleDuration = 0.64
static let titleStagger = 0.08
static let pageDuration = 0.44
static let ruleDuration = 0.5
static let entranceDuration = 0.8
static let glyphDuration = 0.28
static let revealOffset: CGFloat = 48
static let revealThreshold = 0.18
static let pressScale: CGFloat = 0.97
```

| 값 | 의미 |
| --- | --- |
| `pressDuration` / `pressScale` | 100ms 동안 0.97배 눌림 |
| `transitionDuration` | 선택, 펼침 등 220ms 상태 전환 |
| `feedbackDuration` | 저장 안내 등 160ms 피드백 |
| `titleDuration` / `titleStagger` | 제목 한 줄당 640ms, 줄별 시작 간격 80ms |
| `pageDuration` | 지면 스윕 등에 사용하는 440ms |
| `ruleDuration` | 구분선 리빌 500ms |
| `entranceDuration` | 제호 등 진입 효과 800ms |
| `glyphDuration` | 큰 사이즈 글자 교체 280ms |
| `revealOffset` / `revealThreshold` | 기본 이동 48pt, 스크롤 노출 기준 18% |

원본: [EditorialStyle.swift / 모션 생성 함수](../../weashion/weashion/Views/EditorialStyle.swift#L191)

```swift
static func editorial(_ duration: Double) -> Animation {
    .timingCurve(0.16, 1, 0.3, 1, duration: duration)
}

static func transition(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .easeInOut(duration: transitionDuration)
}

static func feedback(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: feedbackDuration)
}

static func page(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : editorial(pageDuration)
}

static func allowsTitleMotion(reduceMotion: Bool, voiceOver: Bool, accessibility: Bool) -> Bool {
    !reduceMotion && !voiceOver && !accessibility
}
```

- **역할:** 긴 감속 곡선과 짧은 상태 변화를 구분하고 접근성 분기를 한곳에서 공유합니다.
- **수정 지점:** 앱 전체 모션 리듬을 바꾸려면 개별 화면의 숫자보다 공통 상수부터 검토합니다.
- **주의:** `editorial(duration)` 자체에는 접근성 분기가 없습니다. 호출부가 직접 조건을 확인하는 경우도 있으므로 이 함수만 보고 모든 효과가 자동으로 꺼진다고 해석하면 안 됩니다.

<a id="snippet-06"></a>

## 06. 스크롤 등장과 마스크 진입

원본: [EditorialStyle.swift / EditorialReveal](../../weashion/weashion/Views/EditorialStyle.swift#L288)

```swift
private struct EditorialReveal: ViewModifier {
    var delay = 0.0
    var distance = EditorialMotion.revealOffset
    var from = Edge.bottom
    var onScroll = true
    var masked = false
    var enabled = true
    var duration = EditorialMotion.titleDuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var hasAppeared = false

    /// Content stays faintly present (never fully transparent) so it remains in the
    /// accessibility tree and reachable by assistive technologies before it scrolls in.
    private var isStatic: Bool { !enabled || reduceMotion || voiceOver }

    func body(content: Content) -> some View {
        let moving = content
            .opacity(isStatic || hasAppeared ? 1 : 0.02)
            .offset(EditorialMotion.offset(from: from, distance: distance, revealed: isStatic || hasAppeared))
        Group {
            if masked { moving.clipped() }
            else { moving }
        }
            .onAppear {
                guard !onScroll, !hasAppeared else { return }
                withAnimation(isStatic ? nil : EditorialMotion.editorial(duration).delay(delay)) {
                    hasAppeared = true
                }
            }
            .onScrollVisibilityChange(threshold: EditorialMotion.revealThreshold) { visible in
                guard onScroll, visible, !hasAppeared else { return }
                withAnimation(isStatic ? nil : EditorialMotion.editorial(duration).delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}
```

- **처리 순서:** 처음에는 약간 비치고 이동한 상태 -> 화면 등장 또는 스크롤 노출 감지 -> 최종 위치와 불투명도 1로 전환합니다.
- **구분:** `onScroll`은 실제 노출 시점을 기다리고, `masked`는 이동 중 뷰 바깥 부분을 잘라냅니다.
- **반복 범위:** `hasAppeared`로 같은 뷰의 상태가 유지되는 동안 재생을 막습니다. 뷰가 제거되거나 identity가 바뀌면 새로 재생될 수 있습니다.
- **접근성:** 동작 줄이기나 VoiceOver에서는 이동 없이 완전히 표시합니다.

원본: [EditorialStyle.swift / 공개 등장 modifier](../../weashion/weashion/Views/EditorialStyle.swift#L353)

```swift
func editorialReveal(delay: Double = 0, from: Edge = .bottom, distance: CGFloat = EditorialMotion.revealOffset) -> some View {
    modifier(EditorialReveal(delay: delay, distance: distance, from: from))
}

func editorialEntrance(delay: Double = 0, from: Edge = .bottom,
                      distance: CGFloat = EditorialMotion.revealOffset, enabled: Bool = true) -> some View {
    modifier(EditorialReveal(delay: delay, distance: distance, from: from,
                             onScroll: false, masked: true, enabled: enabled, duration: EditorialMotion.entranceDuration))
}
```

- **사용처:** 후속 콘텐츠는 `editorialReveal`, 표지 제호처럼 화면 진입에 맞춘 요소는 `editorialEntrance`를 사용합니다.
- **수정 지점:** `delay`, `from`, `distance`는 개별 연출을, 내부 modifier는 공통 동작을 바꿉니다.

<a id="snippet-07"></a>

## 07. 큰 제목을 줄마다 드러내기

원본: [EditorialStyle.swift / EditorialTitle.body](../../weashion/weashion/Views/EditorialStyle.swift#L576)

```swift
var body: some View {
    let lines = text.components(separatedBy: "\n")
    VStack(alignment: alignment, spacing: style == .display ? -scaledSize * 0.2 : style == .displayItalic ? -scaledSize * 0.06 : style == .statement ? -scaledSize * 0.12 : 0) {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            Text(line)
                .font(titleFont)
                .tracking(style == .statement ? -1.5 : -0.5)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .padding(.vertical, 2)
                .modifier(EditorialReveal(delay: Double(index) * EditorialMotion.titleStagger,
                                         distance: scaledSize * 1.15, onScroll: revealsOnScroll,
                                         masked: true, enabled: usesMotion))
        }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
    .accessibilityAddTraits(.isHeader)
    .transaction { if !usesMotion { $0.animation = nil; $0.disablesAnimations = true } }
}
```

- **화면 효과:** 명시적인 줄바꿈으로 나눈 제목이 각 줄의 마스크 안에서 올라옵니다. 자동 줄바꿈된 모든 시각적 줄을 별도로 추적하는 구현은 아닙니다.
- **핵심 계산:** `index * titleStagger`가 순차 등장 간격, `scaledSize * 1.15`가 이동량입니다.
- **접근성:** 시각적으로는 여러 Text지만 VoiceOver에는 줄바꿈을 제거한 하나의 제목으로 전달합니다. `usesMotion`은 동작 줄이기, VoiceOver, 접근성 글씨 크기에서 꺼집니다.
- **수정 지점:** 제목 크기와 스타일은 같은 타입의 `scaledSize`, `titleFont`도 함께 확인합니다.

<a id="snippet-08"></a>

## 08. 사이즈 글자의 상하 교체 컴포넌트: 현재 직접 사용 미확인

원본: [EditorialStyle.swift / EditorialDisplayGlyph](../../weashion/weashion/Views/EditorialStyle.swift#L525)

```swift
struct EditorialDisplayGlyph: View {
    let text: String
    var size: CGFloat = 150
    var italic = true
    var color = Editorial.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(Editorial.serif(size, italic: italic))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .id(text)
                .transition(reduceMotion ? .identity :
                    .asymmetric(insertion: .offset(y: size * 0.4).combined(with: .opacity),
                                removal: .offset(y: -size * 0.3).combined(with: .opacity)))
        }
        .clipped()
        .animation(reduceMotion ? nil : EditorialMotion.editorial(EditorialMotion.glyphDuration), value: text)
    }
}
```

- **구현된 효과:** 이 컴포넌트를 사용하면 이전 글자는 위로 사라지고 새 글자는 아래에서 들어옵니다.
- **핵심:** `.id(text)`가 텍스트 변경을 뷰 교체로 인식시켜 삽입과 제거 transition을 실행합니다.
- **현재 연결 상태:** 타입 정의는 있지만 현재 앱 Swift 소스에서 `EditorialDisplayGlyph(...)` 호출은 확인되지 않습니다. 보유한 효과 구현과 실제 표시 중인 효과를 구분합니다.
- **현재 보이는 사이즈 효과:** 표지는 별도로 [contentTransition(.interpolate)](../../weashion/weashion/ContentView.swift#L515)를 사용합니다. 현재 모든 사이즈 글자에 이 상하 교체가 적용된다고 설명하지 않습니다.

<a id="snippet-09"></a>

## 09. 탭을 바꿀 때 헤더를 통과하는 띠

원본: [EditorialStyle.swift / EditorialPageSweep](../../weashion/weashion/Views/EditorialStyle.swift#L327)

```swift
struct EditorialPageSweep: View {
    let page: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if !reduceMotion {
                Color.clear.keyframeAnimator(initialValue: CGFloat.zero, trigger: page) { _, progress in
                    Rectangle()
                        .fill(Editorial.accent)
                        .frame(width: geometry.size.width * 0.35)
                        .offset(x: geometry.size.width * (1.35 * progress - 0.35))
                } keyframes: { _ in
                    LinearKeyframe(CGFloat.zero, duration: 0)
                    CubicKeyframe(CGFloat(1), duration: EditorialMotion.pageDuration)
                }
            }
        }
        .frame(height: 3)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

- **화면 효과:** 헤더 너비의 35%, 높이 3pt인 버건디 띠가 440ms 동안 지나갑니다.
- **트리거:** `page` 값이 바뀌면 keyframe 애니메이션이 실행됩니다.
- **UX 경계:** 장식이므로 터치와 접근성 탐색에서 제외하고, 동작 줄이기에서는 생성하지 않습니다. 이 띠가 3D 장면을 움직이는 것은 아닙니다.

<a id="snippet-10"></a>

## 10. 표지의 스크롤 패럴랙스

원본: [ContentView.swift / cover 내부 배경](../../weashion/weashion/ContentView.swift#L466)

```swift
WeatherBackdrop(mood: weather.mood)
    .scaleEffect(reduceMotion ? 1 : 1.06)
    .visualEffect { [reduceMotion] content, geometry in
        content.offset(y: reduceMotion ? 0 :
            EditorialMotion.parallaxOffset(minY: geometry.frame(in: .scrollView).minY, limit: 10))
    }
```

- **화면 효과:** 배경만 1.06배 확대하고 스크롤 위치에 따라 최대 위아래 10pt 이동시킵니다.
- **계산:** [parallaxOffset](../../weashion/weashion/Views/EditorialStyle.swift#L185)는 스크롤 위치에 `-0.08`을 곱한 뒤 지정 범위로 제한합니다.
- **주의:** 시간 기반 반복 애니메이션이 아니라 스크롤 위치에 직접 연결됩니다. 마네킹과 조작 버튼까지 같은 modifier 안에 넣으면 의도하지 않은 움직임이 생길 수 있습니다.

<a id="snippet-21"></a>

## 21. 브랜드 소개 페이지의 전환

원본: [EditorialWelcomeView.swift / pageTransition](../../weashion/weashion/Views/EditorialWelcomeView.swift#L94)

```swift
private var pageTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
}
```

- **화면 효과:** 소개 페이지의 콘텐츠가 8pt 이동과 페이드로 교체됩니다. 동작 줄이기에서는 이동을 제외하고 페이드만 사용합니다.
- **반응형:** 같은 파일은 실제 폭 700pt 이상이면서 접근성 글씨가 아닐 때 좌우 배치를 사용합니다.
- **실제 진입 경로:** 현재 [FittingSettingsView의 fullScreenCover](../../weashion/weashion/Views/FittingSettingsView.swift#L82)로 열리는 'WEASHION 이야기'입니다. 최초 체형 생성 흐름은 별도의 [BodySetupView](../../weashion/weashion/Views/BodySetupView.swift)입니다.

<a id="snippet-22"></a>

## 22. 실행 스플래시와 본문 전환

원본: [weashionApp.swift / LaunchSplashContainer](../../weashion/weashion/weashionApp.swift#L22)

```swift
private struct LaunchSplashContainer: View {
    @State private var contentReady = false
    @State private var minimumDurationElapsed = false

    private var showsSplash: Bool { !contentReady || !minimumDurationElapsed }

    var body: some View {
        ZStack {
            ContentView {
                contentReady = true
            }
            .opacity(showsSplash ? 0 : 1)
            .allowsHitTesting(!showsSplash)
            .accessibilityHidden(showsSplash)

            if showsSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Could not finish the launch splash delay: \(error)")
                return
            }
            withAnimation(.easeOut(duration: 0.45)) {
                minimumDurationElapsed = true
            }
        }
    }
}
```

- **표시 조건:** 콘텐츠 준비와 최소 900ms 경과가 모두 충족되어야 스플래시가 사라집니다.
- **화면 효과:** 최소 시간 경과 상태는 0.45초 easeOut 애니메이션으로 변경합니다.
- **정확한 범위:** 콘텐츠가 900ms 이후 준비되는 경우의 상태 변경까지 이 `withAnimation`이 자동으로 감싸는 것은 아닙니다.
- **주의:** 현재 컨테이너는 공통 `EditorialMotion`이나 별도의 Reduce Motion 분기를 사용하지 않습니다. 앱의 모든 모션이 동일한 정책으로 구현되어 있다고 해석하지 않습니다.
- **시각 자산:** 실제 스플래시 구도와 이미지는 [LaunchSplashView](../../weashion/weashion/Views/LaunchSplashView.swift)를 함께 봅니다.

## 변경·검증 체크리스트

- opacity·offset·색 전환·숫자 교체·스크롤 연동 중 어느 종류인지 먼저 구분합니다.
- 공통 상수 변경과 개별 호출부의 delay·distance 변경을 나눠 영향 범위를 확인합니다.
- Reduce Motion·VoiceOver·접근성 글씨의 조건을 효과별로 확인합니다. 하나의 함수만으로 전체 적용을 가정하지 않습니다.
- 리빌 전 콘텐츠의 접근성 탐색과, 제목이 하나의 헤더로 읽히는 구조를 유지합니다.
- 버튼 기능이나 화면 준비 완료를 장식 애니메이션 종료에 종속시키지 않습니다.
- 일반 지면의 120ms 예고 임계값과 실행 스플래시의 최소 900ms를 같은 지연 정책으로 취급하지 않습니다.
- 새로 쓰는 효과가 현재 연결된 구현인지, 보유만 한 컴포넌트인지 확인합니다.

## 함께 보는 문서

- [버튼, 선택과 입력 컨트롤](./controls-and-input.md): CTA·선택 버튼·눌림·입력 포커스·오류 이동과 시스템 컨트롤의 외형·동작을 다룹니다.
- [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md): 실제 저장 결과, 오류 alert, 늦은 화면 준비 예고와 계산 중 진행선·블러·오버레이를 구분합니다.
- [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md): 이중선, 스튜디오 워터마크·빛 면·타원, 상품 컷아웃과 아카이브 그래픽을 다룹니다.
- [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md): 경계값 테스트, 전체 시각 타입·효과·형상 생성 경로와 미구현·미확인 요소를 한곳에서 찾습니다.
