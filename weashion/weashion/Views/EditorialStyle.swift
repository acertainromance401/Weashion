import SwiftUI

enum Editorial {
    static let paper = Color(red: 250 / 255, green: 249 / 255, blue: 246 / 255)
    static let ink = Color(red: 32 / 255, green: 43 / 255, blue: 48 / 255)
    static let muted = Color(red: 98 / 255, green: 107 / 255, blue: 103 / 255)
    static let accent = Color(red: 159 / 255, green: 53 / 255, blue: 72 / 255)
    static let warning = Color(red: 121 / 255, green: 81 / 255, blue: 23 / 255)
    static let error = Color(red: 166 / 255, green: 41 / 255, blue: 32 / 255)
    static let rule = ink.opacity(0.18)
    static let stock = Color(red: 234 / 255, green: 231 / 255, blue: 224 / 255)
    static let studio = Color(red: 236 / 255, green: 237 / 255, blue: 234 / 255)

    /// Latin display face. Bodoni Moda with the optical size following the point size.
    static func serif(_ size: CGFloat, italic: Bool = false, weight: CGFloat = 400) -> Font {
        EditorialFonts.display(size: size, weight: weight, italic: italic)
    }

    /// Phrase headlines ("Every size, a note.") are set in New York, the system serif, so the
    /// hairline Bodoni is reserved for the masthead, numerals and size letters.
    static func headline(_ size: CGFloat, italic: Bool = true) -> Font {
        let font = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? font.italic() : font
    }

    /// Heavy grotesk statement (Pretendard Black behind Helvetica Neue Bold) for the one loud
    /// Korean line a spread is allowed, in the manner of magazine feature openers.
    static func statement(_ size: CGFloat) -> Font {
        Font(EditorialFonts.sansUIFont(size: size, weight: .black) as CTFont)
    }

    /// Korean display face. Nanum Myeongjo scaled with Dynamic Type.
    static func hangul(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .title) -> Font {
        EditorialFonts.hangul(size: size, bold: bold, relativeTo: style)
    }

}

/// Functional text: Helvetica Neue for Latin and digits with Pretendard behind it for Hangul,
/// scaled with Dynamic Type like the system text styles it replaces.
private struct EditorialSansText: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(EditorialFonts.sans(style, weight: weight, dynamicTypeSize: dynamicTypeSize))
    }
}

struct EditorialTransitionPreview: View {
    let number: String
    let title: String
    let extended: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number).font(Editorial.serif(21, italic: true)).foregroundStyle(Editorial.accent)
                EditorialEyebrow(text: title)
            }
            if extended {
                Text("화면을 준비하고 있어요").editorialSans(.caption).foregroundStyle(Editorial.muted)
            }
            EditorialPendingRule(reduceMotion: reduceMotion).frame(height: 1.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.paper)
        .overlay(alignment: .top) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pendingPagePreview")
    }
}

private struct EditorialPendingRule: UIViewRepresentable {
    let reduceMotion: Bool

    func makeUIView(context: Context) -> RuleView { RuleView() }

    func updateUIView(_ view: RuleView, context: Context) {
        view.reduceMotion = reduceMotion
    }

    final class RuleView: UIView {
        private let stroke = CALayer()
        var reduceMotion = false {
            didSet { if reduceMotion != oldValue { updateAnimation() } }
        }
        private var laidOutSize = CGSize.zero

        init() {
            super.init(frame: .zero)
            clipsToBounds = true
            stroke.backgroundColor = UIColor(Editorial.accent).cgColor
            layer.addSublayer(stroke)
        }

        required init?(coder: NSCoder) { super.init(coder: coder) }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard laidOutSize != bounds.size else { return }
            laidOutSize = bounds.size
            updateAnimation()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateAnimation()
        }

        private func updateAnimation() {
            stroke.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stroke.frame = CGRect(x: 0, y: 0, width: reduceMotion ? 24 : bounds.width * 0.25, height: bounds.height)
            CATransaction.commit()
            guard !reduceMotion, window != nil, bounds.width > 0 else { return }
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = -stroke.bounds.width / 2
            animation.toValue = bounds.width + stroke.bounds.width / 2
            animation.duration = 0.75
            animation.repeatCount = .infinity
            stroke.add(animation, forKey: "pending")
        }
    }
}

extension View {
    func editorialSans(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> some View {
        modifier(EditorialSansText(style: style, weight: weight))
    }
}

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

enum EditorialMotion {
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

    static func offset(from edge: Edge, distance: CGFloat, revealed: Bool) -> CGSize {
        guard !revealed else { return .zero }
        switch edge {
        case .top: return CGSize(width: 0, height: -distance)
        case .bottom: return CGSize(width: 0, height: distance)
        case .leading: return CGSize(width: -distance, height: 0)
        case .trailing: return CGSize(width: distance, height: 0)
        }
    }

