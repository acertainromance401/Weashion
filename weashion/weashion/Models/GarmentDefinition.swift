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
            && material.isValid && appearance.isValid
    }
}

nonisolated struct GarmentPatternDescriptor: Codable, Hashable, Sendable {
    enum Source: String, Codable, Hashable, Sendable {
        case cottonTShirt
        case mesh
    }

    let id: String
    let version: Int
    let source: Source
    let dimensions: SampleTShirtSpecification?
    let meshResource: String?
    let anchor: GarmentAnchor?
}

nonisolated enum GarmentAnchor: String, Codable, Hashable, Sendable {
    case shoulders
    case waist
}

nonisolated struct SampleTShirtSpecification: Codable, Hashable, Sendable {
    let chestCircumference: Float
    var waistCircumference: Float? = nil
    var hipCircumference: Float? = nil
    let shoulderWidth: Float
    let length: Float
    let sleeveLength: Float
    let sleeveOpening: Float

    var isValid: Bool {
        (0.4...3).contains(chestCircumference) && (0.2...1).contains(shoulderWidth)
            && (0.2...1.8).contains(length) && (0.05...1).contains(sleeveLength)
            && (0.12...1.2).contains(sleeveOpening) && sleeveOpening * 0.64 < length
            && (0.4...3).contains(waistCircumference ?? chestCircumference)
            && (0.4...3).contains(hipCircumference ?? chestCircumference)
    }
}

nonisolated struct GarmentMaterial: Codable, Hashable, Sendable {
    let maximumStrain: Float

    var isValid: Bool {
        maximumStrain.isFinite && maximumStrain > 0 && maximumStrain <= 1
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