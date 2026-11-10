import Foundation
import simd

nonisolated struct GarmentSizeLabelCalibration {
    let length: Double
    let shoulder: Double
    let chest: Double
    let sleeve: Double
    let sleeveWidth: Double

    init(templateID: String) {
        let hoodie = templateID == "meshy-hoodie"
        length = hoodie ? 70.0 / 65 : 1
        shoulder = hoodie ? 52.0 / 58 : 1
        chest = hoodie ? 58.0 / 56 : 1
        sleeve = hoodie ? 60.0 / 50 : 1
        sleeveWidth = hoodie ? 100.0 / 80 : 1
    }

    func displayed(_ input: GarmentSizeInput) -> GarmentSizeInput {
        var result = input
        result.length *= length
        result.shoulderWidth *= shoulder
        result.chestWidth *= chest
        result.sleeveLength *= sleeve
        if sleeveWidth != 1 {
            result.sleeveWidthPercent = (input.sleeveWidthPercent ?? 100) * sleeveWidth
        }
        return result
    }
}

nonisolated struct GarmentSizing: Codable, Sendable {
    let reference: SampleTShirtSpecification
    let rightShoulder: SIMD3<Float>
    let rightCuff: SIMD3<Float>

    var isValid: Bool {
        reference.isValid && [rightShoulder, rightCuff].allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        } && simd_distance(rightShoulder, rightCuff) > 0.01
    }

    func resized(_ asset: GarmentMeshAsset, to target: SampleTShirtSpecification,
                 preservingNeckShape: Bool = false) -> GarmentMeshAsset? {
        guard target.isValid, let fitting = asset.fitting else { return nil }
        let width = target.chestCircumference / reference.chestCircumference
        let shoulder = target.shoulderWidth / reference.shoulderWidth
        let bottom = asset.vertices.map(\.y).min() ?? -reference.length
        // A hood sits above the neck and is not part of the torso's measured length.
        let top = bottom + reference.length
        let length = target.length / reference.length
        let opening = target.sleeveOpening / reference.sleeveOpening
        let sleeveWidth = (target.sleeveWidthScale ?? 1) / (reference.sleeveWidthScale ?? 1)
        let axis = simd_normalize(rightCuff - rightShoulder)
        func trimCenter(_ trim: GarmentTrim) -> SIMD3<Float> {
            trim.vertices.reduce(SIMD3<Float>.zero) { $0 + asset.vertices[$1] } / Float(trim.vertices.count)
        }
        guard let cuff = asset.trims.min(by: {
            simd_distance_squared(trimCenter($0), rightCuff) < simd_distance_squared(trimCenter($1), rightCuff)
        }), let outer = cuff.vertices.max(by: { asset.vertices[$0].y < asset.vertices[$1].y }) else { return nil }
        let outerOffset = asset.vertices[outer] - rightShoulder
        let axialLength = simd_dot(outerOffset, axis)
        let radial = outerOffset - axis * axialLength
        let cuffScale = opening * sleeveWidth
        let axialSquared = target.sleeveLength * target.sleeveLength - simd_length_squared(radial) * cuffScale * cuffScale
        guard axialSquared > 0, abs(axialLength) > 0.001 else { return nil }
        let longSleeve = asset.sleeves != nil || reference.sleeveLength > 0.35
        let sleeve = longSleeve ? target.sleeveLength / reference.sleeveLength
            : sqrt(axialSquared) / abs(axialLength)
        let newShoulder = SIMD3<Float>(rightShoulder.x * shoulder, rightShoulder.y - top, rightShoulder.z)
        let newCuff = newShoulder + (rightCuff - rightShoulder) * sleeve
        let chestHeight = target.armholeDepth.map { newShoulder.y - $0 }
            ?? ((fitting.chest.center.y - top) * length)
        guard chestHeight > -target.length + 0.01, chestHeight < newShoulder.y else { return nil }

        func height(_ value: Float) -> Float {
            if value <= fitting.chest.center.y {
                let progress = (value - bottom) / max(fitting.chest.center.y - bottom, 0.01)
                return -target.length + progress * (chestHeight + target.length)
            }
            if value <= rightShoulder.y {
                let progress = (value - fitting.chest.center.y) / max(rightShoulder.y - fitting.chest.center.y, 0.01)
                return chestHeight + progress * (newShoulder.y - chestHeight)
            }
            return value - top
        }

        func torso(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let upper = GarmentFitProfile.smoothBlend((point.y - fitting.chest.center.y) /
                max(rightShoulder.y - fitting.chest.center.y, 0.01))
            let lowerWidth = (target.hipCircumference ?? target.chestCircumference) /
                (reference.hipCircumference ?? reference.chestCircumference)
            let hem = GarmentFitProfile.smoothBlend((fitting.waist.center.y - point.y) /
                max(fitting.waist.center.y - fitting.hip.center.y, 0.01))
            let bodyWidth = width + (lowerWidth - width) * hem
            var horizontal = bodyWidth + (shoulder - bodyWidth) * upper
            // Neck openings barely change between sizes, so only the shoulder line follows the shoulder width.
            let neckRadius = abs(rightShoulder.x) * 0.45
            if abs(point.x) < neckRadius {
                horizontal += (1 - horizontal) * upper * (1 - abs(point.x) / neckRadius)
            }
            let scaled = SIMD3<Float>(point.x * horizontal, height(point.y), point.z * bodyWidth)
            let hood = GarmentFitProfile.smoothBlend((point.y - top) / 0.08)
            return scaled + (SIMD3<Float>(point.x, point.y - top, point.z) - scaled) * hood
        }

        func sleevePoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let side: Float = point.x < 0 ? -1 : 1
            let mirror = SIMD3<Float>(side, 1, 1)
            let relative = point * mirror - rightShoulder
            let along = axis * simd_dot(relative, axis)
            let cuffProgress = GarmentFitProfile.smoothBlend(
                (simd_dot(relative, axis) / simd_distance(rightShoulder, rightCuff) - 0.25) / 0.75
            )
            let radialScale = (longSleeve ? width + (opening - width) * cuffProgress : opening) * sleeveWidth
            return (newShoulder + along * sleeve + (relative - along) * radialScale) * mirror
        }
        let positions = asset.vertices.indices.map { index in
            let point = asset.vertices[index]
            let progress = preservingNeckShape
                ? GarmentFitter.shapePreservingSleeveBlend(at: point, fitting: fitting, sleeveLength: reference.sleeveLength)
                : fitting.weights[index].sleeveProgress
            let trunk = torso(point)
            let sized = progress > 0 ? trunk + (sleevePoint(point) - trunk) * progress : trunk
            guard preservingNeckShape else { return sized }
            return sized + (point - SIMD3<Float>(0, top, 0) - sized)
                * fitting.weights[index].hoodShapeWeight(at: point)
        }
        func section(_ source: GarmentFitSection) -> GarmentFitSection {
            let center = torso(source.center)
            let scale = source.center.y <= fitting.hip.center.y + 0.001
                ? (target.hipCircumference ?? target.chestCircumference) /
                    (reference.hipCircumference ?? reference.chestCircumference) : width
            return GarmentFitSection(center: center, halfWidth: source.halfWidth * scale,
                                     halfDepth: source.halfDepth * scale,
                                     circumference: source.circumference * scale)
        }
        let profile = GarmentFitProfile(
            hip: section(fitting.hip), waist: section(fitting.waist), chest: section(fitting.chest),
            shoulderWidth: target.shoulderWidth, shoulderHeight: newShoulder.y,
            referenceCircumferences: fitting.referenceCircumferences, weights: fitting.weights
        )
        return GarmentMeshAsset(vertices: positions, indices: asset.indices, trims: asset.trims, fitting: profile,
                                sizing: GarmentSizing(reference: target, rightShoulder: newShoulder, rightCuff: newCuff),
                                sleeves: asset.sleeves?.resized(stationScale: sleeve, transform: sleevePoint))
    }
}