    static func parallaxOffset(minY: CGFloat, limit: CGFloat) -> CGFloat {
        guard minY.isFinite else { return 0 }
        return min(limit, max(-limit, -minY * 0.08))
    }

    /// Long, decelerating editorial curve shared by titles, rules, reveals and page entries.
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
}

struct EditorialFeedbackTrigger: Equatable {
    enum Kind: Equatable { case selection, success }

    let saveRevision: Int
    let selection: [String?]

    func kind(since previous: Self) -> Kind? {
        if saveRevision != previous.saveRevision { return .success }
        return selection != previous.selection ? .selection : nil
    }
}

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

struct EditorialPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: EditorialLayout.minimumControlSize, minHeight: EditorialLayout.minimumControlSize)
            .modifier(EditorialPressFeedback(isPressed: configuration.isPressed, scalesOnPress: true))
            .contentShape(Rectangle())
    }
}

struct EditorialChoiceStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
}

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

extension View {
    func editorialReveal(delay: Double = 0, from: Edge = .bottom, distance: CGFloat = EditorialMotion.revealOffset) -> some View {
        modifier(EditorialReveal(delay: delay, distance: distance, from: from))
    }

    func editorialEntrance(delay: Double = 0, from: Edge = .bottom,
                          distance: CGFloat = EditorialMotion.revealOffset, enabled: Bool = true) -> some View {
        modifier(EditorialReveal(delay: delay, distance: distance, from: from,
                                 onScroll: false, masked: true, enabled: enabled, duration: EditorialMotion.entranceDuration))
    }
}

