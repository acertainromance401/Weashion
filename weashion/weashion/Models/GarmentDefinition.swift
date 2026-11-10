import Foundation
import simd

nonisolated struct GarmentDefinition: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let selectionLabel: String
    let pattern: GarmentPatternDescriptor
    let material: GarmentMaterial
    let appearance: GarmentAppearance

    var isValid: Bool {
        !id.isEmpty && !pattern.id.isEmpty && pattern.version > 0
            && (pattern.dimensions?.isValid ?? true)
            && (pattern.trouserDimensions?.isValid ?? true)
            && (pattern.footwearDimensions?.isValid ?? true)
            && [pattern.dimensions != nil, pattern.trouserDimensions != nil, pattern.footwearDimensions != nil]
                .filter { $0 }.count <= 1
            && (pattern.trouserDimensions == nil || (kind == .pants && pattern.anchor == .waist))
            && (pattern.footwearDimensions == nil || (kind == .shoes && pattern.anchor == .feet))
            && (pattern.dimensions == nil || [.shortSleeveTShirt, .longSleeveTop, .knitwear, .outerwear].contains(kind))
            && (pattern.fittingMode == nil || (pattern.dimensions != nil && pattern.meshResource != nil))
            && material.isValid && appearance.isValid
    }
}

nonisolated struct GarmentPatternDescriptor: Codable, Hashable, Sendable {
    enum Source: String, Codable, Hashable, Sendable {
        case mesh
    }

    enum FittingMode: String, Codable, Hashable, Sendable {
        case shapePreserving
    }

    let id: String
    let version: Int
    let source: Source
    let dimensions: SampleTShirtSpecification?
    let meshResource: String?
    let anchor: GarmentAnchor?
    var kind: GarmentKind? = nil
    var trouserDimensions: TrouserSpecification? = nil
    var footwearDimensions: FootwearSpecification? = nil
    var fittingMode: FittingMode? = nil
}

nonisolated enum GarmentAnchor: String, Codable, Hashable, Sendable {
    case shoulders
    case waist
    case feet
}

nonisolated struct SampleTShirtSpecification: Codable, Hashable, Sendable {
    let chestCircumference: Float
    var waistCircumference: Float? = nil
    var hipCircumference: Float? = nil
    let shoulderWidth: Float
    let length: Float
    let sleeveLength: Float
    let sleeveOpening: Float
    var armholeDepth: Float? = nil
    var sleeveWidthScale: Float? = nil

    var effectiveSleeveOpening: Float { sleeveOpening * (sleeveWidthScale ?? 1) }

    var isValid: Bool {
        (0.4...3).contains(chestCircumference) && (0.2...1).contains(shoulderWidth)
            && (0.2...1.8).contains(length) && (0.05...1).contains(sleeveLength)
            && (0.12...1.2).contains(sleeveOpening) && effectiveSleeveOpening * 0.64 < length
            && (0.4...3).contains(waistCircumference ?? chestCircumference)
            && (0.4...3).contains(hipCircumference ?? chestCircumference)
            && (armholeDepth.map { (0.10...0.45).contains($0) && $0 < length } ?? true)
            && (sleeveWidthScale.map { (0.5...1.5).contains($0) } ?? true)
    }
}

nonisolated struct GarmentMaterial: Codable, Hashable, Sendable {
    let maximumStrain: Float
    var fabric: GarmentFabricSettings? = nil

    var fabricSettings: GarmentFabricSettings { fabric ?? GarmentFabricSettings() }

    var isValid: Bool {
        maximumStrain.isFinite && maximumStrain > 0 && maximumStrain <= 1
    }
}

nonisolated struct GarmentFabricSettings: Codable, Hashable, Sendable {
    nonisolated enum Stretch: String, Codable, CaseIterable, Identifiable, Sendable {
        case unknown, none, minimal, regular, moderate, high

        var id: String { rawValue }
        var title: String {
            switch self {
            case .unknown: L("모름")
            case .none: L("없음")
            case .minimal: L("거의 없음")
            case .regular: L("보통")
            case .moderate: L("약간 있음")
            case .high: L("있음")
            }
        }
    }

    nonisolated enum Softness: String, Codable, CaseIterable, Identifiable, Sendable {
        case unknown, soft, regular, firm

        var id: String { rawValue }
        var title: String {
            switch self {
            case .unknown: L("모름")
            case .soft: L("부드러움")
            case .regular: L("보통")
            case .firm: L("뻣뻣함")
            }
        }
    }

    nonisolated enum Thickness: String, Codable, CaseIterable, Identifiable, Sendable {
        case unknown, thin, regular, thick

        var id: String { rawValue }
        var title: String {
            switch self {
            case .unknown: L("모름")
            case .thin: L("얇음")
            case .regular: L("보통")
            case .thick: L("두꺼움")
            }
        }
    }

    var stretch: Stretch = .unknown
    var softness: Softness = .unknown
    var thickness: Thickness = .unknown

    var estimatedMaximumExtension: Float {
        switch stretch {
        case .unknown: 0.08
        case .none: 0.015
        case .minimal: 0.04
        case .regular: 0.10
        case .moderate: 0.15
        case .high: 0.22
        }
    }

    var estimatedBendingCompliance: Float {
        let softnessFactor: Float = switch softness {
        case .unknown: 4
        case .soft: 9
        case .regular: 3
        case .firm: 0.5
        }
        let thicknessFactor: Float = switch thickness {
        case .unknown, .regular: 1
        case .thin: 1.6
        case .thick: 0.35
        }
        return softnessFactor * thicknessFactor
    }

    var estimatedSurfaceDensity: Float {
        switch thickness {
        case .unknown, .regular: 0.18
        case .thin: 0.12
        case .thick: 0.30
        }
    }
}

nonisolated struct GarmentAppearance: Codable, Hashable, Sendable {
    let color: SIMD3<Float>
    let trimColor: SIMD3<Float>
    let roughness: Float

    var isValid: Bool {
        [color.x, color.y, color.z, trimColor.x, trimColor.y, trimColor.z, roughness]
            .allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

nonisolated enum GarmentCatalog {
    static let samples: [GarmentDefinition] = {
        guard let url = Bundle.main.url(forResource: "garments", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let garments = try? JSONDecoder().decode([GarmentDefinition].self, from: data),
              Set(garments.map(\.id)).count == garments.count,
              garments.allSatisfy(\.isValid) else { return [] }
        return garments
    }()
}