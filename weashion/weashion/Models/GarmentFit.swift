import Foundation
import simd

nonisolated struct GarmentFitSection: Codable, Sendable {
    let center: SIMD3<Float>
    let halfWidth: Float
    let halfDepth: Float
    let circumference: Float

    init(vertices: [SIMD3<Float>]) {
        let center = vertices.reduce(SIMD3<Float>.zero, +) / Float(vertices.count)
        self.center = center
        halfWidth = vertices.map { abs($0.x - center.x) }.max() ?? 0
        halfDepth = vertices.map { abs($0.z - center.z) }.max() ?? 0
        circumference = vertices.indices.reduce(Float.zero) { total, index in
            total + simd_distance(vertices[index], vertices[(index + 1) % vertices.count])
        }
    }

    private init(center: SIMD3<Float>, halfWidth: Float, halfDepth: Float, circumference: Float) {
        self.center = center
        self.halfWidth = halfWidth
        self.halfDepth = halfDepth
        self.circumference = circumference
    }

    func translated(by offset: SIMD3<Float>) -> Self {
        Self(center: center + offset, halfWidth: halfWidth, halfDepth: halfDepth, circumference: circumference)
    }

    var isValid: Bool {
        [center.x, center.y, center.z, halfWidth, halfDepth, circumference].allSatisfy(\.isFinite)
            && halfWidth > 0 && halfDepth > 0 && circumference > 0
    }

    static func ellipseCircumference(halfWidth: Float, halfDepth: Float) -> Float {
        var previous = SIMD2<Float>(halfWidth, 0)
        var length: Float = 0
        for segment in 1...64 {
            let angle = 2 * Float.pi * Float(segment) / 64
            let point = SIMD2<Float>(halfWidth * cos(angle), halfDepth * sin(angle))
            length += simd_distance(previous, point)
            previous = point
        }
        return length
    }
}

nonisolated struct GarmentBodyFitProfile: Sendable {
    let chest: GarmentFitSection
    let waist: GarmentFitSection
    let hip: GarmentFitSection
    let shoulderWidth: Float
    let shoulderHeight: Float
    var rightArm: [SIMD3<Float>] = []
    var rightArmSections: [GarmentFitSection] = []

    func translated(by offset: SIMD3<Float>) -> Self {
        Self(chest: chest.translated(by: offset), waist: waist.translated(by: offset),
             hip: hip.translated(by: offset), shoulderWidth: shoulderWidth,
             shoulderHeight: shoulderHeight + offset.y, rightArm: rightArm.map { $0 + offset },
             rightArmSections: rightArmSections.map { $0.translated(by: offset) })
    }
}

nonisolated struct GarmentVertexFitWeight: Codable, Sendable {
    let regions: SIMD4<Float>
    var sleeveProgress: Float = 0
    var sleeveAngle: Float? = nil
}

nonisolated struct GarmentSleeveFit: Codable, Sendable {
    let center: SIMD3<Float>
    let radialAxis: SIMD3<Float>
    let length: Float
    let radius: Float

    var isValid: Bool {
        [center.x, center.y, center.z, radialAxis.x, radialAxis.y, radialAxis.z, length, radius].allSatisfy(\.isFinite)
            && (0.05...1).contains(length) && (0.01...0.3).contains(radius)
            && abs(simd_length(radialAxis) - 1) < 0.001
    }
}

