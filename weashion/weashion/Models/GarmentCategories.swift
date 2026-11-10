import Foundation
import simd

nonisolated struct TrouserSpecification: Codable, Hashable, Sendable {
    let waistCircumference: Float
    let hipCircumference: Float
    let rise: Float
    let inseam: Float
    let thighCircumference: Float
    let hemCircumference: Float
    var legWidthScale: Float? = nil
    var totalLength: Float { rise + inseam }
    var effectiveThighCircumference: Float { thighCircumference * (legWidthScale ?? 1) }
    var effectiveHemCircumference: Float { hemCircumference * (legWidthScale ?? 1) }

    var isValid: Bool {
        (0.4...2).contains(waistCircumference) && (0.5...2.4).contains(hipCircumference)
            && (0.12...0.5).contains(rise) && (0.3...1.2).contains(inseam)
            && (0.25...1.2).contains(thighCircumference) && (0.15...0.9).contains(hemCircumference)
            && (legWidthScale.map { (0.5...1.5).contains($0) } ?? true)
    }
}

nonisolated struct FootwearSpecification: Codable, Hashable, Sendable {
    let length: Float
    let width: Float

    var isValid: Bool { (0.15...0.4).contains(length) && (0.05...0.18).contains(width) }
}

nonisolated struct TrouserSizeInput: Codable, Hashable, Sendable {
    var waistWidth: Double
    var hipWidth: Double
    var rise: Double
    var inseam: Double
    var thighWidth: Double
    var hemWidth: Double
    var fabric: GarmentFabricSettings? = nil
    var legWidthPercent: Double? = nil

    var totalLength: Double {
        get { rise + inseam }
        set { inseam = newValue - rise }
    }
    var totalLengthRange: ClosedRange<Double> { (rise + 30)...(rise + 120) }

    var specification: TrouserSpecification {
        .init(waistCircumference: Float(waistWidth / 50), hipCircumference: Float(hipWidth / 50),
              rise: Float(rise / 100), inseam: Float(inseam / 100),
              thighCircumference: Float(thighWidth / 50), hemCircumference: Float(hemWidth / 50),
              legWidthScale: legWidthPercent.map { Float($0 / 100) })
    }

    var isValid: Bool { specification.isValid }

    init(waistWidth: Double = 41, hipWidth: Double = 51, rise: Double = 28, inseam: Double = 76,
         thighWidth: Double = 30, hemWidth: Double = 19, fabric: GarmentFabricSettings? = nil,
         legWidthPercent: Double? = nil) {
        self.waistWidth = waistWidth
        self.hipWidth = hipWidth
        self.rise = rise
        self.inseam = inseam
        self.thighWidth = thighWidth
        self.hemWidth = hemWidth
        self.fabric = fabric
        self.legWidthPercent = legWidthPercent
    }

    init(dimensions: TrouserSpecification) {
        self.init(waistWidth: Double(dimensions.waistCircumference) * 50,
                  hipWidth: Double(dimensions.hipCircumference) * 50,
                  rise: Double(dimensions.rise) * 100, inseam: Double(dimensions.inseam) * 100,
                  thighWidth: Double(dimensions.thighCircumference) * 50,
                  hemWidth: Double(dimensions.hemCircumference) * 50,
                  legWidthPercent: dimensions.legWidthScale.map { Double(($0 * 1000).rounded()) / 10 })
    }
}

nonisolated struct FootwearSizeInput: Codable, Hashable, Sendable {
    var length: Double
    var width: Double

    var specification: FootwearSpecification { .init(length: Float(length / 1000), width: Float(width / 1000)) }
    var isValid: Bool { specification.isValid }

    init(length: Double = 270, width: Double = 105) {
        self.length = length
        self.width = width
    }

    init(dimensions: FootwearSpecification) {
        self.init(length: Double(dimensions.length) * 1000, width: Double(dimensions.width) * 1000)
    }
}

nonisolated struct TrouserBinding: Codable, Sendable {
    let reference: TrouserSpecification
    let rightLegCenters: [SIMD3<Float>]
    let legWeights: [Float]

    func isValid(vertexCount: Int) -> Bool {
        reference.isValid && rightLegCenters.count >= 2
            && rightLegCenters.allSatisfy { $0.x.isFinite && $0.x > 0 && $0.y.isFinite && $0.z.isFinite }
            && zip(rightLegCenters, rightLegCenters.dropFirst()).allSatisfy { $0.y < $1.y }
            && legWeights.count == vertexCount && legWeights.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

nonisolated struct FootwearBinding: Codable, Sendable {
    let reference: FootwearSpecification
    let rightCenter: SIMD3<Float>
    let leftCenter: SIMD3<Float>
    let sides: [Int]
    let soleThickness: Float

    func isValid(vertexCount: Int) -> Bool {
        reference.isValid && (0.005...0.10).contains(soleThickness) && [rightCenter, leftCenter].allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        } && rightCenter.x > leftCenter.x && sides.count == vertexCount
            && Set(sides) == Set([-1, 1])
    }
}

nonisolated struct GarmentFootBounds: Sendable {
    let center: SIMD3<Float>
    let length: Float
    let width: Float
    let floor: Float
    var forward = SIMD3<Float>(0, 0, 1)

    func translated(by offset: SIMD3<Float>) -> Self {
        .init(center: center + offset, length: length, width: width, floor: floor + offset.y, forward: forward)
    }
}

extension GarmentDefinition {
    nonisolated var kind: GarmentKind { pattern.kind ?? .shortSleeveTShirt }
    nonisolated var measurements: GarmentMeasurements? {
        if let dimensions = pattern.trouserDimensions { return .trousers(.init(dimensions: dimensions)) }
        if let dimensions = pattern.footwearDimensions { return .footwear(.init(dimensions: dimensions)) }
        return pattern.dimensions.map { .shortSleeve(.init(dimensions: $0)) }
    }
}