struct EditorialHeading: View {
    let number: String
    let title: String
    let subtitle: String
    var hangul = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var scale: CGFloat = 1

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 18))
        VStack(alignment: .leading, spacing: 14) {
            EditorialRule(animates: true)
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(hangul ? Editorial.hangul(24, relativeTo: .title2) : Editorial.headline(28 * scale))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .editorialSans(.caption)
                        .foregroundStyle(Editorial.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("N° \(number)")
                    .font(Editorial.serif(13 * scale, italic: true))
                    .foregroundStyle(Editorial.accent)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct EditorialRule: View {
    var animates = false
    var double = true
    var color = Editorial.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        VStack(spacing: 3) {
            Rectangle().fill(color).frame(height: 1)
            if double { Rectangle().fill(color.opacity(0.25)).frame(height: 0.5) }
        }
        .scaleEffect(x: animates && !reduceMotion && !drawn ? 0 : 1, y: 1, anchor: .leading)
        .onAppear {
            guard animates else { return }
            withAnimation(reduceMotion ? nil : EditorialMotion.editorial(EditorialMotion.ruleDuration).delay(0.2)) {
                drawn = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// `display` keeps Bodoni for graphic words; `displayItalic` is the New York phrase headline.
enum EditorialTitleStyle {
    case display, displayItalic, hangul, statement
}

struct EditorialPageTitle: View {
    let number: String
    let section: String
    let title: String
    let subtitle: String
    var animated = true
    var compact = false
    var style = EditorialTitleStyle.displayItalic
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 20) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                HStack(spacing: 8) {
                    Rectangle().fill(Editorial.accent).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    EditorialEyebrow(text: section)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("N° \(number)")
                        .font(Editorial.serif(20, italic: true))
                        .foregroundStyle(Editorial.accent)
                        .accessibilityHidden(true)
                        .editorialEntrance(from: .trailing, enabled: animated)
                }
            }
            EditorialTitle(text: title, animated: animated, pointSize: compact ? 34 : 48, style: style)
                .frame(maxWidth: .infinity, alignment: .leading)
            EditorialRule(animates: animated)
            Text(subtitle)
                .editorialSans(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(Editorial.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditorialFigureCaption: View {
    let number: String
    let text: String
    var alignment = HorizontalAlignment.leading
    var numberColor = Editorial.accent
    var textColor = Editorial.muted

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("FIG. \(number)")
                .font(Editorial.serif(11, italic: true))
                .foregroundStyle(numberColor)
            Text(text)
                .editorialSans(.caption2)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

struct EditorialEyebrow: View {
    let text: String
    var color = Editorial.muted

    var body: some View {
        Text(text)
            .editorialSans(.caption2, weight: .medium)
            .tracking(1.5)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Vertical running head placed along a page edge, as on a magazine spread.
struct EditorialRunningHead: View {
    let text: String
    var color = Editorial.muted
    var font: Font? = nil
    var tracking: CGFloat = 3
    /// Width of the vertical column the rotated line occupies (its line height).
    var thickness: CGFloat = 16

    /// Rotated around its top-leading corner so the line hangs downward from wherever it is placed.
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
}

/// Oversized display glyphs (a size letter, a temperature) used as graphic elements.
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

struct EditorialTitle: View {
    let text: String
    var animated = true
    var pointSize: CGFloat = 44
    var style = EditorialTitleStyle.displayItalic
    var color = Editorial.ink
    var alignment = HorizontalAlignment.leading
    var revealsOnScroll = false
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesMotion: Bool {
        animated && EditorialMotion.allowsTitleMotion(reduceMotion: reduceMotion, voiceOver: voiceOver,
                                                       accessibility: dynamicTypeSize.isAccessibilitySize)
    }

    private var scaledSize: CGFloat {
        switch style {
        case .hangul: pointSize
        case .statement: pointSize * min(typeScale, 1.2)
        default: pointSize * min(typeScale, 1.4)
        }
    }

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

    private var titleFont: Font {
        switch style {
        case .display: Editorial.serif(scaledSize)
        case .displayItalic: Editorial.headline(scaledSize)
        case .hangul: Editorial.hangul(pointSize, relativeTo: .largeTitle)
        case .statement: Editorial.statement(pointSize * min(typeScale, 1.2))
        }
    }
}

struct EditorialStudioBackdrop: View {
    var mark = "W"

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Editorial.studio
                Rectangle()
                    .fill(LinearGradient(colors: [Editorial.paper.opacity(0.7), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: geometry.size.width * 0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(mark)
                    .font(Editorial.serif(min(geometry.size.width * 0.95, 420), italic: true))
                    .foregroundStyle(Editorial.ink.opacity(0.045))
                    .offset(x: -geometry.size.width * 0.12, y: -geometry.size.height * 0.14)
                VStack {
                    Spacer()
                    Ellipse()
                        .fill(Editorial.ink.opacity(0.05))
                        .frame(width: geometry.size.width * 0.55, height: 18)
                        .blur(radius: 12)
                        .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity)
                Canvas { context, size in
                    var corners = Path()
                    for point in [CGPoint(x: 16, y: 16), CGPoint(x: size.width - 16, y: 16),
                                  CGPoint(x: 16, y: size.height - 16), CGPoint(x: size.width - 16, y: size.height - 16)] {
                        let dx: CGFloat = point.x < size.width / 2 ? 14 : -14
                        let dy: CGFloat = point.y < size.height / 2 ? 14 : -14
                        corners.move(to: CGPoint(x: point.x + dx, y: point.y))
                        corners.addLine(to: point)
                        corners.addLine(to: CGPoint(x: point.x, y: point.y + dy))
                    }
                    context.stroke(corners, with: .color(Editorial.ink.opacity(0.3)), lineWidth: 0.5)
                    var accent = Path()
                    accent.move(to: CGPoint(x: 16, y: 30))
                    accent.addLine(to: CGPoint(x: 16, y: 16))
                    accent.addLine(to: CGPoint(x: 44, y: 16))
                    context.stroke(accent, with: .color(Editorial.accent), lineWidth: 2)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EditorialActionLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).editorialSans(.headline, weight: .semibold)
                Text(subtitle)
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right").font(.system(size: 20, weight: .light))
        }
        .padding(.vertical, 22)
        .frame(minHeight: 68)
        .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

struct EditorialStatusMessage: View {
    @Binding var message: String?
    var horizontalInset: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Editorial.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("기록을 저장했어요").editorialSans(.caption, weight: .semibold)
                        Text(message).editorialSans(.caption2).foregroundStyle(Editorial.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { self.message = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("저장 안내 닫기")
                }
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("savedFeedback")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, horizontalInset)
        .background(Editorial.paper)
        .animation(EditorialMotion.feedback(reduceMotion: reduceMotion), value: message)
    }
}

enum EditorialNoticeTone: Equatable {
    case information, progress, success, warning, error

    var color: Color {
        switch self {
        case .warning: Editorial.warning
        case .error: Editorial.error
        case .success: Editorial.accent
        default: Editorial.ink
        }
    }

    /// Italic lead-in that carries the meaning in type, the way a magazine footnote opens.
    var leadIn: String {
        switch self {
        case .information: "Note"
        case .progress: "In progress"
        case .success: "Saved"
        case .warning: "Attention"
        case .error: "Error"
        }
    }

    var spokenWord: String {
        switch self {
        case .information: L("안내")
        case .progress: L("진행 중")
        case .success: L("저장 완료")
        case .warning: L("주의")
        case .error: L("오류")
        }
    }
}

/// Footnote-style status: one hairline, an italic lead-in running straight into the sentence,
/// and an optional caption beneath. No icon, no side bar, no tinted box.
struct EditorialNotice: View {
    let title: String
    var detail: String?
    var tone = EditorialNoticeTone.information
    var rule = Edge.Set.top
    var onDismiss: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rule.contains(.top) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if tone == .progress {
                    ProgressView().controlSize(.mini).tint(Editorial.ink)
                        .accessibilityHidden(true)
                }
                (Text("\(tone.leadIn) — ").font(Editorial.serif(18, italic: true)).foregroundStyle(tone.color)
                 + Text(title).font(EditorialFonts.sans(.subheadline, dynamicTypeSize: dynamicTypeSize)).foregroundStyle(Editorial.ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(tone.spokenWord). \(title)")
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .editorialSans(.caption, weight: .medium)
                            .frame(width: EditorialLayout.minimumControlSize, height: EditorialLayout.minimumControlSize)
                    }
                    .accessibilityLabel("저장 안내 닫기")
                }
            }
            if let detail {
                Text(detail)
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rule.contains(.bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// Inline navigation title set in the editorial faces instead of the system bold title.
private struct EditorialNavigationTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(title.unicodeScalars.allSatisfy(\.isASCII) ? Editorial.serif(17) : Editorial.hangul(17, relativeTo: .headline))
                        .tracking(title.unicodeScalars.allSatisfy(\.isASCII) ? 3 : 0)
                        .foregroundStyle(Editorial.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .toolbarBackground(Editorial.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct EditorialInputSurface: ViewModifier {
    let focused: Bool
    let invalid: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Editorial.stock.opacity(0.4))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(invalid ? Editorial.error : focused ? Editorial.accent : Editorial.rule)
                    .frame(height: focused || invalid ? 1.5 : 0.5)
                    .animation(EditorialMotion.feedback(reduceMotion: reduceMotion), value: focused)
                    .animation(EditorialMotion.feedback(reduceMotion: reduceMotion), value: invalid)
            }
    }
}

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

/// Text button for navigation toolbars. Measures in the system font and never wraps,
/// so Japanese labels such as 閉じる stay on one line inside the toolbar capsule.
struct EditorialToolbarButton: View {
    private let title: LocalizedStringKey
    private let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

extension View {
    func editorialNavigationTitle(_ title: String) -> some View {
        modifier(EditorialNavigationTitle(title: title))
    }

    func editorialSaveFeedback(_ message: Binding<String?>, horizontalInset: CGFloat = 24) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            EditorialStatusMessage(message: message, horizontalInset: horizontalInset)
        }
    }

    func editorialInput(focused: Bool, invalid: Bool = false) -> some View {
        modifier(EditorialInputSurface(focused: focused, invalid: invalid))
    }

    func editorialError(_ message: Binding<String?>) -> some View {
        alert(L("확인이 필요해요"), isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("확인") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
        .sensoryFeedback(trigger: message.wrappedValue) { _, value in
            value == nil ? nil : .error
        }
    }
}

struct GarmentIllustration: View {
    var tint: Color = Color(red: 0.45, green: 0.49, blue: 0.45)

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let shirt = Path { path in
                path.move(to: CGPoint(x: w * 0.35, y: h * 0.12))
                path.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.12),
                                  control: CGPoint(x: w * 0.5, y: h * 0.28))
                for point in [
                    CGPoint(x: w * 0.79, y: h * 0.19), CGPoint(x: w * 0.96, y: h * 0.42),
                    CGPoint(x: w * 0.78, y: h * 0.53), CGPoint(x: w * 0.71, y: h * 0.43),
                    CGPoint(x: w * 0.73, y: h * 0.91), CGPoint(x: w * 0.27, y: h * 0.91),
                    CGPoint(x: w * 0.29, y: h * 0.43), CGPoint(x: w * 0.22, y: h * 0.53),
                    CGPoint(x: w * 0.04, y: h * 0.42), CGPoint(x: w * 0.21, y: h * 0.19)
                ] { path.addLine(to: point) }
                path.closeSubpath()
            }
            shirt.fill(LinearGradient(colors: [
                tint.opacity(0.65), tint
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            shirt.stroke(Editorial.ink.opacity(0.35), lineWidth: 0.8)
            Path { path in
                path.move(to: CGPoint(x: w * 0.35, y: h * 0.12))
                path.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.12),
                                  control: CGPoint(x: w * 0.5, y: h * 0.36))
                path.move(to: CGPoint(x: w * 0.29, y: h * 0.87))
                path.addLine(to: CGPoint(x: w * 0.71, y: h * 0.87))
            }
            .stroke(.white.opacity(0.3), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
