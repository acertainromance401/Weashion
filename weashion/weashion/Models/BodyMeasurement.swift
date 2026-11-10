import Foundation

enum BodyMeasurement: String, CaseIterable, Codable, Identifiable {
    case height, weight, shoulderWidth, chest, waist, hip, legLength, armSize, legSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .height: L("키")
        case .weight: L("몸무게")
        case .shoulderWidth: L("어깨너비")
        case .chest: L("가슴둘레")
        case .waist: L("허리둘레")
        case .hip: L("엉덩이둘레")
        case .legLength: L("인심")
        case .armSize: L("팔 굵기 배율")
        case .legSize: L("다리 굵기 배율")
        }
    }

    var keyPath: WritableKeyPath<UserBody, Double> {
        switch self {
        case .height: \UserBody.height
        case .weight: \UserBody.weight
        case .shoulderWidth: \UserBody.shoulderWidth
        case .chest: \UserBody.chest
        case .waist: \UserBody.waist
        case .hip: \UserBody.hip
        case .legLength: \UserBody.legLength
        case .armSize: \UserBody.armSize
        case .legSize: \UserBody.legSize
        }
    }

    func range(for base: MannequinBase) -> ClosedRange<Double> {
        switch self {
        case .height: (base == .female ? 140 : 150)...200
        case .weight: (base == .female ? 35 : 45)...100
        case .shoulderWidth: (base == .female ? 25 : 35)...60
        case .chest, .hip: (base == .female ? 30 : 75)...120
        case .waist: (base == .female ? 30 : 60)...105
        case .legLength: (base == .female ? 45 : 65)...95
        case .armSize, .legSize: (base == .female ? 0.5 : 0.7)...1.3
        }
    }

    var isPhysical: Bool { self != .armSize && self != .legSize }
    var unit: String { isPhysical ? (self == .weight ? "kg" : "cm") : L("배") }
    var step: Double { isPhysical ? 0.1 : 0.01 }
    var fractionDigits: Int { isPhysical ? 1 : 2 }

    func formatted(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(fractionDigits)).grouping(.never))
    }
}