nonisolated struct GarmentSizeInput: Codable, Hashable, Sendable {
    var length: Double
    var shoulderWidth: Double
    var chestWidth: Double
    var sleeveLength: Double
    var hemWidth: Double? = nil
    var sleeveOpeningWidth: Double? = nil
    var armhole: Double? = nil
    var fabric: GarmentFabricSettings? = nil
    var sleeveWidthPercent: Double? = nil

    static let small = Self(length: 61, shoulderWidth: 51, chestWidth: 52, sleeveLength: 18)
    static let medium = Self(length: 63, shoulderWidth: 53, chestWidth: 54.5, sleeveLength: 19)
    static let large = Self(length: 65, shoulderWidth: 55, chestWidth: 56, sleeveLength: 20)

    var isValid: Bool {
        (20...120).contains(length) && (20...90).contains(shoulderWidth)
            && (25...100).contains(chestWidth) && (5...80).contains(sleeveLength)
            && (hemWidth.map { (25...100).contains($0) } ?? true)
            && (sleeveOpeningWidth.map { (6...40).contains($0) } ?? true)
            && (armhole.map { (10...45).contains($0) } ?? true)
            && (sleeveWidthPercent.map { (50...150).contains($0) } ?? true)
    }

    var specification: SampleTShirtSpecification {
        SampleTShirtSpecification(
            chestCircumference: Float(chestWidth / 50),
            waistCircumference: nil, hipCircumference: hemWidth.map { Float($0 / 50) },
            shoulderWidth: Float(shoulderWidth / 100), length: Float(length / 100),
            sleeveLength: Float(sleeveLength / 100),
            sleeveOpening: Float(sleeveOpeningWidth.map { $0 / 50 } ?? (0.36 * chestWidth / 54.5)),
            armholeDepth: armhole.map { Float($0 / 100) },
            sleeveWidthScale: sleeveWidthPercent.map { Float($0 / 100) }
        )
    }

    func applying(to definition: GarmentDefinition) -> GarmentDefinition {
        let source = definition.pattern
        return GarmentDefinition(
            id: definition.id, name: definition.name, selectionLabel: definition.selectionLabel,
            pattern: GarmentPatternDescriptor(id: source.id, version: source.version, source: source.source,
                                             dimensions: specification, meshResource: source.meshResource,
                                             anchor: source.anchor, kind: source.kind, fittingMode: source.fittingMode),
            material: GarmentMaterial(maximumStrain: definition.material.maximumStrain,
                                      fabric: fabric ?? definition.material.fabric),
            appearance: definition.appearance
        )
    }
}

