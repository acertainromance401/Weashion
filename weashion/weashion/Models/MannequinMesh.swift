import Foundation
import simd
import CryptoKit

nonisolated struct MannequinMesh {
    nonisolated struct Landmarks: Decodable {
        let height: Float
        let inseam: Float
        let hipHeight: Float
        let waistHeight: Float
        let chestHeight: Float
        let shoulderHeight: Float
        let shoulderWidth: Float
    }

    private nonisolated struct Asset: Decodable {
        let version: Int
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
        let regions: [Int]
        let armWeights: [Float]
        let armCenters: [SIMD3<Float>]
        let legCenters: [SIMD3<Float>]
        let landmarks: Landmarks
        let anatomy: BodyAnatomy?
    }

    private nonisolated struct FrameMorphs: Decodable {
        let version: Int
        let sourceSHA256: String
        let vertexCount: Int
        let presets: [String: [SIMD3<Float>]]
        let breastPresets: [String: [SIMD3<Float>]]
    }

    nonisolated struct Fitted: Sendable {
        let surface: BodySurfaceMesh
        let profile: GarmentBodyFitProfile
        let collisionMesh: GarmentCollisionMesh?
        let anchor: SIMD3<Float>
        let anatomy: BodyAnatomy?
        let landmarks: [BodyAnatomy.LandmarkID: SIMD3<Float>]
    }

    private let asset: Asset
    private let frameMorphs: FrameMorphs?
    private let topology: ParametricBody
    private let referenceSections: [GarmentFitSection]
    private let referenceArmWidths: [Float]
    private let deformationWeights: [Float]
    private let neighbors: [[Int]]

    static func load(resource: String) -> Self? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let asset = try? JSONDecoder().decode(Asset.self, from: data),
              asset.version == 1, !asset.vertices.isEmpty, !asset.indices.isEmpty,
              asset.indices.count.isMultiple(of: 3), asset.indices.count / 3 == asset.regions.count,
              asset.armWeights.count == asset.vertices.count,
              asset.vertices.allSatisfy(Self.finite),
              asset.indices.allSatisfy({ Int($0) < asset.vertices.count }),
              asset.regions.allSatisfy({ (0...4).contains($0) }),
              asset.armWeights.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              asset.anatomy?.isValid(vertexCount: asset.vertices.count) ?? true,
              validChain(asset.armCenters), validChain(asset.legCenters) else { return nil }
        let frameMorphs: FrameMorphs?
        if resource == "female_body_40k", asset.anatomy != nil {
            guard let morphURL = Bundle.main.url(forResource: "female_body_frame_presets", withExtension: "json"),
                  let morphData = try? Data(contentsOf: morphURL),
                  let decoded = try? JSONDecoder().decode(FrameMorphs.self, from: morphData),
                  decoded.version == 1, decoded.vertexCount == asset.vertices.count,
                  decoded.sourceSHA256 == SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined(),
                  Set(decoded.presets.keys) == Set(FemaleBodyFramePreset.allCases.filter { $0 != .neutral }.map(\.rawValue)),
                  decoded.presets.values.allSatisfy({ $0.count == asset.vertices.count && $0.allSatisfy(Self.finite) }),
                  Set(decoded.breastPresets.keys) == Set(["small", "neutral", "large"]),
                  decoded.breastPresets.values.allSatisfy({ $0.count == asset.vertices.count && $0.allSatisfy(Self.finite) }) else {
                return nil
            }
            frameMorphs = decoded
        } else {
            frameMorphs = nil
        }
        let landmarks = asset.landmarks
        let heights = [Float(0), landmarks.inseam, landmarks.hipHeight, landmarks.waistHeight,
                       landmarks.chestHeight, landmarks.shoulderHeight, landmarks.height]
        guard heights.allSatisfy(\.isFinite), zip(heights, heights.dropFirst()).allSatisfy({ $0 < $1 }),
              landmarks.shoulderWidth.isFinite, landmarks.shoulderWidth > 0 else { return nil }
        let faces = asset.regions.indices.map { index in
            ParametricBody.Face(indices: (0..<3).map { Int(asset.indices[index * 3 + $0]) }, region: asset.regions[index])
        }
        let topology = ParametricBody(vertices: [], faces: faces)
        let sections = [landmarks.hipHeight, landmarks.waistHeight, landmarks.chestHeight].compactMap {
            topology.section(at: $0, positions: asset.vertices, convex: true)
        }
        guard sections.count == 3, sections.allSatisfy(\.isValid) else { return nil }
        var weights = asset.armWeights
        for _ in 0..<12 {
            var sums = Array(repeating: Float(0), count: weights.count)
            var counts = Array(repeating: Float(0), count: weights.count)
            for face in faces {
                for corner in 0..<3 {
                    let index = face.indices[corner]
                    sums[index] += weights[face.indices[(corner + 1) % 3]] + weights[face.indices[(corner + 2) % 3]]
                    counts[index] += 2
                }
            }
            weights = weights.indices.map { counts[$0] > 0 ? (weights[$0] + sums[$0] / counts[$0]) * 0.5 : weights[$0] }
        }
        let armWidths = [landmarks.hipHeight, landmarks.waistHeight].map {
            topology.section(at: $0, positions: asset.vertices, region: 1, convex: true)?.halfWidth ?? 0
        }
        var neighbors = Array(repeating: Set<Int>(), count: asset.vertices.count)
        for face in faces {
            for corner in 0..<3 {
                neighbors[face.indices[corner]].insert(face.indices[(corner + 1) % 3])
                neighbors[face.indices[corner]].insert(face.indices[(corner + 2) % 3])
            }
        }
        return Self(asset: asset, frameMorphs: frameMorphs, topology: topology, referenceSections: sections,
                    referenceArmWidths: armWidths, deformationWeights: weights,
                    neighbors: neighbors.map { $0.sorted() })
    }

    func fitted(to measurements: ParametricBody.Measurements, footLength: Float? = nil,
                partScales: [String: Double] = [:], includeGarmentFit: Bool = true,
                shapeProfile: BodyShapeProfile? = nil) -> Fitted? {
        let values = [measurements.height, measurements.weight, measurements.shoulderWidth, measurements.chest,
                      measurements.waist, measurements.hip, measurements.inseam, measurements.armSize, measurements.legSize]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        var sourceVertices = asset.vertices
        if measurements.feminine, let neutral = frameMorphs?.breastPresets["neutral"] {
            sourceVertices = zip(sourceVertices, neutral).map { $0 + $1 }
            if let shapeProfile, shapeProfile.framePreset != .neutral {
                if let offsets = frameMorphs?.presets[shapeProfile.framePreset.rawValue] {
                    sourceVertices = zip(sourceVertices, offsets).map { $0 + $1 }
                }
            }
        }
        let landmarks = asset.landmarks
        let stature = measurements.height / landmarks.height
        let shoulderHeight = landmarks.shoulderHeight * stature
        let inseam = min(measurements.inseam, shoulderHeight - 0.15)
        guard inseam > 0 else { return nil }
        var footScale = stature
        if let footLength {
            guard footLength.isFinite, footLength > 0 else { return nil }
            let feet = asset.vertices.filter { $0.y <= landmarks.height * 0.04 }
            guard let front = feet.map(\.z).max(), let back = feet.map(\.z).min(), front > back else { return nil }
            footScale = footLength / (front - back)
        }
        let volume: Float = shapeProfile == nil ? 1 + min(max((measurements.weight - 70) / 30, -1), 1) * 0.06 : 1
        let armScale = stature * measurements.armSize * volume
        let shoulderShift = (measurements.shoulderWidth - landmarks.shoulderWidth * stature) * 0.5
        let heights = [landmarks.hipHeight, landmarks.waistHeight, landmarks.chestHeight]
        let targets = [measurements.hip, measurements.waist, measurements.chest]
        let reference = shapeProfile?.referenceCircumferences
        let circumferences = reference.map { [$0.x, $0.y, $0.z] } ?? targets
        var scales = zip(circumferences, referenceSections).map { $0 / $1.circumference }
        var positions: [SIMD3<Float>] = []
        var sections: [GarmentFitSection] = []
        let heightKnots: [Float] = [0, landmarks.inseam, landmarks.shoulderHeight, landmarks.height]
        let heightValues: [Float] = [0, inseam, shoulderHeight, measurements.height]
        let spacingKnots: [Float] = [0, landmarks.hipHeight]

        func height(_ source: Float) -> Float {
            Self.interpolate(source, knots: heightKnots, values: heightValues)
        }

        func armCenter(_ source: Float, clearance: Float) -> SIMD3<Float> {
            let center = Self.center(at: source, chain: asset.armCenters)
            let attachment = GarmentFitProfile.smoothBlend(
                (landmarks.shoulderHeight - source) / (landmarks.shoulderHeight - landmarks.chestHeight))
            return [center.x * stature + shoulderShift + clearance * attachment,
                    height(source), center.z * stature]
        }

        var clearance: Float = 0
        let knots = heights + [landmarks.shoulderHeight, landmarks.height * 0.88, landmarks.height]
        let centerDepths = referenceSections.map { $0.center.z }
        let compositionClearance: Float = measurements.feminine
            ? (max(shapeProfile?.fat ?? 0, 0) * 0.03 + max(shapeProfile?.muscle ?? 0, 0) * 0.02) * stature : 0
        for iteration in 0..<3 {
            clearance = measurements.feminine ? max(-shoulderShift, 0) + compositionClearance : 0
            for index in heights.indices.dropLast() {
                guard referenceArmWidths[index] > 0 else { continue }
                let center = armCenter(heights[index], clearance: 0)
                clearance = max(clearance, referenceSections[index].halfWidth * scales[index] + referenceArmWidths[index] * armScale + 0.012 - center.x)
            }
            let widths = scales + [measurements.shoulderWidth / landmarks.shoulderWidth, stature, stature]
            let depths = scales + [stature, stature, stature]
            let spacings: [Float] = [stature, scales[0]]
            positions = sourceVertices.indices.map { index in
                let point = sourceVertices[index]
                let side: Float = abs(point.x) < 0.00001 ? 0 : (point.x < 0 ? -1 : 1)
                let width = Self.interpolate(point.y, knots: knots, values: widths, smooth: true)
                let depth = Self.interpolate(point.y, knots: knots, values: depths, smooth: true)
                let centerDepth = Self.interpolate(point.y, knots: heights, values: centerDepths)
                let trunk = SIMD3<Float>(point.x * width, height(point.y), (point.z - centerDepth) * depth + centerDepth * stature)
                let sourceArm = Self.center(at: point.y, chain: asset.armCenters) * SIMD3<Float>(side, 1, 1)
                var arm = armCenter(point.y, clearance: clearance) * SIMD3<Float>(side, 1, 1)
                arm.x += (point.x - sourceArm.x) * armScale
                arm.z += (point.z - sourceArm.z) * armScale
                let sourceLeg = Self.center(at: point.y, chain: asset.legCenters) * SIMD3<Float>(side, 1, 1)
                let legBlend = GarmentFitProfile.smoothBlend(point.y / (landmarks.height * 0.12))
                let legRadius = stature * (1 + (measurements.legSize * volume - 1) * legBlend)
                let footBlend: Float = footLength == nil ? 0 : 1 - GarmentFitProfile.smoothBlend(
                    (point.y - landmarks.height * 0.04) / (landmarks.height * 0.025))
                let legDepth = legRadius + (footScale - legRadius) * footBlend
                let spacing = Self.interpolate(point.y, knots: spacingKnots, values: spacings, smooth: true)
                let innerLegBlend = GarmentFitProfile.smoothBlend(abs(point.x) / (landmarks.height * 0.02))
                let legX = measurements.feminine
                    ? point.x * legRadius + sourceLeg.x * (spacing - legRadius) * innerLegBlend
                    : (point.x - sourceLeg.x) * legRadius + sourceLeg.x * spacing
                let leg = SIMD3<Float>(legX,
                                      height(point.y), (point.z - sourceLeg.z) * legDepth + sourceLeg.z * stature)
                let armWeight = deformationWeights[index]
                let legWeight = (1 - armWeight) * (1 - GarmentFitProfile.smoothBlend(
                    (point.y - landmarks.inseam) / (landmarks.hipHeight - landmarks.inseam)))
                return trunk * (1 - armWeight - legWeight) + arm * armWeight + leg * legWeight
            }
            guard positions.allSatisfy(Self.finite) else { return nil }
            sections = heights.compactMap { topology.section(at: height($0), positions: positions, convex: true) }
            guard sections.count == 3, sections.allSatisfy(\.isValid) else { return nil }
            if iteration < 2 {
                for index in scales.indices { scales[index] *= circumferences[index] / sections[index].circumference }
            }
        }
        if let shapeProfile, let anatomy = asset.anatomy,
              shapeProfile.feminine || shapeProfile.fat != 0 || shapeProfile.muscle != 0
            || shapeProfile.framePreset != .neutral
            || zip(targets, circumferences).contains(where: { abs($0 - $1) > 0.000001 }) {
            let source = positions
            let shaped = anatomy.prepareDeformation(in: source).vertices(profile: shapeProfile)
            positions = smoothDisplacements(shaped, from: source)
            let sectionHeights = heights.map(height)
            for _ in 0..<3 {
                sections = sectionHeights.compactMap { topology.section(at: $0, positions: positions, convex: true) }
                guard sections.count == 3, sections.allSatisfy(\.isValid) else { return nil }
                let ratios = zip(targets, sections).map { $0 / $1.circumference }
                if ratios.allSatisfy({ abs($0 - 1) < 0.0001 }) { break }
                let depths = sections.map { $0.center.z }
                positions = positions.indices.map { index in
                    let point = positions[index]
                    let lower = GarmentFitProfile.smoothBlend((point.y - inseam) / max(sectionHeights[0] - inseam, 0.01))
                    let upper = 1 - GarmentFitProfile.smoothBlend((point.y - sectionHeights[2]) / max(shoulderHeight - sectionHeights[2], 0.01))
                    let influence = (1 - deformationWeights[index]) * lower * upper
                    let ratio = Self.interpolate(point.y, knots: sectionHeights, values: ratios, smooth: true)
                    let scale = 1 + (ratio - 1) * influence
                    let depth = Self.interpolate(point.y, knots: sectionHeights, values: depths, smooth: true)
                    return SIMD3<Float>(point.x * scale, point.y, depth + (point.z - depth) * scale)
                }
            }
            positions = stabilizeProfile(positions, from: source)
            guard positions.allSatisfy(Self.finite) else { return nil }
            sections = sectionHeights.compactMap { topology.section(at: $0, positions: positions, convex: true) }
            guard sections.count == 3, sections.allSatisfy(\.isValid) else { return nil }
        }
        if !partScales.isEmpty, let deformation = prepareDeformation(in: positions, feminine: measurements.feminine) {
            positions = deformation.vertices(scales: partScales)
            guard positions.allSatisfy(Self.finite) else { return nil }
            sections = heights.compactMap { topology.section(at: height($0), positions: positions, convex: true) }
            guard sections.count == 3, sections.allSatisfy(\.isValid) else { return nil }
        }
        let anchor = SIMD3<Float>(0, shoulderHeight + 0.075 * stature, 0)
        let arm = asset.armCenters.map { armCenter($0.y, clearance: clearance) - anchor }
        let fitTopology = includeGarmentFit
            ? garmentTopology(positions: positions,
                              below: height(landmarks.chestHeight) + (shoulderHeight - height(landmarks.chestHeight)) * 0.5)
            : topology
        let lowerArm = height(asset.armCenters[0].y)
        let upperArm = height(landmarks.chestHeight + 0.02)
        let armSections: [GarmentFitSection] = includeGarmentFit ? (0...20).compactMap { step in
            fitTopology.section(at: lowerArm + (upperArm - lowerArm) * Float(step) / 20,
                                positions: positions, region: 1, convex: true)?.translated(by: -anchor)
        } : []
        let handPoints = asset.anatomy?.parts["rightHand"]?.indices.map { positions[Int($0)] } ?? []
        let handFloor = handPoints.map(\.y).min()
        let posedLandmarks = asset.anatomy?.landmarkPositions(in: positions) ?? [:]
        let wristHeight = posedLandmarks[.rightWrist]?.y ?? lowerArm
        let wristSection = includeGarmentFit
            ? fitTopology.section(at: wristHeight, positions: positions, region: 1, convex: true)?.translated(by: -anchor)
            : nil
        let handTop = max(lowerArm, wristHeight)
        let handSections: [GarmentFitSection]
        if includeGarmentFit, let handFloor, handFloor < handTop - 0.02 {
            handSections = (1...8).compactMap { step in
                let level = handTop + (handFloor - handTop) * Float(step) / 9
                // Separate finger loops must contribute to one whole-hand envelope.
                let band = handPoints.filter { abs($0.y - level) < 0.01 }
                guard let first = band.first else { return nil }
                let minimum = band.reduce(first) { simd_min($0, $1) }
                let maximum = band.reduce(first) { simd_max($0, $1) }
                let width = (maximum.x - minimum.x) * 0.5
                let depth = (maximum.z - minimum.z) * 0.5
                guard width > 0.0001, depth > 0.0001 else { return nil }
                let center = SIMD3<Float>((minimum.x + maximum.x) * 0.5, level, (minimum.z + maximum.z) * 0.5)
                return GarmentFitSection(center: center, halfWidth: width, halfDepth: depth,
                    circumference: GarmentFitSection.ellipseCircumference(halfWidth: width, halfDepth: depth))
                    .translated(by: -anchor)
            }
        } else {
            handSections = []
        }
        func legSections(region: Int) -> [GarmentFitSection] {
            guard includeGarmentFit else { return [] }
            return (0...20).compactMap { step in
                let level = 0.10 * stature + (inseam - 0.015 - 0.10 * stature) * Float(step) / 20
                return fitTopology.section(at: level, positions: positions, region: region, convex: true)?.translated(by: -anchor)
            }
        }
        func footBounds(side: Float) -> GarmentFootBounds? {
            guard let heel = posedLandmarks[side > 0 ? .rightHeel : .leftHeel],
                  let toe = posedLandmarks[side > 0 ? .rightToe : .leftToe] else { return nil }
            let axis = SIMD3<Float>(toe.x - heel.x, 0, toe.z - heel.z)
            guard simd_length_squared(axis) > 1e-8 else { return nil }
            let forward = simd_normalize(axis)
            let across = SIMD3<Float>(forward.z, 0, -forward.x)
            let binding = asset.anatomy?.parts[side > 0 ? "rightFoot" : "leftFoot"]
            let candidates = binding?.indices.map { Int($0) } ?? positions.indices.filter { positions[$0].x * side > 0 }
            let points = candidates.map { positions[$0] }.filter { $0.y < 0.09 * stature }
            guard let first = points.first else { return nil }
            let minimum = points.reduce(first) { simd_min($0, $1) }
            let maximum = points.reduce(first) { simd_max($0, $1) }
            let along = points.map { simd_dot($0, forward) }
            let lateral = points.map { simd_dot($0, across) }
            guard let front = along.max(), let back = along.min(), front > back,
                  let outer = lateral.max(), let inner = lateral.min(), outer > inner else { return nil }
            let center = forward * ((front + back) * 0.5) + across * ((outer + inner) * 0.5)
                + SIMD3<Float>(0, (minimum.y + maximum.y) * 0.5, 0)
            return .init(center: center - anchor, length: front - back,
                         width: outer - inner, floor: minimum.y - anchor.y, forward: forward)
        }
        let shoulderPoint = measurements.shoulderWidth * 0.5
        // The shoulder landmark sits below the deltoid top; garments rest on the surface itself.
        let shoulderTop = positions.filter {
            abs(abs($0.x) - shoulderPoint) < 0.015 && $0.y > shoulderHeight - 0.05 && $0.y < shoulderHeight + 0.08
        }.map(\.y).max() ?? shoulderHeight
        let profile = GarmentBodyFitProfile(chest: sections[2].translated(by: -anchor),
            waist: sections[1].translated(by: -anchor), hip: sections[0].translated(by: -anchor),
            shoulderWidth: measurements.shoulderWidth, shoulderHeight: shoulderTop - anchor.y,
            rightArm: arm, rightArmSections: armSections, rightHandSections: handSections, rightWrist: wristSection,
            rightLegSections: legSections(region: 3),
            leftLegSections: legSections(region: 4),
            rightFoot: includeGarmentFit ? footBounds(side: 1) : nil,
            leftFoot: includeGarmentFit ? footBounds(side: -1) : nil,
            inseamHeight: inseam - anchor.y)
        return Fitted(surface: BodySurfaceMesh(vertices: positions, indices: asset.indices), profile: profile,
                      collisionMesh: includeGarmentFit ? fitTopology.collisionMesh(positions: positions, anchor: anchor) : nil,
                      anchor: anchor, anatomy: asset.anatomy,
                      landmarks: includeGarmentFit ? posedLandmarks : [:])
    }

    private static func finite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }

    // Armpit surface fused to the torso is labelled arm; treating it as torso keeps arm collision and sections to the arm itself.
    private func garmentTopology(positions: [SIMD3<Float>], below limit: Float) -> ParametricBody {
        func level(_ index: Int) -> Int { Int(floor(positions[index].y / 0.035)) }
        var outer: [Int: Float] = [:]
        for face in topology.faces where face.region == 1 || face.region == 2 {
            for index in face.indices {
                outer[level(index)] = max(outer[level(index)] ?? 0, abs(positions[index].x))
            }
        }
        var depth: [Int: (Float, Float)] = [:]
        for face in topology.faces where face.region == 1 || face.region == 2 {
            for index in face.indices {
                let point = positions[index]
                guard let edge = outer[level(index)], abs(point.x) > edge - 0.06 else { continue }
                let range = depth[level(index)] ?? (point.z, point.z)
                depth[level(index)] = (min(range.0, point.z), max(range.1, point.z))
            }
        }
        return ParametricBody(vertices: [], faces: topology.faces.map { face in
            guard face.region == 1 || face.region == 2 else { return face }
            let isArm = face.indices.allSatisfy { index in
                let point = positions[index]
                guard point.y < limit, let edge = outer[level(index)], let range = depth[level(index)] else { return true }
                let radius = (range.1 - range.0) * 0.5
                let center = SIMD2<Float>(edge - radius, (range.0 + range.1) * 0.5)
                return simd_distance(SIMD2<Float>(abs(point.x), point.z), center) <= radius * 1.2
            }
            return isArm ? face : ParametricBody.Face(indices: face.indices, region: 0)
        })
    }

    func prepareDeformation(in positions: [SIMD3<Float>], feminine: Bool) -> BodyAnatomy.Deformation? {
        guard let anatomy = asset.anatomy, positions.count == asset.vertices.count else { return nil }
        var breastMorphs: BodyAnatomy.BreastMorphs?
        if feminine, let presets = frameMorphs?.breastPresets,
           let neutral = presets["neutral"], let small = presets["small"], let large = presets["large"] {
            let parts: [BodyAnatomy.Part] = [.chest, .leftChestVolume, .rightChestVolume, .upperBack]
            var sourceCenter = SIMD3<Float>.zero
            var fittedCenter = SIMD3<Float>.zero
            var total: Float = 0
            for part in parts {
                guard let binding = anatomy.binding(for: part) else { continue }
                for (index, weight) in zip(binding.indices, binding.weights) {
                    sourceCenter += (asset.vertices[Int(index)] + neutral[Int(index)]) * weight
                    fittedCenter += positions[Int(index)] * weight
                    total += weight
                }
            }
            guard total > 0 else { return nil }
            sourceCenter /= total
            fittedCenter /= total
            var sourceVariance = SIMD3<Float>.zero
            var fittedVariance = SIMD3<Float>.zero
            for part in parts {
                guard let binding = anatomy.binding(for: part) else { continue }
                for (index, weight) in zip(binding.indices, binding.weights) {
                    let source = asset.vertices[Int(index)] + neutral[Int(index)] - sourceCenter
                    let fitted = positions[Int(index)] - fittedCenter
                    sourceVariance += source * source * weight
                    fittedVariance += fitted * fitted * weight
                }
            }
            let scale = SIMD3<Float>(
                sqrt(max(fittedVariance.x, 1e-10) / max(sourceVariance.x, 1e-10)),
                sqrt(max(fittedVariance.y, 1e-10) / max(sourceVariance.y, 1e-10)),
                sqrt(max(fittedVariance.z, 1e-10) / max(sourceVariance.z, 1e-10)))
            guard Self.finite(scale) else { return nil }
            breastMorphs = BodyAnatomy.BreastMorphs(
                small: zip(small, neutral).map { ($0 - $1) * scale },
                large: zip(large, neutral).map { ($0 - $1) * scale })
        }
        return anatomy.prepareDeformation(in: positions, feminine: feminine, breastMorphs: breastMorphs)
    }

    private func smoothDisplacements(_ positions: [SIMD3<Float>], from source: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var offsets = zip(positions, source).map { $0 - $1 }
        for _ in 0..<18 {
            offsets = offsets.indices.map { index in
                guard !neighbors[index].isEmpty else { return offsets[index] }
                let average = neighbors[index].reduce(SIMD3<Float>.zero) { $0 + offsets[$1] } / Float(neighbors[index].count)
                return offsets[index] * 0.45 + average * 0.55
            }
        }
        return source.indices.map { index in
            var result = source[index] + offsets[index]
            if abs(source[index].x) < 0.00001 { result.x = source[index].x }
            return result
        }
    }

    private func stabilizeProfile(_ positions: [SIMD3<Float>], from source: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let triangles = stride(from: 0, to: asset.indices.count, by: 3).map { offset in
            (Int(asset.indices[offset]), Int(asset.indices[offset + 1]), Int(asset.indices[offset + 2]))
        }
        let normals = triangles.map { first, second, third in
            simd_cross(source[second] - source[first], source[third] - source[first])
        }
        var result = positions
        for _ in 0..<32 {
            var corrections = Array(repeating: SIMD3<Float>.zero, count: source.count)
            var counts = Array(repeating: Float(0), count: source.count)
            var conflicts = 0
            for index in triangles.indices {
                let (first, second, third) = triangles[index]
                let area = simd_length(normals[index])
                guard area > 1e-12 else { continue }
                let normal = normals[index] / area
                let edge = result[second] - result[first]
                let other = result[third] - result[first]
                let deficit = area * 0.10 - simd_dot(simd_cross(edge, other), normal)
                guard deficit > 0 else { continue }
                var gradients = [simd_cross(result[second] - result[third], normal),
                                 simd_cross(other, normal), simd_cross(normal, edge)]
                let corners = [first, second, third]
                for corner in 0..<3 {
                    gradients[corner].y = 0
                    if abs(source[corners[corner]].x) < 0.00001 { gradients[corner].x = 0 }
                }
                let denominator = gradients.reduce(Float(0)) { $0 + simd_length_squared($1) }
                guard denominator > 1e-16 else { continue }
                for corner in 0..<3 {
                    let correction = gradients[corner] * (deficit / denominator)
                    let magnitude = simd_length(correction)
                    corrections[corners[corner]] += correction * min(1, 0.004 / max(magnitude, 1e-12))
                    counts[corners[corner]] += 1
                }
                conflicts += 1
            }
            if conflicts == 0 { break }
            for index in result.indices where counts[index] > 0 {
                result[index] += corrections[index] / counts[index]
            }
        }
        return result
    }

    private static func validChain(_ points: [SIMD3<Float>]) -> Bool {
        points.count >= 2 && points.allSatisfy(finite)
            && zip(points, points.dropFirst()).allSatisfy { $0.y < $1.y }
    }

    private static func center(at height: Float, chain: [SIMD3<Float>]) -> SIMD3<Float> {
        guard height > chain[0].y else { return chain[0] }
        guard let upper = chain.indices.dropFirst().first(where: { height <= chain[$0].y }) else { return chain[chain.count - 1] }
        let lower = chain[upper - 1]
        return lower + (chain[upper] - lower) * ((height - lower.y) / (chain[upper].y - lower.y))
    }

    private static func interpolate(_ value: Float, knots: [Float], values: [Float], smooth: Bool = false) -> Float {
        guard value > knots[0] else { return values[0] }
        guard let upper = knots.indices.dropFirst().first(where: { value <= knots[$0] }) else { return values[values.count - 1] }
        let fraction = (value - knots[upper - 1]) / (knots[upper] - knots[upper - 1])
        let blend = smooth ? GarmentFitProfile.smoothBlend(fraction) : fraction
        return values[upper - 1] + (values[upper] - values[upper - 1]) * blend
    }
}