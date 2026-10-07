import Foundation

enum BodyMeasurement: String, CaseIterable, Codable, Identifiable {
    case height, weight, shoulderWidth, chest, waist, hip, legLength, armSize, legSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .height: "키"
        case .weight: "몸무게"
        case .shoulderWidth: "어깨너비"
        case .chest: "가슴둘레"
        case .waist: "허리둘레"
        case .hip: "엉덩이둘레"
        case .legLength: "인심"
        case .armSize: "팔 굵기 배율"
        case .legSize: "다리 굵기 배율"
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

    var range: ClosedRange<Double> {
        switch self {
        case .height: 150...200
        case .weight: 45...100
        case .shoulderWidth: 35...60
        case .chest, .hip: 75...120
        case .waist: 60...105
        case .legLength: 65...95
        case .armSize, .legSize: 0.7...1.3
        }
    }

    var isPhysical: Bool { self != .armSize && self != .legSize }
    var unit: String { isPhysical ? (self == .weight ? "kg" : "cm") : "배" }
    var step: Double { isPhysical ? 0.1 : 0.01 }
    var fractionDigits: Int { isPhysical ? 1 : 2 }

    func formatted(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(fractionDigits)).grouping(.never))
    }
}