extension GarmentSizeInput {
    nonisolated init(dimensions: SampleTShirtSpecification) {
        self.init(
            length: Double((dimensions.length * 1000).rounded()) / 10,
            shoulderWidth: Double((dimensions.shoulderWidth * 1000).rounded()) / 10,
            chestWidth: Double((dimensions.chestCircumference * 500).rounded()) / 10,
            sleeveLength: Double((dimensions.sleeveLength * 1000).rounded()) / 10
        )
        hemWidth = dimensions.hipCircumference.map { Double($0) * 50 }
        if abs(specification.sleeveOpening - dimensions.sleeveOpening) > 0.00001 {
            sleeveOpeningWidth = Double(dimensions.sleeveOpening) * 50
        }
        armhole = dimensions.armholeDepth.map { Double($0) * 100 }
        sleeveWidthPercent = dimensions.sleeveWidthScale.map { Double(($0 * 1000).rounded()) / 10 }
    }
}

nonisolated struct GarmentFitSummary: Sendable, Equatable {
    let chestEase: Float
    let shoulderEase: Float
    let wornChest: Float?
    let verticalLength: Float
    let maximumStrain: Float
    let remainingOverlap: Float
    let waistEase: Float?
    let hipEase: Float?
    let footLengthEase: Float?
    let footWidthEase: Float?
    let collisionWasSolved: Bool
    let hemFloorClearance: Float?

    var primaryEase: Float { footLengthEase ?? waistEase ?? chestEase }
    @MainActor var primaryEaseTitle: String {
        if footLengthEase != nil { return L("길이 여유") }
        return waistEase == nil ? L("가슴 여유") : L("허리 여유")
    }

    init(asset: GarmentMeshAsset, positions: [SIMD3<Float>], body: GarmentBodyFitProfile,
         maximumStrain: Float, remainingOverlap: Float) {
        let reference = asset.sizing?.reference
        waistEase = asset.trousers.map { $0.reference.waistCircumference - body.waist.circumference }
        hipEase = asset.trousers.map { $0.reference.hipCircumference - body.hip.circumference }
        let feet = [body.rightFoot, body.leftFoot].compactMap { $0 }
        footLengthEase = asset.footwear.flatMap { binding in feet.map(\.length).max().map { binding.reference.length - $0 } }
        footWidthEase = asset.footwear.flatMap { binding in feet.map(\.width).max().map { binding.reference.width - $0 } }
        collisionWasSolved = asset.footwear == nil
        hemFloorClearance = asset.trousers.flatMap { _ in
            feet.map(\.floor).min().flatMap { floor in positions.map(\.y).min().map { $0 - floor } }
        }
        chestEase = (reference?.chestCircumference ?? asset.fitting?.chest.circumference ?? 0) - body.chest.circumference
        shoulderEase = (reference?.shoulderWidth ?? asset.fitting?.shoulderWidth ?? 0) - body.shoulderWidth
        var topology = ParametricBody()
        let weights = asset.fitting?.weights
        for offset in stride(from: 0, to: asset.indices.count, by: 3) {
            let corners = (0..<3).map { Int(asset.indices[offset + $0]) }
            if corners.allSatisfy({ (weights?[$0].sleeveProgress ?? 0) < 0.1 }) {
                topology.faces.append(.init(indices: corners, region: 0))
            }
        }
        wornChest = asset.fitting == nil ? nil
            : topology.section(at: body.chest.center.y, positions: positions, convex: true)?.circumference
        let heights = positions.indices.filter { (weights?[$0].sleeveProgress ?? 0) < 0.1 }.map { positions[$0].y }
        verticalLength = (heights.max() ?? 0) - (heights.min() ?? 0)
        self.maximumStrain = maximumStrain
        self.remainingOverlap = remainingOverlap
    }
}