nonisolated struct GarmentFitProfile: Codable, Sendable {
    let hip: GarmentFitSection
    let waist: GarmentFitSection
    let chest: GarmentFitSection
    let shoulderWidth: Float
    let shoulderHeight: Float
    let referenceCircumferences: SIMD3<Float>
    let weights: [GarmentVertexFitWeight]
    var sleeve: GarmentSleeveFit? = nil

    var memoryCost: Int { weights.count * MemoryLayout<GarmentVertexFitWeight>.stride + 256 }

    func isValid(vertexCount: Int) -> Bool {
        [hip, waist, chest].allSatisfy(\.isValid)
            && hip.center.y < waist.center.y && waist.center.y < chest.center.y
            && shoulderWidth.isFinite && shoulderWidth > 0
            && shoulderHeight.isFinite && shoulderHeight > chest.center.y
            && (sleeve?.isValid ?? true)
            && (0..<3).allSatisfy { referenceCircumferences[$0].isFinite && referenceCircumferences[$0] > 0 }
            && weights.count == vertexCount && weights.allSatisfy { weight in
                let regions = weight.regions
                return (0..<4).allSatisfy { regions[$0].isFinite && (0...1).contains(regions[$0]) }
                    && abs(regions.x + regions.y + regions.z + regions.w - 1) < 0.001
                    && weight.sleeveProgress.isFinite && (0...1).contains(weight.sleeveProgress)
                    && (weight.sleeveAngle?.isFinite ?? true)
            }
    }

    static func torsoWeights(height: Float, hip: Float, waist: Float, chest: Float) -> SIMD4<Float> {
        if height <= hip { return [1, 0, 0, 0] }
        if height < waist {
            let blend = smoothBlend((height - hip) / (waist - hip))
            return [1 - blend, blend, 0, 0]
        }
        let blend = smoothBlend((height - waist) / (chest - waist))
        return [0, 1 - blend, blend, 0]
    }

    static func smoothBlend(_ progress: Float) -> Float {
        let value = min(max(progress, 0), 1)
        return value * value * (3 - 2 * value)
    }
}

