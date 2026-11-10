import SwiftUI
import CoreText
import UIKit

/// Bundled OFL typefaces: Bodoni Moda (variable, opsz/wght) for Latin display type and
/// Nanum Myeongjo for Korean display type. Both fall back to the system serif when the
/// bundle registration fails so screens never lose their text.
enum EditorialFonts {
    static let displayName = "BodoniModa-Regular"
    static let displayItalicName = "BodoniModa-Italic"
    static let hangulName = "NanumMyeongjo"
    static let hangulBoldName = "NanumMyeongjoBold"
    /// Pretendard (OFL, variable wght 45–930) draws Hangul behind the Latin grotesk.
    static let sansName = "PretendardVariable-Regular"
    static let latinSansFamily = "Helvetica Neue"
    static let opticalSizeRange: ClosedRange<CGFloat> = 6...96
    static let weightRange: ClosedRange<CGFloat> = 400...900

    private static let opticalSizeTag: UInt32 = 0x6F70_737A
    private static let weightTag: UInt32 = 0x7767_6874

    private static let registration: Bool = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return [displayName, displayItalicName, hangulName].allSatisfy { UIFont(name: $0, size: 12) != nil }
    }()

    static var isAvailable: Bool { registration }
    static var sansIsAvailable: Bool { registration && UIFont(name: sansName, size: 12) != nil }

    @discardableResult
    static func register() -> Bool { registration }

    static func opticalSize(for pointSize: CGFloat) -> CGFloat {
        min(max(pointSize, opticalSizeRange.lowerBound), opticalSizeRange.upperBound)
    }

    static func display(size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font {
        guard registration else {
            let font = Font.system(size: size, weight: weight >= 600 ? .semibold : .regular, design: .serif)
            return italic ? font.italic() : font
        }
        let clampedWeight = min(max(weight, weightRange.lowerBound), weightRange.upperBound)
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: opticalSizeTag): NSNumber(value: Double(opticalSize(for: size))),
            NSNumber(value: weightTag): NSNumber(value: Double(clampedWeight))
        ]
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: italic ? displayItalicName : displayName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation
        ])
        return Font(UIFont(descriptor: descriptor, size: size) as CTFont)
    }

    static func hangul(size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .title) -> Font {
        guard registration else { return .system(size: size, weight: bold ? .semibold : .regular, design: .serif) }
        let name = bold && UIFont(name: hangulBoldName, size: 12) != nil ? hangulBoldName : hangulName
        return .custom(name, size: size, relativeTo: style)
    }

    // MARK: - Functional sans: Helvetica Neue for Latin and digits, Pretendard for Hangul

    static func latinSansName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight: "HelveticaNeue-UltraLight"
        case .thin: "HelveticaNeue-Thin"
        case .light: "HelveticaNeue-Light"
        case .medium: "HelveticaNeue-Medium"
        case .semibold, .bold, .heavy, .black: "HelveticaNeue-Bold"
        default: "HelveticaNeue"
        }
    }

    static func sansWeightValue(for weight: Font.Weight) -> Double {
        switch weight {
        case .thin: 100
        case .ultraLight: 200
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

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

    static func sansUIFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        UIFont(descriptor: sansDescriptor(weight: weight), size: size)
    }

    /// Point size a text style resolves to for a given Dynamic Type size, without needing a view.
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
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
