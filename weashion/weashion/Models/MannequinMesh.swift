import Foundation
import simd

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
    }

    nonisolated struct Fitted {
        let surface: BodySurfaceMesh
        let profile: GarmentBodyFitProfile
        let collisionBands: [GarmentCollisionBand]
        let anchor: SIMD3<Float>
    }

    private let asset: Asset
    private let topology: ParametricBody
    private let referenceSections: [GarmentFitSection]
    private let deformationWeights: [Float]

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
              validChain(asset.armCenters), validChain(asset.legCenters) else { return nil }
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
        return Self(asset: asset, topology: topology, referenceSections: sections, deformationWeights: weights)
    }

    func fitted(to measurements: ParametricBody.Measurements) -> Fitted? {
        let values = [measurements.height, measurements.weight, measurements.shoulderWidth, measurements.chest,
                      measurements.waist, measurements.hip, measurements.inseam, measurements.armSize, measurements.legSize]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let landmarks = asset.landmarks
        let stature = measurements.height / landmarks.height
        let shoulderHeight = landmarks.shoulderHeight * stature
        let inseam = min(measurements.inseam, shoulderHeight - 0.15)
        guard inseam > 0 else { return nil }
        let volume = 1 + min(max((measurements.weight - 70) / 30, -1), 1) * 0.06
        let armScale = stature * measurements.armSize * volume
        let shoulderShift = (measurements.shoulderWidth - landmarks.shoulderWidth * stature) * 0.5
        let heights = [landmarks.hipHeight, landmarks.waistHeight, landmarks.chestHeight]
        let circumferences = [measurements.hip, measurements.waist, measurements.chest]
        var scales = zip(circumferences, referenceSections).map { $0 / $1.circumference }
        var positions: [SIMD3<Float>] = []
        var sections: [GarmentFitSection] = []

        func height(_ source: Float) -> Float {
            Self.interpolate(source, knots: [0, landmarks.inseam, landmarks.shoulderHeight, landmarks.height],
                             values: [0, inseam, shoulderHeight, measurements.height])
        }

        func armCenter(_ source: Float, clearance: Float) -> SIMD3<Float> {
            let center = Self.center(at: source, chain: asset.armCenters)
            let attachment = GarmentFitProfile.smoothBlend(
                (landmarks.shoulderHeight - source) / (landmarks.shoulderHeight - landmarks.chestHeight))
            return [center.x * stature + shoulderShift + clearance * attachment,
                    height(source), center.z * stature]
        }

        var clearance: Float = 0
        for iteration in 0..<3 {
            clearance = 0
            for index in heights.indices.dropLast() {
                guard let arm = topology.section(at: heights[index], positions: asset.vertices, region: 1, convex: true) else { continue }
                let center = armCenter(heights[index], clearance: 0)
                clearance = max(clearance, referenceSections[index].halfWidth * scales[index] + arm.halfWidth * armScale + 0.012 - center.x)
            }
            positions = asset.vertices.indices.map { index in
                let point = asset.vertices[index]
                let side: Float = point.x < 0 ? -1 : 1
                let knots = heights + [landmarks.shoulderHeight, landmarks.height * 0.88, landmarks.height]
                let width = Self.interpolate(point.y, knots: knots,
                    values: scales + [measurements.shoulderWidth / landmarks.shoulderWidth, stature, stature], smooth: true)
                let depth = Self.interpolate(point.y, knots: knots, values: scales + [stature, stature, stature], smooth: true)
                let centerDepth = Self.interpolate(point.y, knots: heights, values: referenceSections.map { $0.center.z })
                let trunk = SIMD3<Float>(point.x * width, height(point.y), (point.z - centerDepth) * depth + centerDepth * stature)
                let sourceArm = Self.center(at: point.y, chain: asset.armCenters) * SIMD3<Float>(side, 1, 1)
                var arm = armCenter(point.y, clearance: clearance) * SIMD3<Float>(side, 1, 1)
                arm.x += (point.x - sourceArm.x) * armScale
                arm.z += (point.z - sourceArm.z) * armScale
                let sourceLeg = Self.center(at: point.y, chain: asset.legCenters) * SIMD3<Float>(side, 1, 1)
                let legBlend = GarmentFitProfile.smoothBlend(point.y / (landmarks.height * 0.12))
                let legRadius = stature * (1 + (measurements.legSize * volume - 1) * legBlend)
                let spacing = Self.interpolate(point.y, knots: [0, landmarks.hipHeight], values: [stature, scales[0]], smooth: true)
                let leg = SIMD3<Float>((point.x - sourceLeg.x) * legRadius + sourceLeg.x * spacing,
                                      height(point.y), (point.z - sourceLeg.z) * legRadius + sourceLeg.z * stature)
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
        let anchor = SIMD3<Float>(0, shoulderHeight + 0.075 * stature, 0)
        let arm = asset.armCenters.map { armCenter($0.y, clearance: clearance) - anchor }
        let lowerArm = height(asset.armCenters[0].y)
        let upperArm = height(landmarks.chestHeight + 0.02)
        let armSections = (0...20).compactMap { step in
            topology.section(at: lowerArm + (upperArm - lowerArm) * Float(step) / 20,
                             positions: positions, region: 1, convex: true)?.translated(by: -anchor)
        }
        let profile = GarmentBodyFitProfile(chest: sections[2].translated(by: -anchor),
            waist: sections[1].translated(by: -anchor), hip: sections[0].translated(by: -anchor),
            shoulderWidth: measurements.shoulderWidth, shoulderHeight: shoulderHeight - anchor.y,
            rightArm: arm, rightArmSections: armSections)
        return Fitted(surface: BodySurfaceMesh(vertices: positions, indices: asset.indices), profile: profile,
                      collisionBands: topology.collisionBands(positions: positions, anchor: anchor), anchor: anchor)
    }

    private static func finite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
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