nonisolated enum GarmentFitter {
    static func positions(for asset: GarmentMeshAsset, body: GarmentBodyFitProfile?) -> [SIMD3<Float>] {
        guard let fitting = asset.fitting, let body else { return asset.vertices }
        let hip = RegionTransform(source: fitting.hip, body: body.hip, reference: fitting.referenceCircumferences.x)
        let waist = RegionTransform(source: fitting.waist, body: body.waist, reference: fitting.referenceCircumferences.y)
        let chest = RegionTransform(source: fitting.chest, body: body.chest, reference: fitting.referenceCircumferences.z)
        let shoulderEase = fitting.shoulderWidth - body.shoulderWidth
        let shoulderExpansion = max(-shoulderEase, 0) * 0.5
        let shoulderDrop = min(max(shoulderEase, 0) * 0.35, 0.04)
        let shoulderShift = body.shoulderHeight - fitting.shoulderHeight - shoulderDrop + 0.020
        func torsoWidth(at height: Float) -> Float {
            let fraction = min(max((height - body.waist.center.y) / (body.chest.center.y - body.waist.center.y), 0), 1)
            return body.waist.halfWidth + (body.chest.halfWidth - body.waist.halfWidth) * fraction
        }
        let underarmHeight = body.rightArmSections.last { section in
            section.center.y <= body.chest.center.y
                && section.center.x - section.halfWidth - torsoWidth(at: section.center.y) > 0.014
        }?.center.y
        let armCenters = body.rightArmSections.isEmpty ? body.rightArm : body.rightArmSections.map(\.center)
        let cuff = fitting.sleeve.flatMap { sleeve in
            sleeveFrame(arm: armCenters, height: min(
                body.shoulderHeight - sleeve.length * 0.92 - shoulderDrop, underarmHeight.map { $0 - 0.015 } ?? body.shoulderHeight))
        }
        func torsoPosition(_ point: SIMD3<Float>, weights: SIMD4<Float>) -> SIMD3<Float> {
            let side: Float = point.x >= 0 ? 1 : -1
            let attachment = GarmentFitProfile.smoothBlend(
                (abs(point.x) - 0.09) / max(fitting.shoulderWidth * 0.5 - 0.09, 0.01)
            )
            let shoulder = point + SIMD3<Float>(side * shoulderExpansion, shoulderShift, 0) * attachment
            var torso = hip.apply(point) * weights.x + waist.apply(point) * weights.y
                + chest.apply(point) * weights.z + shoulder * weights.w
            let underarm = pow(min(abs(point.x) / fitting.chest.halfWidth, 1), 12)
                * GarmentFitProfile.smoothBlend((point.y - fitting.chest.center.y + 0.080) / 0.080)
                * pow(1 - weights.w, 4)
            let sideLimit = body.chest.halfWidth + 0.005
            torso.x -= side * max(abs(torso.x) - sideLimit, 0) * underarm
            if let underarmHeight {
                torso.y -= max(torso.y - underarmHeight, 0) * underarm
            }
            if let section = body.rightArmSections.min(by: {
                abs($0.center.y - torso.y) < abs($1.center.y - torso.y)
            }), abs(section.center.y - torso.y) < 0.025 {
                let medial = pow(max(1 - abs(torso.z - section.center.z) / (section.halfDepth + 0.018), 0), 2)
                    * pow(1 - weights.w, 4)
                let limit = section.center.x - section.halfWidth - 0.006
                torso.x -= side * max(abs(torso.x) - limit, 0) * medial
            }
            return torso
        }
        return asset.vertices.indices.map { index in
            let point = asset.vertices[index]
            let binding = fitting.weights[index]
            let side: Float = point.x >= 0 ? 1 : -1
            if let reference = fitting.sleeve, let cuff, let angle = binding.sleeveAngle {
                let original = reference.center + reference.radialAxis * (reference.radius * cos(angle))
                    + SIMD3<Float>(0, 0, reference.radius * sin(angle))
                let destination = (cuff.center + cuff.radial * (reference.radius * cos(angle))
                    + cuff.depth * (reference.radius * sin(angle))) * SIMD3<Float>(side, 1, 1)
                let progress = binding.sleeveProgress
                guard progress < 1 else { return destination }
                let source = (point - original * SIMD3<Float>(side, 1, 1) * progress) / (1 - progress)
                let root = torsoPosition(source, weights: binding.regions)
                return root + (destination - root) * progress
                    + SIMD3<Float>(side * 0.012, 0.008, 0) * sin(.pi * progress)
            }
            let torso = torsoPosition(point, weights: binding.regions)
            let sleeve = point + SIMD3<Float>(side * shoulderExpansion, shoulderShift, 0)
            return torso + (sleeve - torso) * binding.sleeveProgress
        }
    }

    private static func sleeveFrame(arm: [SIMD3<Float>], height: Float) -> (center: SIMD3<Float>, radial: SIMD3<Float>, depth: SIMD3<Float>)? {
        guard arm.count >= 2 else { return nil }
        let upperIndex = arm.indices.dropFirst().first { arm[$0].y >= height } ?? (arm.count - 1)
        let lower = arm[upperIndex - 1]
        let upper = arm[upperIndex]
        let span = upper.y - lower.y
        guard span > 0.0001 else { return nil }
        let fraction = min(max((height - lower.y) / span, 0), 1)
        let center = lower + (upper - lower) * fraction
        let direction = simd_normalize(lower - upper)
        let radial = simd_normalize(SIMD3<Float>(-direction.y, direction.x, 0))
        return (center, radial, simd_normalize(simd_cross(direction, radial)))
    }

    private nonisolated struct RegionTransform {
        let source: GarmentFitSection
        let widthScale: Float
        let depthScale: Float
        let depthOffset: Float
        let sag: Float
        let verticalContraction: Float

        init(source: GarmentFitSection, body: GarmentFitSection, reference: Float) {
            self.source = source
            let ease = source.circumference - body.circumference
            let referenceEase = max(source.circumference - reference, source.circumference * 0.025)
            let contact = referenceEase / (referenceEase + max(ease, 0))
            let stretch = max(-ease, 0) / source.circumference
            let referenceSize = SIMD2<Float>(source.halfWidth, source.halfDepth)
            let bodyShape = SIMD2<Float>(body.halfWidth, body.halfDepth)
                * (source.circumference / body.circumference)
            let shape = referenceSize + (bodyShape - referenceSize) * contact
            let circumference = max(source.circumference, body.circumference + 2 * .pi * 0.004)
            let correction = circumference / GarmentFitSection.ellipseCircumference(halfWidth: shape.x, halfDepth: shape.y)
            widthScale = shape.x * correction / source.halfWidth
            depthScale = shape.y * correction / source.halfDepth
            depthOffset = (body.center.z - source.center.z) * contact
            sag = min(max(ease, 0) * 0.10, 0.025)
            verticalContraction = min(stretch * 0.2, 0.06)
        }

        func apply(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let lateral = min(abs(point.x - source.center.x) / source.halfWidth, 1)
            return [
                source.center.x + (point.x - source.center.x) * widthScale,
                point.y * (1 - verticalContraction) - sag * (1 - lateral * lateral),
                source.center.z + (point.z - source.center.z) * depthScale + depthOffset
            ]
        }
    }
}