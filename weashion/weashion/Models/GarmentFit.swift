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

    init(center: SIMD3<Float>, halfWidth: Float, halfDepth: Float, circumference: Float) {
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
    var rightHandSections: [GarmentFitSection] = []
    var rightWrist: GarmentFitSection? = nil
    var rightLegSections: [GarmentFitSection] = []
    var leftLegSections: [GarmentFitSection] = []
    var rightFoot: GarmentFootBounds? = nil
    var leftFoot: GarmentFootBounds? = nil
    var inseamHeight: Float? = nil

    func translated(by offset: SIMD3<Float>) -> Self {
        Self(chest: chest.translated(by: offset), waist: waist.translated(by: offset),
             hip: hip.translated(by: offset), shoulderWidth: shoulderWidth,
             shoulderHeight: shoulderHeight + offset.y, rightArm: rightArm.map { $0 + offset },
             rightArmSections: rightArmSections.map { $0.translated(by: offset) },
             rightHandSections: rightHandSections.map { $0.translated(by: offset) },
             rightWrist: rightWrist?.translated(by: offset),
             rightLegSections: rightLegSections.map { $0.translated(by: offset) },
             leftLegSections: leftLegSections.map { $0.translated(by: offset) },
             rightFoot: rightFoot?.translated(by: offset), leftFoot: leftFoot?.translated(by: offset),
             inseamHeight: inseamHeight.map { $0 + offset.y })
    }
}

nonisolated struct GarmentVertexFitWeight: Codable, Sendable {
    let regions: SIMD4<Float>
    var sleeveProgress: Float = 0
    var sleeveAngle: Float? = nil

    func hoodShapeWeight(at point: SIMD3<Float>, transitionWidth: Float = 0.07) -> Float {
        let center = 1 - GarmentFitProfile.smoothBlend((abs(point.x) - 0.17) / transitionWidth)
        let height = GarmentFitProfile.smoothBlend((point.y + 0.10) / 0.10)
        let back = 1 - GarmentFitProfile.smoothBlend((point.z + 0.015) / 0.08)
        return center * height * back
    }

    func preservesNeckShape(at point: SIMD3<Float>) -> Bool {
        hoodShapeWeight(at: point) >= 0.999999
    }
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
    static func shapePreservingSleeveBlend(at point: SIMD3<Float>, fitting: GarmentFitProfile,
                                           sleeveLength: Float) -> Float {
        let transition = 0.20 + max(0, -point.y - 0.10) * 0.60
        let lateral = GarmentFitProfile.smoothBlend(
            (abs(point.x) - fitting.chest.halfWidth * 0.55) / transition)
        let aboveHem = GarmentFitProfile.smoothBlend((point.y + sleeveLength + 0.02) / 0.10)
        let distal = GarmentFitProfile.smoothBlend((abs(point.x) - fitting.chest.halfWidth - 0.05) / 0.10)
        return lateral * max(aboveHem, distal)
    }

    static func contactGuides(for asset: GarmentMeshAsset, positions: [SIMD3<Float>],
                              body: GarmentBodyFitProfile) -> (origins: [SIMD3<Float>], axes: [SIMD3<Float>]) {
        let arm = GarmentSleeveCurve(chain: body.rightArmSections.map(\.center))
        let trunk = [body.hip.center, body.waist.center, body.chest.center]
        var origins: [SIMD3<Float>] = []
        var axes: [SIMD3<Float>] = []
        for (index, point) in positions.enumerated() {
            let sleeve = asset.fitting?.weights[index].sleeveProgress ?? 0
            let side: Float = point.x < 0 ? -1 : 1
            let mirror = SIMD3<Float>(side, 1, 1)
            if sleeve >= 0.5, let frame = arm.closestFrame(to: point * mirror) {
                origins.append(frame.center * mirror)
                axes.append(frame.tangent * mirror)
            } else if asset.fitting != nil, point.y < body.shoulderHeight - 0.06 {
                origins.append(LowerGarmentFitter.center(at: point.y, chain: trunk))
                axes.append([0, 1, 0])
            } else {
                origins.append(.zero)
                axes.append(.zero)
            }
        }
        return (origins, axes)
    }

    static func positions(for asset: GarmentMeshAsset, body: GarmentBodyFitProfile?) -> [SIMD3<Float>] {
        placement(for: asset, body: body).positions
    }

    static func placement(for asset: GarmentMeshAsset, body: GarmentBodyFitProfile?,
                          preservingShape: Bool = false) -> GarmentPlacement {
        if let binding = asset.trousers, let body {
            return .init(positions: LowerGarmentFitter.trousers(asset, binding: binding, body: body), pins: [])
        }
        if let binding = asset.footwear, let body {
            return .init(positions: LowerGarmentFitter.footwear(asset, binding: binding, body: body), pins: [])
        }
        guard let fitting = asset.fitting, let body else { return .init(positions: asset.vertices, pins: []) }
        let fixedSize = asset.sizing != nil
        let hip = RegionTransform(source: fitting.hip, body: body.hip, reference: fitting.referenceCircumferences.x, fixedSize: fixedSize)
        let waist = RegionTransform(source: fitting.waist, body: body.waist, reference: fitting.referenceCircumferences.y, fixedSize: fixedSize)
        let chest = RegionTransform(source: fitting.chest, body: body.chest, reference: fitting.referenceCircumferences.z, fixedSize: fixedSize)
        let shoulderEase = fitting.shoulderWidth - body.shoulderWidth
        let shoulderExpansion = fixedSize ? 0 : max(-shoulderEase, 0) * 0.5
        let shoulderDrop = min(max(shoulderEase, 0) * 0.35, 0.04)
        let drapesOverShoulder = fixedSize && shoulderEase > 0
        let shoulderShift = body.shoulderHeight - fitting.shoulderHeight
            - (drapesOverShoulder ? 0 : shoulderDrop) + 0.006
        let hoodOffset = SIMD3<Float>(0, 0, -0.020)
        let trunkCenters = (body.rightLegSections.map(\.center).filter { $0.y < body.hip.center.y }
            + [body.hip.center, body.waist.center, body.chest.center]).sorted { $0.y < $1.y }
        func torsoWidth(at height: Float) -> Float {
            let fraction = min(max((height - body.waist.center.y) / (body.chest.center.y - body.waist.center.y), 0), 1)
            return body.waist.halfWidth + (body.chest.halfWidth - body.waist.halfWidth) * fraction
        }
        let underarmHeight = body.rightArmSections.last { section in
            section.center.y <= body.chest.center.y
                && section.center.x - section.halfWidth - torsoWidth(at: section.center.y) > 0.014
        }?.center.y
        let armCenters = body.rightArmSections.isEmpty ? body.rightArm : body.rightArmSections.map(\.center)
        let sleeveLength = asset.sizing?.reference.sleeveLength ?? fitting.sleeve?.length
        let cuff = sleeveLength.flatMap { length in
            sleeveFrame(arm: armCenters, height: min(
                body.shoulderHeight - length * 0.92 - shoulderDrop, underarmHeight.map { $0 - 0.015 } ?? body.shoulderHeight))
        }
        let shoulderDirection = cuff.map { SIMD3<Float>($0.radial.y, -$0.radial.x, 0) }
            ?? SIMD3<Float>(0, -1, 0)
        func torsoPosition(_ point: SIMD3<Float>, weights: SIMD4<Float>) -> SIMD3<Float> {
            let side: Float = point.x >= 0 ? 1 : -1
            let attachment = GarmentFitProfile.smoothBlend(
                (abs(point.x) - 0.09) / max(fitting.shoulderWidth * 0.5 - 0.09, 0.01)
            )
            var shoulder = point + SIMD3<Float>(side * shoulderExpansion, shoulderShift, 0)
                * (preservingShape ? 1 : attachment)
            if drapesOverShoulder && !preservingShape {
                let supportWidth = body.shoulderWidth * 0.5
                let overhang = max(abs(point.x) - supportWidth, 0)
                shoulder += SIMD3<Float>(side * (shoulderDirection.x - 1), shoulderDirection.y, 0) * overhang
            }
            var torso = hip.apply(point) * weights.x + waist.apply(point) * weights.y
                + chest.apply(point) * weights.z + shoulder * weights.w
            if preservingShape {
                torso.y += shoulderShift * (1 - weights.w)
                let center = LowerGarmentFitter.center(at: point.y + shoulderShift, chain: trunkCenters)
                torso.z += center.z * (1 - weights.w)
                    - body.hip.center.z * weights.x - body.waist.center.z * weights.y - body.chest.center.z * weights.z
                return torso
            }
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
        let root = asset.sizing.map { sizing in
            var root = torsoPosition(sizing.rightShoulder, weights: [0, 0, 0, 1])
            if preservingShape && drapesOverShoulder {
                let overhang = max(sizing.rightShoulder.x - max(body.shoulderWidth * 0.5, 0.22), 0)
                root += SIMD3<Float>(shoulderDirection.x - 1, shoulderDirection.y, 0) * overhang
            }
            return root
        }
        let armCurve = root.flatMap { root -> GarmentSleeveCurve? in
            let wristHeight = body.rightWrist?.center.y ?? -.infinity
            var chain = [root] + armCenters.reversed().filter {
                $0.y < root.y - 0.01 && $0.y > wristHeight + 0.005
            }
            if let wrist = body.rightWrist { chain.append(wrist.center) }
            if let wrist = chain.last {
                chain.append(contentsOf: body.rightHandSections.map(\.center).filter { $0.y < wrist.y - 0.005 })
            }
            return chain.count >= 2 ? GarmentSleeveCurve(chain: chain) : nil
        }
        let sourceRoot = preservingShape ? asset.sizing.map {
            [GarmentSleeveKnot(center: $0.rightShoulder, station: 0)]
        } ?? [] : []
        let rightSleeve = asset.sleeves.map { GarmentSleeveCurve(knots: sourceRoot + $0.right) }
        let leftSleeve = asset.sleeves.map {
            GarmentSleeveCurve(knots: sourceRoot + $0.left.map {
                .init(center: $0.center * SIMD3<Float>(-1, 1, 1), station: $0.station)
            })
        }
        let cuffStop: Float?
        if asset.sleeves != nil, let sizing = asset.sizing, let wrist = body.rightWrist,
           let hand = body.rightHandSections.map(\.circumference).max(),
           hand > sizing.reference.effectiveSleeveOpening * 1.02,
           let station = armCurve?.closestFrame(to: wrist.center)?.station,
           station < sizing.reference.sleeveLength {
            cuffStop = station
        } else {
            cuffStop = nil
        }
        func armStation(_ station: Float) -> Float {
            guard let stop = cuffStop, let length = asset.sizing?.reference.sleeveLength else { return station }
            if preservingShape { return station * stop / length }
            let start = stop * 0.55
            guard station > start else { return station }
            return start + (station - start) * (stop - start) / (length - start)
        }
        let shapeArm = preservingShape ? asset.sizing.flatMap { sizing -> (
            axis: SIMD3<Float>, scale: Float, rotation: simd_quatf,
            right: GarmentSleeveCurve.SmoothedOffsets, left: GarmentSleeveCurve.SmoothedOffsets,
            destination: GarmentSleeveCurve.SmoothedOffsets)? in
            let length = sizing.reference.sleeveLength
            guard let root, let armCurve, let rightSleeve, let leftSleeve,
                  let end = armCurve.frame(at: armStation(length)) else {
                return nil
            }
            let source = sizing.rightCuff - sizing.rightShoulder
            let destination = end.center - root
            guard simd_length_squared(destination) > 1e-8 else { return nil }
            return (simd_normalize(source), simd_length(destination) / simd_length(source),
                    simd_quatf(from: simd_normalize(source), to: simd_normalize(destination)),
                    rightSleeve.smoothedOffsets(from: sizing.rightShoulder, to: sizing.rightCuff, length: length),
                    leftSleeve.smoothedOffsets(from: sizing.rightShoulder, to: sizing.rightCuff, length: length),
                    armCurve.smoothedOffsets(from: root, to: end.center, length: armStation(length)))
        } : nil
        let shoulderContact = GarmentFitProfile.smoothBlend(
            (1 - (asset.sizing?.reference.sleeveWidthScale ?? 1)) / 0.20)
        func shoulderClearance(_ point: SIMD3<Float>) -> SIMD3<Float> {
            guard shoulderContact > 0, let section = body.rightArmSections.last else { return point }
            let upper = 1 - GarmentFitProfile.smoothBlend((point.y - section.center.y - 0.02) / 0.18)
            let lower = GarmentFitProfile.smoothBlend((point.y - section.center.y + 0.28) / 0.14)
            let lateral = GarmentFitProfile.smoothBlend((abs(point.x) - body.chest.halfWidth * 0.78) / 0.08)
            let horizontal = (abs(point.x) - section.center.x) / 0.075
            let blend = upper * lower * lateral * exp(-0.5 * horizontal * horizontal)
            guard blend > 0 else { return point }
            let depth = section.halfDepth + 0.006
            let offset = point.z - section.center.z
            let contact = 1 - GarmentFitProfile.smoothBlend((abs(offset) - depth * 0.5) / depth)
            let correction = depth * 0.54 * tanh(offset / (depth * 0.2)) * contact * blend * shoulderContact
            return point + SIMD3<Float>(0, 0, correction)
        }
        let positions = asset.vertices.indices.map { index -> SIMD3<Float> in
            let point = asset.vertices[index]
            let binding = fitting.weights[index]
            if preservingShape && binding.preservesNeckShape(at: point) {
                return point + SIMD3<Float>(0, shoulderShift, 0) + hoodOffset
            }
            let side: Float = point.x >= 0 ? 1 : -1
            if let shapeArm, let sizing = asset.sizing, let root {
                let hood = binding.hoodShapeWeight(at: point, transitionWidth: 0.07 + 0.02 * shoulderContact)
                let blend = shapePreservingSleeveBlend(at: point, fitting: fitting,
                    sleeveLength: sizing.reference.sleeveLength) * (1 - hood)
                let mirror = SIMD3<Float>(side, 1, 1)
                let relative = point * mirror - sizing.rightShoulder
                let station = max(simd_dot(relative, shapeArm.axis), 0)
                let sourceOffsets = side > 0 ? shapeArm.right : shapeArm.left
                let centerOffset = sourceOffsets.offset(at: station)
                let radial = relative - shapeArm.axis * simd_dot(relative, shapeArm.axis) - centerOffset
                let progress = station / sizing.reference.sleeveLength
                let shoulderCap = GarmentFitProfile.smoothBlend(progress / 0.08)
                    * (1 - GarmentFitProfile.smoothBlend((progress - 0.28) / 0.32))
                    * GarmentFitProfile.smoothBlend((abs(point.x) - fitting.chest.halfWidth - 0.03) / 0.06)
                let axialOffset = shapeArm.axis * simd_dot(relative, shapeArm.axis) * (shapeArm.scale - 1)
                let shoulderInset = radial * (0.22 * shoulderCap)
                let scaled = relative + (axialOffset - centerOffset - shoulderInset) * blend
                let rotation = simd_slerp(simd_quatf(angle: 0, axis: [0, 0, 1]), shapeArm.rotation, blend)
                let translatedRoot = sizing.rightShoulder + SIMD3<Float>(0, shoulderShift, 0)
                let pivot = translatedRoot + (root - translatedRoot) * blend
                let translated = point + SIMD3<Float>(0, shoulderShift, 0)
                let torsoCorrection = torsoPosition(point, weights: binding.regions) - translated
                let curveOffset = shapeArm.destination.offset(at: armStation(station)) * blend
                let placed = (pivot + rotation.act(scaled) + curveOffset) * mirror
                    + torsoCorrection * (1 - blend) * (1 - hood) + hoodOffset * hood
                return shoulderClearance(placed)
            }
            let sleeveProgress: Float
            if preservingShape, let sleeveLength {
                sleeveProgress = shapePreservingSleeveBlend(at: point, fitting: fitting, sleeveLength: sleeveLength)
            } else {
                sleeveProgress = binding.sleeveProgress
            }
            let sourceCurve = side > 0 ? rightSleeve : leftSleeve
            let source: GarmentSleeveCurve.Frame?
            source = sourceCurve?.closestFrame(to: point * SIMD3<Float>(side, 1, 1))
            if sleeveProgress > 0,
               let source,
               let destination = armCurve?.frame(at: armStation(source.station)) {
                let relative = point * SIMD3<Float>(side, 1, 1) - source.center
                let sleeve = (destination.center + destination.radial * simd_dot(relative, source.radial)
                    + destination.depth * simd_dot(relative, source.depth)
                    + destination.tangent * simd_dot(relative, source.tangent)) * SIMD3<Float>(side, 1, 1)
                let trunk = torsoPosition(point, weights: binding.regions)
                return trunk + (sleeve - trunk) * sleeveProgress
            }
            if let sizing = asset.sizing, let cuff, binding.sleeveProgress > 0 {
                let mirror = SIMD3<Float>(side, 1, 1)
                let root = torsoPosition(sizing.rightShoulder, weights: [0, 0, 0, 1])
                let originalDirection = simd_normalize(sizing.rightCuff - sizing.rightShoulder)
                let destination = cuff.center - root
                if simd_length_squared(destination) > 1e-8 {
                    if sizing.reference.sleeveLength > 0.35 {
                        let relative = point * mirror - sizing.rightShoulder
                        let distance = max(simd_dot(relative, originalDirection), 0)
                        let chain = [root] + armCenters.reversed().filter { $0.y < root.y - 0.01 }
                        if let frame = LowerGarmentFitter.frame(at: distance, along: chain) {
                            let radial = relative - originalDirection * simd_dot(relative, originalDirection)
                            let rotation = simd_quatf(from: originalDirection, to: frame.direction)
                            let sleeve = (frame.center + rotation.act(radial)) * mirror
                            let trunk = torsoPosition(point, weights: binding.regions)
                            return trunk + (sleeve - trunk) * binding.sleeveProgress
                        }
                    }
                    let rotation = simd_quatf(from: originalDirection, to: simd_normalize(destination))
                    let sleeve = (root + rotation.act(point * mirror - sizing.rightShoulder)) * mirror
                    let trunk = torsoPosition(point, weights: binding.regions)
                    return trunk + (sleeve - trunk) * binding.sleeveProgress
                }
            }
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
        var pins: [Int32] = []
        if preservingShape {
            pins = fitting.weights.indices.filter {
                fitting.weights[$0].preservesNeckShape(at: asset.vertices[$0])
            }.map { Int32($0) }
        }
        if !preservingShape, cuffStop != nil, let sleeves = asset.sleeves {
            for center in [sleeves.right.last?.center, sleeves.left.last?.center].compactMap({ $0 }) {
                if let cuff = asset.trims.min(by: { first, second in
                    func centerOf(_ trim: GarmentTrim) -> SIMD3<Float> {
                        trim.vertices.reduce(SIMD3<Float>.zero) { $0 + asset.vertices[$1] } / Float(trim.vertices.count)
                    }
                    return simd_distance_squared(centerOf(first), center) < simd_distance_squared(centerOf(second), center)
                }) {
                    pins.append(contentsOf: cuff.vertices.map { Int32($0) })
                }
            }
        }
        return .init(positions: positions, pins: pins)
    }

    nonisolated struct GarmentPlacement: Sendable {
        let positions: [SIMD3<Float>]
        let pins: [Int32]
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

        init(source: GarmentFitSection, body: GarmentFitSection, reference: Float, fixedSize: Bool) {
            self.source = source
            let ease = source.circumference - body.circumference
            let referenceEase = max(source.circumference - reference, source.circumference * 0.025)
            // Product-sized garments start as the body section scaled to their own circumference.
            let contact = fixedSize ? 1 : referenceEase / (referenceEase + max(ease, 0))
            let stretch = max(-ease, 0) / source.circumference
            let referenceSize = SIMD2<Float>(source.halfWidth, source.halfDepth)
            let bodyShape = SIMD2<Float>(body.halfWidth, body.halfDepth)
                * (source.circumference / body.circumference)
            let shape = referenceSize + (bodyShape - referenceSize) * contact
            let circumference = fixedSize ? source.circumference
                : max(source.circumference, body.circumference + 2 * .pi * 0.004)
            let correction = circumference / GarmentFitSection.ellipseCircumference(halfWidth: shape.x, halfDepth: shape.y)
            widthScale = shape.x * correction / source.halfWidth
            depthScale = shape.y * correction / source.halfDepth
            depthOffset = (body.center.z - source.center.z) * contact
            sag = fixedSize ? 0 : min(max(ease, 0) * 0.10, 0.025)
            verticalContraction = fixedSize ? 0 : min(stretch * 0.2, 0.06)
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