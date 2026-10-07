import simd

nonisolated struct ParametricBody {
    nonisolated struct Vertex {
        var position: SIMD3<Float> = .zero
        var feminine: SIMD3<Float> = .zero
        var weights: SIMD4<Float> = .zero
           var anatomy: SIMD3<Float> = .zero
           var feminineAnatomy: SIMD3<Float> = .zero

        static func + (left: Self, right: Self) -> Self {
            Self(position: left.position + right.position, feminine: left.feminine + right.feminine,
                  weights: left.weights + right.weights, anatomy: left.anatomy + right.anatomy,
                  feminineAnatomy: left.feminineAnatomy + right.feminineAnatomy)
        }

        static func * (value: Self, scale: Float) -> Self {
              Self(position: value.position * scale, feminine: value.feminine * scale, weights: value.weights * scale,
                  anatomy: value.anatomy * scale, feminineAnatomy: value.feminineAnatomy * scale)
        }
    }

    nonisolated struct Face {
        let indices: [Int]
        let region: Int
    }

    nonisolated struct Edge: Hashable {
        let first: Int
        let second: Int

        init(_ first: Int, _ second: Int) {
            self.first = min(first, second)
            self.second = max(first, second)
        }
    }

    var vertices: [Vertex] = []
    var faces: [Face] = []

    nonisolated struct Finger {
        let offset: Float
        let length: Float
        let radius: Float
        let rootHeight: Float
        let curl: Float
    }

    static let fingers: [Finger] = [
        Finger(offset: -0.025, length: 0.067, radius: 0.0085, rootHeight: 0.001, curl: 0.008),
        Finger(offset: -0.007, length: 0.078, radius: 0.0090, rootHeight: -0.004, curl: 0.012),
        Finger(offset: 0.011, length: 0.073, radius: 0.0085, rootHeight: 0, curl: 0.017),
        Finger(offset: 0.027, length: 0.055, radius: 0.0070, rootHeight: 0.010, curl: 0.020)
    ]

    nonisolated struct Toe {
        let offset: Float
        let base: Float
        let length: Float
        let radius: Float
    }

    static let toeBaseHeight: Float = 0.022
    static let toes: [Toe] = [
        Toe(offset: -0.030, base: 0.116, length: 0.062, radius: 0.013),
        Toe(offset: -0.007, base: 0.120, length: 0.053, radius: 0.0095),
        Toe(offset: 0.010, base: 0.114, length: 0.047, radius: 0.0085),
        Toe(offset: 0.025, base: 0.104, length: 0.039, radius: 0.0075),
        Toe(offset: 0.037, base: 0.095, length: 0.031, radius: 0.0065)
    ]

    nonisolated struct Measurements {
        let height: Float
        let weight: Float
        let shoulderWidth: Float
        let chest: Float
        let waist: Float
        let hip: Float
        let inseam: Float
        let armSize: Float
        let legSize: Float
        let feminine: Bool
    }

    nonisolated struct Fitted {
        let positions: [SIMD3<Float>]
        let indices: [UInt32]
        let collisionBands: [GarmentCollisionBand]
        let profile: GarmentBodyFitProfile
        let anchor: SIMD3<Float>
        let headHeight: Float
        let handScale: Float
        let footScale: Float
        let skeleton: BodySkeleton
    }

    func fitted(to measurements: Measurements) -> Fitted? {
        let rig = Rig(measurements: measurements)
        let crotch = vertices.filter { abs($0.position.x) < 0.00001 && (0.75...0.92).contains($0.position.y) }
            .map { $0.position.y }.min() ?? 0.82
        let floor = vertices.filter { $0.weights.w > 0.99 }.map { $0.position.y }.min() ?? 0
        let referenceHeights: [Float] = [0, 0.14, 0.465, crotch, 0.94, 1.105, 1.285, 1.43, 1.532, 1.565]
        let targetHeights: [Float] = [0, 0.14 * rig.footScale, rig.kneeHeight, measurements.inseam,
                                      rig.hipHeight, rig.waistHeight, rig.chestHeight, rig.shoulderHeight,
                                      rig.headHeight, rig.headHeight + 0.033]
        var scales = SIMD3<Float>(repeating: 1)
        var positions: [SIMD3<Float>] = []
        var sections: [GarmentFitSection] = []
        var clearance: Float = max(measurements.waist, measurements.hip) / (2 * .pi)
        let handRotation: Float = -0.90
        let footRotation: Float = 0.09
        let torsoDetail = min(max((rig.shoulderHeight - measurements.inseam) / 0.61, 0.25), 1)
        var skeleton = rig.skeleton(clearance: clearance, floor: floor,
                        handRotation: handRotation, footRotation: footRotation)

        func deform(_ vertex: Vertex) -> SIMD3<Float> {
            let feminine: Float = measurements.feminine ? 1 : 0
            let detail = vertex.anatomy + vertex.feminineAnatomy * feminine
            let point = vertex.position + vertex.feminine * feminine - detail * ((1 - torsoDetail) * vertex.weights.x)
            let side: Float = point.x < 0 ? -1 : 1
            let widthScale = Self.interpolate(point.y, knots: [0.80, 0.94, 1.105, 1.285, 1.43, 1.52],
                                               values: [scales.x, scales.x, scales.y, scales.z, measurements.shoulderWidth / 0.45, 1])
            let depthScale = Self.interpolate(point.y, knots: [0.80, 0.94, 1.105, 1.285, 1.43, 1.52],
                                               values: [scales.x, scales.x, scales.y, scales.z, 1, 1])
            let right = side > 0
            let trunkBinding = BodySkeleton.chain([.pelvis, .lumbar, .chest, .neck, .head],
                heights: [1.105, 1.285, 1.477, 1.532], at: point.y, transition: 0.025)
            var trunk = skeleton.deform([point.x * widthScale, point.y, point.z * depthScale], influences: trunkBinding)
            if point.y < 0.94 {
                trunk.y = Self.interpolate(point.y, knots: referenceHeights, values: targetHeights)
            }
            let armRadius = Self.interpolate(point.y, knots: [0.80, 0.88, 1.02, 1.125, 1.25, 1.43],
                                              values: [rig.handScale, rig.handScale * pow(rig.armScale, 0.25), rig.armScale,
                                                       sqrt(rig.armScale), rig.armScale, rig.armScale])
            let armBinding = BodySkeleton.chain(
                right ? [.rightWrist, .rightElbow, .rightShoulder, .rightClavicle]
                    : [.leftWrist, .leftElbow, .leftShoulder, .leftClavicle],
                heights: [0.935, 1.125, 1.425], at: point.y, transition: 0.045)
            let arm = vertex.weights.y > 0 ? skeleton.deform(point, influences: armBinding, radialScale: armRadius) : point
            let legRadius = Self.interpolate(point.y, knots: [0.14, 0.30, 0.465, 0.655, 0.82],
                                              values: [rig.footScale * pow(rig.legScale, 0.25), rig.legScale,
                                                       sqrt(rig.legScale), rig.legScale, rig.legScale])
            let legBinding = BodySkeleton.chain(right ? [.rightKnee, .rightHip] : [.leftKnee, .leftHip],
                heights: [0.465], at: point.y, transition: 0.065)
            let leg = vertex.weights.z > 0 ? skeleton.deform(point, influences: legBinding, radialScale: legRadius) : point
            let foot = vertex.weights.w > 0 ? skeleton.deform(point,
                influences: [.init(joint: right ? .rightAnkle : .leftAnkle, weight: 1)], radialScale: rig.footScale) : point
            return trunk * vertex.weights.x + arm * vertex.weights.y + leg * vertex.weights.z + foot * vertex.weights.w
        }

        for iteration in 0..<5 {
            skeleton = rig.skeleton(clearance: clearance, floor: floor,
                                    handRotation: handRotation, footRotation: footRotation)
            positions = vertices.map(deform)
            sections = [rig.hipHeight, rig.waistHeight, rig.chestHeight].compactMap { section(at: $0, positions: positions) }
            guard sections.count == 3, sections.allSatisfy({ $0.isValid }), positions.allSatisfy({
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            }) else { return nil }
            if iteration == 4 { break }
            scales *= SIMD3<Float>(measurements.hip / sections[0].circumference,
                                    measurements.waist / sections[1].circumference,
                                    measurements.chest / sections[2].circumference)
            clearance = max(sections[0].halfWidth, sections[1].halfWidth)
        }
        let anchor = SIMD3<Float>(0, rig.shoulderHeight + 0.075, 0)
        let arm = [Float(0.88), 1.02, 1.125, 1.245, 1.34, 1.43].map {
            rig.armCenter(at: $0, clearance: clearance) - anchor
        }
        let lowerArmHeight = rig.armCenter(at: 1.02, clearance: clearance).y
        let armSections = (0...20).compactMap { step in
            section(at: lowerArmHeight + (rig.chestHeight + 0.04 - lowerArmHeight) * Float(step) / 20,
                    positions: positions, region: 1)?.translated(by: -anchor)
        }
        let profile = GarmentBodyFitProfile(chest: sections[2].translated(by: -anchor),
                                            waist: sections[1].translated(by: -anchor), hip: sections[0].translated(by: -anchor),
                                            shoulderWidth: measurements.shoulderWidth,
                                            shoulderHeight: rig.shoulderHeight - anchor.y, rightArm: arm,
                                            rightArmSections: armSections)
        return Fitted(positions: positions, indices: triangleIndices,
                      collisionBands: collisionBands(positions: positions, anchor: anchor), profile: profile, anchor: anchor,
                      headHeight: rig.headHeight, handScale: rig.handScale, footScale: rig.footScale, skeleton: skeleton)
    }

    private var triangleIndices: [UInt32] {
        faces.flatMap { face in
            (1..<(face.indices.count - 1)).flatMap { corner in
                [UInt32(face.indices[0]), UInt32(face.indices[corner]), UInt32(face.indices[corner + 1])]
            }
        }
    }

    func section(at height: Float, positions: [SIMD3<Float>], region: Int = 0, convex: Bool = false) -> GarmentFitSection? {
        var crossings: [Edge: SIMD3<Float>] = [:]
        for face in faces where face.region == region {
            for corner in 1..<(face.indices.count - 1) {
                let triangle = [face.indices[0], face.indices[corner], face.indices[corner + 1]]
                for edgeIndex in 0..<3 {
                    let firstIndex = triangle[edgeIndex]
                    let secondIndex = triangle[(edgeIndex + 1) % 3]
                    let first = positions[firstIndex]
                    let second = positions[secondIndex]
                    guard (first.y < height) != (second.y < height) else { continue }
                    let fraction = (height - first.y) / (second.y - first.y)
                    crossings[Edge(firstIndex, secondIndex)] = first + (second - first) * fraction
                }
            }
        }
        guard crossings.count >= 8 else { return nil }
        if convex {
            let points = crossings.values.sorted { $0.x == $1.x ? $0.z < $1.z : $0.x < $1.x }
            func turn(_ first: SIMD3<Float>, _ second: SIMD3<Float>, _ third: SIMD3<Float>) -> Float {
                (second.x - first.x) * (third.z - first.z) - (second.z - first.z) * (third.x - first.x)
            }
            func chain(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
                var result: [SIMD3<Float>] = []
                for point in points {
                    while result.count >= 2 && turn(result[result.count - 2], result[result.count - 1], point) <= 0 {
                        result.removeLast()
                    }
                    result.append(point)
                }
                return result
            }
            let loop = Array(chain(points).dropLast()) + Array(chain(Array(points.reversed())).dropLast())
            guard loop.count >= 3 else { return nil }
            return GarmentFitSection(vertices: loop)
        }
        let center = crossings.values.reduce(SIMD3<Float>.zero, +) / Float(crossings.count)
        let loop = crossings.values.sorted {
            atan2($0.z - center.z, $0.x - center.x) < atan2($1.z - center.z, $1.x - center.x)
        }
        return GarmentFitSection(vertices: loop)
    }

    func collisionBands(positions: [SIMD3<Float>], anchor: SIMD3<Float>) -> [GarmentCollisionBand] {
        var bands: [Int: Set<Int>] = [:]
        for face in faces {
            let heights = face.indices.map { positions[$0].y }
            let lower = Int(floor((heights.min() ?? 0) / 0.035))
            let upper = Int(floor((heights.max() ?? 0) / 0.035))
            for level in lower...upper {
                bands[face.region * 256 + level, default: []].formUnion(face.indices)
            }
        }
        return bands.keys.sorted().compactMap { key in
            let indices = bands[key]!.sorted()
            guard indices.count >= 4 else { return nil }
            let step = max(1, (indices.count + 511) / 512)
            return GarmentCollisionBand(vertices: stride(from: 0, to: indices.count, by: step).map { positions[indices[$0]] - anchor })
        }
    }

    private static func armCenter(at height: Float) -> SIMD3<Float> {
        let knots: [Float] = [0.768, 0.88, 1.125, 1.43]
        return [interpolate(height, knots: knots, values: [0.271, 0.258, 0.232, 0.190]), height,
                interpolate(height, knots: knots, values: [0.030, 0.023, -0.013, 0])]
    }

    private static func interpolate(_ value: Float, knots: [Float], values: [Float]) -> Float {
        guard value > knots[0] else { return values[0] }
        guard value < knots[knots.count - 1] else { return values[values.count - 1] }
        let upper = (1..<knots.count).first { value <= knots[$0] }!
        let lower = upper - 1
        let distance = knots[upper] - knots[lower]
        let slope = (values[upper] - values[lower]) / distance
        func tangent(_ index: Int) -> Float {
            if index == 0 || index == knots.count - 1 { return slope }
            let before = (values[index] - values[index - 1]) / (knots[index] - knots[index - 1])
            let after = (values[index + 1] - values[index]) / (knots[index + 1] - knots[index])
            return before * after > 0 ? 2 * before * after / (before + after) : 0
        }
        let fraction = (value - knots[lower]) / distance
        let squared = fraction * fraction
        let cubed = squared * fraction
        return values[lower] * (2 * cubed - 3 * squared + 1) + values[upper] * (-2 * cubed + 3 * squared)
            + tangent(lower) * distance * (cubed - 2 * squared + fraction)
            + tangent(upper) * distance * (cubed - squared)
    }

    private nonisolated struct Rig {
        let measurements: Measurements
        var stature: Float { measurements.height / 1.75 }
        var headHeight: Float { measurements.height - 0.218 }
        var shoulderHeight: Float { headHeight - 0.102 }
        var hipHeight: Float { measurements.inseam + (shoulderHeight - measurements.inseam) * 0.20 }
        var waistHeight: Float { measurements.inseam + (shoulderHeight - measurements.inseam) * 0.47 }
        var chestHeight: Float { measurements.inseam + (shoulderHeight - measurements.inseam) * 0.76 }
        var kneeHeight: Float { 0.14 * footScale + (measurements.inseam - 0.14 * footScale) * 0.47 }
        var handScale: Float { pow(stature, 0.45) * (measurements.feminine ? 0.97 : 1) }
        var footScale: Float { pow(stature, 0.65) * (measurements.feminine ? 0.97 : 1) }
        var volume: Float { 1 + min(max((measurements.weight - 70) / 30, -1), 1) * 0.06 }
        var armScale: Float { measurements.armSize * volume }
        var legScale: Float { measurements.legSize * volume }
        var hipSpacing: Float { max(0.097 * measurements.hip / 0.98, 0.089 * legScale) }
        var kneeSpacing: Float { 0.075 + (hipSpacing - 0.097) * 0.30 }
        var ankleSpacing: Float { max(0.085 * footScale, kneeSpacing + 0.010) }

        func skeleton(clearance: Float, floor: Float, handRotation: Float, footRotation: Float) -> BodySkeleton {
            var positions = BodySkeleton.referencePositions
            var orientations: [BodySkeleton.Joint: simd_quatf] = [:]
            positions[BodySkeleton.Joint.pelvis.rawValue] = [0, hipHeight, 0]
            positions[BodySkeleton.Joint.lumbar.rawValue] = [0, waistHeight, 0]
            positions[BodySkeleton.Joint.chest.rawValue] = [0, chestHeight, 0]
            positions[BodySkeleton.Joint.neck.rawValue] = [0, headHeight - 0.055, 0]
            positions[BodySkeleton.Joint.head.rawValue] = [0, headHeight, 0]
            for side: Float in [-1, 1] {
                let right = side > 0
                let clavicle: BodySkeleton.Joint = right ? .rightClavicle : .leftClavicle
                let shoulder: BodySkeleton.Joint = right ? .rightShoulder : .leftShoulder
                let elbow: BodySkeleton.Joint = right ? .rightElbow : .leftElbow
                let wrist: BodySkeleton.Joint = right ? .rightWrist : .leftWrist
                let palm: BodySkeleton.Joint = right ? .rightPalm : .leftPalm
                let hip: BodySkeleton.Joint = right ? .rightHip : .leftHip
                let knee: BodySkeleton.Joint = right ? .rightKnee : .leftKnee
                let ankle: BodySkeleton.Joint = right ? .rightAnkle : .leftAnkle
                let foot: BodySkeleton.Joint = right ? .rightFoot : .leftFoot
                positions[clavicle.rawValue] = [side * 0.055, shoulderHeight + 0.005, 0]
                for (joint, height) in [(shoulder, Float(1.43)), (elbow, Float(1.125)), (wrist, Float(0.88))] {
                    positions[joint.rawValue] = armCenter(at: height, clearance: clearance) * SIMD3<Float>(side, 1, 1)
                }
                let handTwist = simd_quatf(angle: side * handRotation, axis: [0, 1, 0])
                let referenceHand = BodySkeleton.referencePositions[palm.rawValue] - BodySkeleton.referencePositions[wrist.rawValue]
                positions[palm.rawValue] = positions[wrist.rawValue] + handTwist.act(referenceHand) * handScale
                orientations[wrist] = handTwist * simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(referenceHand))
                positions[hip.rawValue] = [side * hipSpacing, hipHeight, 0]
                positions[knee.rawValue] = [side * kneeSpacing, kneeHeight, 0]
                positions[ankle.rawValue] = [side * ankleSpacing, (0.14 - floor) * footScale, 0]
                let footTurn = simd_quatf(angle: side * footRotation, axis: [0, 1, 0])
                let referenceFoot = BodySkeleton.referencePositions[foot.rawValue] - BodySkeleton.referencePositions[ankle.rawValue]
                positions[foot.rawValue] = positions[ankle.rawValue] + footTurn.act(referenceFoot) * footScale
                orientations[ankle] = footTurn * simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(referenceFoot))
            }
            return BodySkeleton(positions: positions, orientations: orientations)
        }

        func armCenter(at referenceHeight: Float, clearance: Float) -> SIMD3<Float> {
            let shoulderShift = (measurements.shoulderWidth - 0.45) * 0.5
            let shoulderX = 0.190 + shoulderShift
            let elbowX = max(0.232 + shoulderShift, clearance + 0.043 * armScale)
            let wristX = max(0.258 + shoulderShift, elbowX + 0.019)
            let elbowDepth = -0.013 * sqrt(stature)
            let wristDepth = 0.023 * sqrt(stature)
            let reference = BodySkeleton.referencePositions
            let upperLength = simd_distance(reference[BodySkeleton.Joint.rightShoulder.rawValue],
                                           reference[BodySkeleton.Joint.rightElbow.rawValue]) * pow(stature, 0.9)
            let lowerLength = simd_distance(reference[BodySkeleton.Joint.rightElbow.rawValue],
                                           reference[BodySkeleton.Joint.rightWrist.rawValue]) * pow(stature, 0.9)
            let elbowHeight = shoulderHeight - sqrt(max(upperLength * upperLength
                - pow(elbowX - shoulderX, 2) - elbowDepth * elbowDepth, 0.0001))
            let wristHeight = elbowHeight - sqrt(max(lowerLength * lowerLength
                - pow(wristX - elbowX, 2) - pow(wristDepth - elbowDepth, 2), 0.0001))
            let knots: [Float] = [0.768, 0.88, 1.125, 1.43]
            return [ParametricBody.interpolate(referenceHeight, knots: knots,
                                                values: [wristX + 0.013 * handScale, wristX, elbowX, shoulderX]),
                    ParametricBody.interpolate(referenceHeight, knots: knots,
                                                values: [wristHeight - 0.112 * handScale, wristHeight, elbowHeight, shoulderHeight]),
                    ParametricBody.armCenter(at: referenceHeight).z * pow(stature, 0.5)]
        }
    }

    static func makeTemplate() -> Self {
        var mesh = Self()
        let trunk: [(height: Float, width: Float, front: Float, back: Float)] = [
            (0.875, 0.176, 0.104, 0.143),
            (0.940, 0.174, 0.118, 0.154),
            (1.000, 0.166, 0.125, 0.136),
            (1.060, 0.152, 0.120, 0.113),
            (1.105, 0.143, 0.111, 0.100),
            (1.165, 0.155, 0.113, 0.114),
            (1.220, 0.174, 0.119, 0.128),
            (1.250, 0.184, 0.133, 0.126),
            (1.285, 0.189, 0.138, 0.124),
            (1.325, 0.185, 0.134, 0.123),
            (1.355, 0.189, 0.129, 0.127),
            (1.390, 0.197, 0.112, 0.118),
            (1.423, 0.210, 0.096, 0.107),
            (1.447, 0.217, 0.087, 0.097),
            (1.477, 0.090, 0.054, 0.063),
            (1.515, 0.054, 0.045, 0.053),
            (1.565, 0.048, 0.044, 0.048)
        ]
        let axillaRow = 9
        let shoulderRow = 13
        let trunkRings = trunk.map { section in
            mesh.ring(count: 16) { angle in
                let across = cos(angle)
                let forward = sin(angle)
                let height = section.height
                let front = max(forward, 0)
                let back = max(-forward, 0)
                let lateral = abs(across)
                let chest = bump(height, 1.295, 0.085)
                let glute = bump(height, 0.94, 0.09)
                let lumbar = bump(height, 1.105, 0.10)
                let ribCage = bump(height, 1.28, 0.14)
                let chestPlane = pow(front, 1 - ribCage * 0.28)
                let backPlane = pow(back, 0.90)
                var point = SIMD3<Float>(section.width * across, height,
                                         section.front * chestPlane - section.back * backPlane)
                let paired = bump(abs(across), 0.48, 0.35)
                let sternum = 0.0035 * chest * bump(point.x, 0, 0.024)
                let pectoralEdge = 0.003 * bump(height, 1.235 + 0.025 * lateral, 0.023) * paired
                let lowerAbdomen = 0.005 * bump(height, 1.035, 0.080) * bump(across, 0, 0.70)
                let navel = 0.0018 * bump(height, 1.074, 0.012) * bump(point.x, 0, 0.012)
                let clavicle = 0.004 * bump(height, 1.414 - 0.025 * lateral, 0.027)
                    * bump(lateral, 0.56, 0.32)
                let collarNotch = 0.003 * bump(height, 1.465, 0.028) * bump(across, 0, 0.22)
                let shoulderBlades = 0.007 * bump(height, 1.355, 0.090) * bump(lateral, 0.52, 0.25)
                let spinalGroove = 0.003 * bump(height, 1.27, 0.24) * bump(point.x, 0, 0.017)
                let glutealCleft = 0.005 * glute * bump(point.x, 0, 0.020)
                point.z += (lowerAbdomen + clavicle - sternum - pectoralEdge - navel - collarNotch) * front
                point.z += (0.006 * lumbar + spinalGroove + glutealCleft - shoulderBlades) * back
                point.x *= 1 + 0.025 * ribCage * back * lateral
                point.y -= 0.009 * bump(height, 1.447, 0.023) * lateral * lateral
                let feminine = SIMD3<Float>(
                    point.x * (0.09 * glute - 0.045 * chest - 0.04 * lumbar), 0,
                    -0.010 * chest * back - 0.012 * glute * paired * back + 0.004 * lumbar * back)
                return Vertex(position: point, feminine: feminine, weights: [1, 0, 0, 0])
            }
        }
        for row in 0..<(trunkRings.count - 1) {
            for column in 0..<16 {
                let rightOpening = column == 15 || column == 0
                let leftOpening = (7..<9).contains(column)
                if (axillaRow..<shoulderRow).contains(row) && (rightOpening || leftOpening) { continue }
                mesh.quad(trunkRings[row][column], trunkRings[row + 1][column],
                          trunkRings[row + 1][(column + 1) % 16], trunkRings[row][(column + 1) % 16], region: 0)
            }
        }
        mesh.cap(trunkRings.last!, top: true, region: 0)

        let bottom = trunkRings[0]
        let front = mesh.vertices[bottom[4]]
        let back = mesh.vertices[bottom[12]]
        let bridge = (1...3).map { step -> Int in
            let fraction = Float(step) / 4
            var vertex = front * (1 - fraction) + back * fraction
            vertex.position.y = 0.875 - 0.068 * sin(.pi * fraction)
            return mesh.append(vertex)
        }
        let rightHip = Array(bottom[0...4]) + bridge + Array(bottom[12..<16])
        let leftHip = Array(bottom[8...12]) + Array(bridge.reversed()) + Array(bottom[4..<8])

        for side: Float in [-1, 1] {
            let armRegion = side > 0 ? 1 : 2
            let arm: [(height: Float, center: Float, width: Float, depth: Float, forward: Float)] = [
                (0.768, 0.271, 0.033, 0.012, 0.030),
                (0.796, 0.269, 0.039, 0.020, 0.027),
                (0.839, 0.263, 0.032, 0.022, 0.025),
                (0.880, 0.258, 0.027, 0.023, 0.023),
                (0.930, 0.255, 0.032, 0.029, 0.016),
                (1.005, 0.250, 0.041, 0.038, 0.007),
                (1.070, 0.240, 0.038, 0.037, -0.006),
                (1.115, 0.232, 0.034, 0.033, -0.010),
                (1.150, 0.227, 0.037, 0.039, -0.008),
                (1.225, 0.225, 0.047, 0.047, 0),
                (1.270, 0.222, 0.049, 0.050, 0),
                (1.300, 0.218, 0.049, 0.052, 0)
            ]
            let armRings = arm.map { section in
                mesh.ring(count: 12) { angle in
                    let across = cos(angle)
                    let forward = sin(angle)
                    let outer = max(across * side, 0)
                    let front = max(forward, 0)
                    let back = max(-forward, 0)
                    let biceps = 0.006 * bump(section.height, 1.25, 0.085) * front * front
                    let triceps = 0.005 * bump(section.height, 1.265, 0.090) * back * back
                    let elbow = 0.004 * bump(section.height, 1.12, 0.023) * back * back
                    let forearm = 0.004 * bump(section.height, 1.02, 0.073) * outer * outer
                    let deltoid = 0.006 * bump(section.height, 1.34, 0.060) * outer * outer
                    let anatomy = SIMD3<Float>(side * (forearm + deltoid), 0, biceps - triceps - elbow)
                    let point = SIMD3<Float>(side * section.center + section.width * across,
                                             section.height, section.forward + section.depth * forward) + anatomy
                    return Vertex(position: point,
                                  feminine: SIMD3<Float>(section.width * across * -0.06, 0, section.depth * forward * -0.06) - anatomy * 0.45,
                                  weights: [0, 1, 0, 0])
                }
            }
            mesh.tube(armRings, region: armRegion)
            mesh.attachFingers(to: armRings[0], side: side, region: armRegion)
            let shoulder = opening(trunkRings, rows: axillaRow...shoulderRow, column: side > 0 ? 15 : 7, width: 2)
            let targetStart = trunkRings[side > 0 ? shoulderRow : axillaRow][side > 0 ? 0 : 8]
            mesh.join(armRings.last!, to: shoulder, startingAt: targetStart, region: armRegion) { vertex in
                var shaped = vertex
                let outer = min(max((vertex.position.x * side - 0.15) / 0.10, 0), 1)
                shaped.position.x += side * 0.008 * outer * outer
                shaped.position.y += 0.004 * outer * outer
                shaped.position.z += 0.010 * tanh(vertex.position.z / 0.030)
                    * bump(vertex.position.y, 1.36, 0.080)
                shaped.feminine.x -= side * 0.003 * outer * outer
                shaped.feminine.y -= 0.002 * outer * outer
                shaped.feminine.z -= 0.004 * tanh(vertex.position.z / 0.030)
                    * bump(vertex.position.y, 1.36, 0.080)
                return shaped
            }

            let legRegion = side > 0 ? 3 : 4
            let leg: [(height: Float, center: Float, width: Float, depth: Float, forward: Float)] = [
                (0.140, 0.085, 0.029, 0.032, -0.003),
                (0.180, 0.085, 0.031, 0.038, -0.004),
                (0.240, 0.085, 0.040, 0.050, -0.010),
                (0.320, 0.083, 0.050, 0.061, -0.015),
                (0.400, 0.077, 0.043, 0.045, -0.007),
                (0.465, 0.075, 0.039, 0.040, 0.013),
                (0.500, 0.077, 0.047, 0.046, 0.014),
                (0.570, 0.082, 0.061, 0.063, 0.010),
                (0.665, 0.090, 0.078, 0.085, 0.001),
                (0.785, 0.097, 0.088, 0.099, -0.007)
            ]
            let legRings = leg.map { section in
                mesh.ring(count: 12) { angle in
                    let across = cos(angle)
                    let forward = sin(angle)
                    let medial = max(-across * side, 0)
                    let lateral = max(across * side, 0)
                    let front = max(forward, 0)
                    let back = max(-forward, 0)
                    var point = SIMD3<Float>(side * section.center + section.width * across,
                                             section.height, section.forward + section.depth * forward)
                    let quadriceps = 0.007 * bump(section.height, 0.65, 0.13) * front * front
                    let innerKnee = 0.004 * bump(section.height, 0.53, 0.05) * medial * front
                    let patella = 0.0045 * bump(section.height, 0.47, 0.035) * front * front
                    let shin = 0.0025 * bump(section.height, 0.29, 0.12) * bump(across * side, -0.20, 0.30) * front
                    let hamstrings = 0.004 * bump(section.height, 0.64, 0.15) * back * back
                    let innerCalf = 0.006 * bump(section.height, 0.31, 0.075) * medial * back
                    let outerCalf = 0.004 * bump(section.height, 0.35, 0.060) * lateral * back
                    let achilles = 0.003 * bump(section.height, 0.17, 0.06) * back * back
                    let kneeHollow = 0.003 * bump(section.height, 0.465, 0.035) * back * back
                    point.z += quadriceps + innerKnee + patella + shin + kneeHollow
                        - hamstrings - innerCalf - outerCalf - achilles
                    point.x += side * (0.003 * lateral * bump(section.height, 0.14, 0.025)
                        - 0.003 * medial * bump(section.height, 0.16, 0.025))
                    return Vertex(position: point,
                                  feminine: [section.width * across * 0.06 * bump(section.height, 0.73, 0.18),
                                             0, section.depth * forward * 0.035], weights: [0, 0, 1, 0])
                }
            }
            mesh.tube(legRings, region: legRegion)
            let hip = side > 0 ? rightHip : leftHip
            mesh.join(legRings.last!, to: hip, startingAt: side > 0 ? hip[0] : hip[6], region: legRegion)

            let foot: [(forward: Float, width: Float, height: Float, depth: Float)] = [
                (-0.075, 0.013, 0.027, 0.019),
                (-0.055, 0.029, 0.037, 0.034),
                (-0.020, 0.033, 0.059, 0.058),
                (0.020, 0.035, 0.051, 0.044),
                (0.055, 0.036, 0.035, 0.027),
                (0.080, 0.047, 0.024, 0.021)
            ]
            let footRings = foot.map { section in
                mesh.ring(count: 12) { angle in
                    let across = cos(angle)
                    let lower = max(sin(angle), 0)
                    let arch = 0.015 * bump(section.forward, 0.025, 0.045) * max(-across * side, 0) * lower
                    let point = SIMD3<Float>(side * 0.085 + section.width * across,
                                             section.height - section.depth * sin(angle) + arch,
                                             section.forward - 0.012 * max(across * side, 0) * bump(section.forward, 0.14, 0.03))
                    return Vertex(position: point, weights: [0, 0, 0, 1])
                }
            }
            for row in 0..<(footRings.count - 1) {
                for column in 0..<12 {
                    if (1..<3).contains(row) && (7..<11).contains(column) { continue }
                    mesh.quad(footRings[row][column], footRings[row + 1][column],
                              footRings[row + 1][(column + 1) % 12], footRings[row][(column + 1) % 12], region: legRegion)
                }
            }
            mesh.cap(footRings[0], top: false, region: legRegion)
            mesh.attachToes(to: footRings.last!, side: side, region: legRegion)
            let ankle = opening(footRings, rows: 1...3, column: 7, width: 4)
            mesh.join(Array(legRings[0].reversed()), to: ankle, region: legRegion)
        }
        return mesh.subdivided().subdivided().withSurfaceAnatomy().subdivided().withJointLandmarks()
    }

    private mutating func attachFingers(to palm: [Int], side: Float, region: Int) {
        faces.append(Face(indices: [palm[0], palm[1], palm[11]], region: region))
        faces.append(Face(indices: [palm[5], palm[6], palm[7]], region: region))
        let sections: [(progress: Float, width: Float, depth: Float, forward: Float)] = [
            (1.00, 0.16, 0.16, 0.015),
            (0.95, 0.58, 0.52, 0.015),
            (0.78, 0.86, 0.80, 0.013),
            (0.62, 0.88, 0.78, 0.009),
            (0.48, 1.07, 0.97, 0.006),
            (0.25, 0.98, 0.90, 0.002)
        ]
        for (index, finger) in Self.fingers.enumerated() {
            let slot = side > 0 ? index : 3 - index
            let root = [palm[1 + slot], palm[2 + slot], palm[10 - slot], palm[11 - slot]]
            let rings = sections.map { section in
                ring(count: 4) { angle in
                    let spread = -side * finger.offset * 0.08 * section.progress
                    let center = side * (0.264 - finger.offset) + spread
                    let height = min(0.772 + finger.rootHeight - finger.length * section.progress, 0.758)
                    let forward = 0.033 + section.forward + finger.curl * section.progress * section.progress
                    let position = SIMD3<Float>(
                        center + finger.radius * section.width * 1.53 * cos(angle + .pi / 4),
                        height, forward + finger.radius * section.depth * 1.53 * sin(angle + .pi / 4))
                    return Vertex(position: position, weights: [0, 1, 0, 0])
                }
            }
            tube(rings + [root], region: region)
            cap(rings[0], top: false, region: region)
        }
    }

    private mutating func attachToes(to forefoot: [Int], side: Float, region: Int) {
        let boundaries: [Float] = [-0.045, -0.018, 0.002, 0.018, 0.032, 0.046]
        var lower: [Int] = []
        var upper: [Int] = []
        for (index, across) in boundaries.enumerated() {
            let before = Self.toes[max(index - 1, 0)]
            let after = Self.toes[min(index, Self.toes.count - 1)]
            let forward = (before.base + after.base) * 0.5
            let radius = (before.radius + after.radius) * 0.5
            lower.append(append(Vertex(position: [side * (0.085 + across), Self.toeBaseHeight - radius * 0.75, forward],
                                       weights: [0, 0, 0, 1])))
            upper.append(append(Vertex(position: [side * (0.085 + across), Self.toeBaseHeight + radius * 0.85, forward],
                                       weights: [0, 0, 0, 1])))
        }
        let junction = side > 0 ? Array(lower.reversed()) + upper : lower + Array(upper.reversed())
        tube([forefoot, junction], region: region)
        let sections: [(progress: Float, width: Float, depth: Float)] = [
            (0.22, 1.02, 0.82),
            (0.45, 0.98, 0.82),
            (0.63, 0.88, 0.74),
            (0.80, 0.86, 0.72),
            (0.94, 0.55, 0.48),
            (1.00, 0.16, 0.16)
        ]
        for (index, toe) in Self.toes.enumerated() {
            let slot = side > 0 ? 4 - index : index
            let root = [junction[slot], junction[slot + 1], junction[10 - slot], junction[11 - slot]]
            let drop = Self.toeBaseHeight - (toe.radius * 0.72 + 0.003)
            let rings = sections.map { section in
                ring(count: 4) { angle in
                    let position = SIMD3<Float>(
                        side * (0.085 + toe.offset) + toe.radius * section.width * 1.53 * cos(angle + .pi / 4),
                        Self.toeBaseHeight - drop * Self.blend(section.progress)
                            - toe.radius * section.depth * 1.53 * sin(angle + .pi / 4),
                        toe.base + toe.length * section.progress)
                    return Vertex(position: position, weights: [0, 0, 0, 1])
                }
            }
            tube([root] + rings, region: region)
            cap(rings.last!, top: true, region: region)
        }
    }

    private func withSurfaceAnatomy() -> Self {
        var result = self
        for index in vertices.indices {
            let vertex = vertices[index]
            let point = vertex.position
            let lateral = abs(point.x)
            let front = Self.blend((point.z - 0.015) / 0.065)
            let back = Self.blend((-point.z - 0.015) / 0.065)
            let pectoral = 0.012 * Self.bump(lateral, 0.083, 0.069) * Self.bump(point.y, 1.305, 0.080)
            let sternum = 0.004 * Self.bump(point.x, 0, 0.020) * Self.bump(point.y, 1.33, 0.095)
            let collar = 0.003 * Self.bump(lateral, 0.091, 0.080)
                * Self.bump(point.y, 1.442 - lateral * 0.15, 0.018)
            let abdomen = 0.002 * Self.bump(lateral, 0.035, 0.030) * Self.bump(point.y, 1.16, 0.090)
            let navel = 0.0028 * Self.bump(point.x, 0, 0.010) * Self.bump(point.y, 1.075, 0.012)
            let scapula = 0.006 * Self.bump(lateral, 0.086, 0.052) * Self.bump(point.y, 1.35, 0.085)
            let spine = 0.003 * Self.bump(point.x, 0, 0.016) * Self.bump(point.y, 1.26, 0.18)
            let glute = 0.008 * Self.bump(lateral, 0.081, 0.059) * Self.bump(point.y, 0.925, 0.090)
            let cleft = 0.009 * Self.bump(point.x, 0, 0.015) * Self.bump(point.y, 0.916, 0.085)
            let relief = vertex.weights.x * (front * (pectoral + collar + abdomen - sternum - navel)
                + back * (spine + cleft - scapula - glute))
            result.vertices[index].position.z += relief
            result.vertices[index].feminine.z -= vertex.weights.x * front * (pectoral - sternum) * 0.75

            let side: Float = point.x < 0 ? -1 : 1
            let legCenter = Self.interpolate(point.y, knots: [0.14, 0.465, 0.785, 0.94], values: [0.085, 0.075, 0.097, 0.097])
            let legAcross = lateral - legCenter
            let legFront = Self.blend((point.z + 0.005) / 0.065)
            let legBack = Self.blend((-point.z - 0.005) / 0.065)
            let thighFront = 0.007 * Self.bump(legAcross, 0.010, 0.047) * Self.bump(point.y, 0.65, 0.13)
            let innerKnee = 0.007 * Self.bump(legAcross, -0.027, 0.025) * Self.bump(point.y, 0.535, 0.047)
            let kneecap = 0.0035 * Self.bump(legAcross, 0, 0.027) * Self.bump(point.y, 0.472, 0.032)
            let calfInner = 0.007 * Self.bump(legAcross, -0.020, 0.025) * Self.bump(point.y, 0.31, 0.068)
            let calfOuter = 0.005 * Self.bump(legAcross, 0.023, 0.024) * Self.bump(point.y, 0.347, 0.060)
            let calfRelief = vertex.weights.z * (legFront * (thighFront + innerKnee + kneecap) - legBack * (calfInner + calfOuter))
            result.vertices[index].position.z += calfRelief
            result.vertices[index].position.x += side * vertex.weights.z * (
                0.004 * Self.bump(point.y, 0.68, 0.12) * Self.blend(legAcross / 0.07)
                - 0.004 * Self.bump(point.y, 0.53, 0.05) * Self.blend(-legAcross / 0.04))
            result.vertices[index].feminine.z -= calfRelief * 0.35
        }
        result = result.withMasculineForm().withFeminineForm()
        for index in vertices.indices {
            result.vertices[index].anatomy = result.vertices[index].position - vertices[index].position
            result.vertices[index].feminineAnatomy = result.vertices[index].feminine - vertices[index].feminine
        }
        return result
    }

    private func withMasculineForm() -> Self {
        var result = self
        for index in vertices.indices {
            let vertex = vertices[index]
            let point = vertex.position
            let lateral = abs(point.x)
            let side: Float = point.x < 0 ? -1 : 1
            let front = Self.blend((point.z - 0.008) / 0.055)
            let back = Self.blend((-point.z - 0.008) / 0.055)
            let trunk = vertex.weights.x
            var offset = SIMD3<Float>.zero

            let shoulder = Self.bump(lateral, 0.185, 0.052) * Self.bump(point.y, 1.377, 0.082)
            offset.z += 0.008 * shoulder * tanh(point.z / 0.042)
            let neckBase = Self.bump(point.y, 1.473, 0.044) * Self.blend((0.13 - lateral) / 0.09)
            offset.z += neckBase * (0.010 * front - 0.009 * back)

            let chestLevel = Self.blend((point.y - 1.235) / 0.040) * Self.blend((1.414 - point.y) / 0.065)
            let chestAcross = Self.blend((lateral - 0.008) / 0.036) * Self.blend((0.187 - lateral) / 0.046)
            let pectoral = 0.003 * chestLevel * chestAcross
                - 0.010 * Self.bump(point.y, 1.293, 0.079) * Self.bump(lateral, 0.075, 0.085)
            let pectoralBorder = 0.0025 * Self.bump(point.y, 1.239 + 0.045 * pow(lateral / 0.17, 2), 0.028)
                * Self.bump(lateral, 0.086, 0.074)
            let sternum = 0.003 * Self.bump(lateral, 0, 0.028) * Self.bump(point.y, 1.329, 0.087)
            let clavicleHeight = 1.431 - 0.042 * lateral / 0.185 + 0.007 * sin(lateral * .pi / 0.185)
            let clavicle = 0.004 * Self.bump(point.y, clavicleHeight, 0.024)
                * Self.blend(lateral / 0.032) * Self.blend((0.196 - lateral) / 0.040)
            let collarHollow = 0.003 * Self.bump(lateral, 0, 0.030) * Self.bump(point.y, 1.447, 0.029)
            let neckTendon = 0.002 * Self.bump(lateral, 0.022 + (point.y - 1.445) * 0.20, 0.021)
                * Self.bump(point.y, 1.483, 0.054)
            let abdominalColumn = Self.bump(lateral, 0.039, 0.034)
            let abdomen = abdominalColumn * (0.003 * Self.bump(point.y, 1.206, 0.031)
                + 0.0035 * Self.bump(point.y, 1.148, 0.033) + 0.002 * Self.bump(point.y, 1.090, 0.035))
            let abdominalMidline = 0.0018 * Self.bump(lateral, 0, 0.009) * Self.bump(point.y, 1.159, 0.103)
            let inguinalLine = 0.003 * Self.bump(point.y, 0.942 + lateral * 0.66, 0.032)
                * Self.bump(lateral, 0.091, 0.070)
            offset.z += trunk * front * (pectoral + clavicle + neckTendon + abdomen
                - pectoralBorder - sternum - collarHollow - abdominalMidline - inguinalLine)

            let shoulderBlade = 0.005 * Self.bump(lateral, 0.092, 0.052) * Self.bump(point.y, 1.348, 0.075)
            let paraspinal = 0.004 * Self.bump(lateral, 0.026, 0.019) * Self.bump(point.y, 1.201, 0.184)
            let lowerBack = 0.003 * Self.bump(lateral, 0, 0.017) * Self.bump(point.y, 1.196, 0.145)
            let latissimus = Self.bump(lateral, 0.143, 0.057) * Self.bump(point.y, 1.239, 0.129)
            offset.z += trunk * back * (lowerBack - shoulderBlade - paraspinal - 0.006 * latissimus)
            offset.x += side * trunk * (0.006 * latissimus
                + 0.004 * Self.bump(lateral, 0.138, 0.035) * Self.bump(point.y, 1.018, 0.047))

            let upperGlute = 0.007 * Self.bump(point.y, 0.987, 0.085) * Self.bump(lateral, 0.075, 0.084)
            let glute = 0.010 * Self.bump(lateral, 0.078, 0.065) * Self.bump(point.y, 0.890, 0.073)
            let cleft = 0.008 * Self.bump(lateral, 0, 0.021) * Self.bump(point.y, 0.888, 0.097)
            let gluteFold = 0.003 * Self.bump(point.y, 0.818 + lateral * 0.17, 0.028)
                * Self.bump(lateral, 0.082, 0.070)
            offset.z += back * (upperGlute + cleft + gluteFold - glute)

            let armCenter = Self.armCenter(at: point.y)
            let armAcross = lateral - armCenter.x
            let armDepth = point.z - armCenter.z
            let armFront = Self.blend((armDepth + 0.002) / 0.034)
            let armBack = Self.blend((-armDepth + 0.002) / 0.034)
            let biceps = 0.005 * Self.bump(armAcross, -0.004, 0.037) * Self.bump(point.y, 1.234, 0.090)
            let triceps = 0.006 * Self.bump(armAcross, 0.014, 0.034) * Self.bump(point.y, 1.264, 0.107)
            let elbow = 0.005 * Self.bump(armAcross, 0, 0.028) * Self.bump(point.y, 1.118, 0.030)
            let elbowFold = 0.0025 * Self.bump(armAcross, 0, 0.030) * Self.bump(point.y, 1.120, 0.027)
            let forearmRidge = Self.bump(armAcross, 0.026, 0.028) * Self.bump(point.y, 1.033, 0.079)
            offset.z += vertex.weights.y * (armFront * (biceps - elbowFold)
                - armBack * (triceps + elbow + 0.003 * forearmRidge))
            offset.x += side * vertex.weights.y * 0.004 * forearmRidge

            let legCenter = Self.interpolate(point.y, knots: [0.14, 0.465, 0.785, 0.94],
                                              values: [0.085, 0.075, 0.097, 0.097])
            let legAcross = lateral - legCenter
            let legFront = Self.blend((point.z + 0.003) / 0.045)
            let legBack = Self.blend((-point.z + 0.003) / 0.045)
            let outerThigh = Self.bump(legAcross, 0.044, 0.042) * Self.bump(point.y, 0.657, 0.133)
            let innerKnee = Self.bump(legAcross, -0.029, 0.030) * Self.bump(point.y, 0.529, 0.059)
            let frontThigh = Self.bump(legAcross, -0.002, 0.035) * Self.bump(point.y, 0.659, 0.144)
            let patella = Self.bump(legAcross, 0, 0.028) * Self.bump(point.y, 0.470, 0.030)
            let shin = Self.bump(legAcross, -0.009, 0.018) * Self.bump(point.y, 0.314, 0.146)
            let hamstring = Self.bump(legAcross, -0.027, 0.030) * Self.bump(point.y, 0.674, 0.137)
                + 0.8 * Self.bump(legAcross, 0.030, 0.032) * Self.bump(point.y, 0.646, 0.123)
            let kneeHollow = Self.bump(legAcross, 0, 0.027) * Self.bump(point.y, 0.466, 0.043)
            let innerCalf = Self.bump(legAcross, -0.023, 0.026) * Self.bump(point.y, 0.299, 0.081)
            let outerCalf = Self.bump(legAcross, 0.024, 0.028) * Self.bump(point.y, 0.343, 0.071)
            let calfDivide = Self.bump(legAcross, 0.001, 0.018) * Self.bump(point.y, 0.330, 0.069)
            offset.z += vertex.weights.z * (legFront * (0.005 * frontThigh + 0.004 * innerKnee
                + 0.003 * patella + 0.003 * shin) + legBack * (0.004 * kneeHollow + 0.0025 * calfDivide
                - 0.004 * hamstring - 0.004 * innerCalf - 0.003 * outerCalf))
            offset.x += side * vertex.weights.z * (0.005 * outerThigh - 0.004 * innerKnee
                - 0.003 * innerCalf + 0.003 * outerCalf)

            result.vertices[index].position += offset
            result.vertices[index].feminine -= offset
        }
        return result
    }

    private func withFeminineForm() -> Self {
        var result = self
        for index in vertices.indices {
            let vertex = vertices[index]
            let point = vertex.position + vertex.feminine
            let lateral = abs(point.x)
            let side: Float = point.x < 0 ? -1 : 1
            let front = Self.blend((point.z - 0.008) / 0.055)
            let back = Self.blend((-point.z - 0.008) / 0.055)
            let trunk = vertex.weights.x
            var offset = SIMD3<Float>.zero

            let neck = Self.bump(point.y, 1.507, 0.065) * Self.blend((0.12 - lateral) / 0.07)
            offset.x -= point.x * 0.07 * neck
            offset.z -= point.z * 0.04 * neck
            let shoulder = Self.bump(lateral, 0.180, 0.071) * Self.bump(point.y, 1.365, 0.110)
            offset.z += 0.006 * shoulder * tanh(point.z / 0.055)
            let clavicle = 0.0025 * Self.bump(point.y, 1.429 - lateral * 0.24, 0.027)
                * Self.blend(lateral / 0.035) * Self.blend((0.19 - lateral) / 0.04)
            let collarHollow = 0.002 * Self.bump(lateral, 0, 0.031) * Self.bump(point.y, 1.444, 0.032)

            let ribCage = Self.bump(point.y, 1.302, 0.140)
            offset.x -= side * trunk * 0.012 * ribCage * Self.blend(lateral / 0.15)
            let waist = Self.bump(point.y, 1.108, 0.122)
            offset.x -= point.x * trunk * 0.055 * waist
            offset.z += point.z * trunk * 0.045 * waist
            let breastHeight = point.y - 1.283
            let breastRadius: Float = breastHeight >= 0 ? 0.115 : 0.074
            let breastVertical = pow(breastHeight / breastRadius, 2)
            let rightBreast = pow((point.x - 0.085) / 0.085, 2) + breastVertical
            let leftBreast = pow((point.x + 0.085) / 0.085, 2) + breastVertical
            let breast = 0.034 * (exp(-1.4 * pow(rightBreast, 1.25)) + exp(-1.4 * pow(leftBreast, 1.25)))
            let breastFold = 0.0015 * Self.bump(point.y, 1.217 + 0.013 * pow((lateral - 0.079) / 0.070, 2), 0.040)
                * Self.bump(lateral, 0.079, 0.061)
            let sternum = 0.005 * Self.bump(lateral, 0, 0.032) * Self.bump(point.y, 1.300, 0.105)
            let lowerAbdomen = 0.004 * Self.bump(lateral, 0, 0.092) * Self.bump(point.y, 1.036, 0.078)
            let abdominalMidline = 0.0015 * Self.bump(lateral, 0, 0.018) * Self.bump(point.y, 1.160, 0.104)
            let navel = 0.0012 * Self.bump(lateral, 0, 0.014) * Self.bump(point.y, 1.075, 0.018)
            let inguinalLine = 0.0025 * Self.bump(point.y, 0.933 + lateral * 0.68, 0.036)
                * Self.bump(lateral, 0.092, 0.068)
            offset.z += trunk * front * (clavicle + breast + lowerAbdomen - collarHollow
                - breastFold - sternum - abdominalMidline - navel - inguinalLine)

            let scapula = 0.003 * Self.bump(lateral, 0.082, 0.049) * Self.bump(point.y, 1.346, 0.094)
            let paraspinal = 0.0025 * Self.bump(lateral, 0.026, 0.022) * Self.bump(point.y, 1.205, 0.178)
            let spine = 0.002 * Self.bump(lateral, 0, 0.019) * Self.bump(point.y, 1.226, 0.186)
            let lumbar = 0.006 * Self.bump(point.y, 1.084, 0.131) * Self.blend((0.155 - lateral) / 0.11)
            offset.z += trunk * back * (spine + lumbar - scapula - paraspinal)

            let pelvis = vertex.weights.x + vertex.weights.z
            let outerHip = Self.blend(lateral / 0.16)
            offset.x += side * pelvis * outerHip * 0.010 * Self.bump(point.y, 0.868, 0.157)
            let upperGlute = 0.022 * Self.bump(lateral, 0.078, 0.108) * Self.bump(point.y, 0.945, 0.112)
            let glute = 0.017 * Self.bump(lateral, 0.078, 0.083) * Self.bump(point.y, 0.843, 0.127)
            let cleft = 0.004 * Self.bump(lateral, 0, 0.022) * Self.bump(point.y, 0.875, 0.105)
            let gluteFold = 0.0015 * Self.bump(point.y, 0.801 + lateral * 0.16, 0.048)
                * Self.bump(lateral, 0.078, 0.060)
            offset.z += pelvis * back * (upperGlute + cleft + gluteFold - glute)

            let armCenter = Self.armCenter(at: point.y)
            let armAcross = lateral - armCenter.x
            let armDepth = point.z - armCenter.z
            let armFront = Self.blend((armDepth + 0.002) / 0.034)
            let armBack = Self.blend((-armDepth + 0.002) / 0.034)
            let upperArm = Self.bump(point.y, 1.266, 0.112)
            let elbow = Self.bump(armAcross, 0, 0.027) * Self.bump(point.y, 1.118, 0.033)
            let forearm = Self.bump(armAcross, 0.020, 0.030) * Self.bump(point.y, 1.025, 0.085)
            let wristTendon = Self.bump(armAcross, -0.004, 0.016) * Self.bump(point.y, 0.942, 0.063)
            offset.x += side * vertex.weights.y * (0.003 * forearm - armAcross * 0.045 * upperArm)
            offset.z += vertex.weights.y * (armFront * (0.002 * forearm + 0.0015 * wristTendon - 0.0015 * elbow)
                - armBack * (0.0035 * elbow + 0.0025 * forearm) - armDepth * 0.035 * upperArm)

            let legCenter = Self.interpolate(point.y, knots: [0.14, 0.465, 0.785, 0.94],
                                              values: [0.085, 0.075, 0.097, 0.097])
            let legAcross = lateral - legCenter
            let legFront = Self.blend((point.z + 0.003) / 0.046)
            let legBack = Self.blend((-point.z + 0.003) / 0.046)
            let outerThigh = Self.bump(legAcross, 0.044, 0.047) * Self.bump(point.y, 0.685, 0.155)
            let adductor = Self.bump(legAcross, -0.041, 0.037) * Self.bump(point.y, 0.728, 0.120)
            let innerKnee = Self.bump(legAcross, -0.027, 0.029) * Self.bump(point.y, 0.526, 0.054)
            let kneecap = Self.bump(legAcross, 0, 0.027) * Self.bump(point.y, 0.471, 0.035)
            let kneeLine = Self.bump(point.y, 0.479, 0.155)
            let shin = Self.bump(legAcross, -0.007, 0.023) * Self.bump(point.y, 0.310, 0.146)
            let hamstring = Self.bump(legAcross, -0.025, 0.033) * Self.bump(point.y, 0.665, 0.142)
                + 0.7 * Self.bump(legAcross, 0.029, 0.034) * Self.bump(point.y, 0.645, 0.126)
            let kneeHollow = Self.bump(legAcross, 0, 0.026) * Self.bump(point.y, 0.465, 0.045)
            let innerCalf = Self.bump(legAcross, -0.020, 0.027) * Self.bump(point.y, 0.302, 0.079)
            let outerCalf = Self.bump(legAcross, 0.022, 0.027) * Self.bump(point.y, 0.348, 0.072)
            offset.x += side * vertex.weights.z * (0.004 * outerThigh - 0.002 * innerKnee
                - 0.004 * kneeLine - 0.002 * innerCalf + 0.002 * outerCalf)
            offset.z += vertex.weights.z * (legFront * (0.0025 * outerThigh + 0.002 * adductor
                + 0.002 * innerKnee + 0.0025 * kneecap + 0.0015 * shin)
                + legBack * (0.002 * kneeHollow - 0.0025 * hamstring - 0.0035 * innerCalf - 0.0025 * outerCalf))

            result.vertices[index].feminine += offset
        }
        let shoulderWeights = result.vertices.map { vertex -> Float in
            let point = vertex.position + vertex.feminine
            return Self.blend((abs(point.x) - 0.115) / 0.070)
                * Self.blend((0.315 - abs(point.x)) / 0.060)
                * Self.blend((point.y - 1.235) / 0.090)
                * Self.blend((1.485 - point.y) / 0.080)
        }
        let shoulderIndices = result.vertices.indices.filter { shoulderWeights[$0] > 0 }
        var neighbors: [Int: Set<Int>] = [:]
        for face in faces {
            for corner in face.indices.indices {
                let current = face.indices[corner]
                let next = face.indices[(corner + 1) % face.indices.count]
                if shoulderWeights[current] > 0 { neighbors[current, default: []].insert(next) }
                if shoulderWeights[next] > 0 { neighbors[next, default: []].insert(current) }
            }
        }
        var surface = result.vertices.map { $0.position + $0.feminine }
        for _ in 0..<8 {
            let previous = surface
            for index in shoulderIndices {
                guard let adjacent = neighbors[index], !adjacent.isEmpty else { continue }
                let average = adjacent.reduce(SIMD3<Float>.zero) { $0 + previous[$1] } / Float(adjacent.count)
                surface[index] += (average - previous[index]) * (0.48 * shoulderWeights[index])
            }
        }
        for index in shoulderIndices {
            result.vertices[index].feminine = surface[index] - result.vertices[index].position
        }
        return result
    }

    private func withJointLandmarks() -> Self {
        var result = self
        for index in vertices.indices {
            let vertex = vertices[index]
            func offset(feminine: Bool) -> SIMD3<Float> {
                let point = vertex.position + (feminine ? vertex.feminine : .zero)
                let lateral = abs(point.x)
                let side: Float = point.x < 0 ? -1 : 1
                let definition: Float = feminine ? 0.62 : 1
                let front = Self.blend((point.z - 0.005) / 0.055)
                let back = Self.blend((-point.z - 0.005) / 0.055)
                let trunk = vertex.weights.x
                var displacement = SIMD3<Float>.zero

                let clavicle = Self.bump(point.y, 1.442 - lateral * 0.20, 0.015)
                    * Self.blend(lateral / 0.035) * Self.blend((0.20 - lateral) / 0.035)
                let trapezius = Self.bump(point.y, 1.465 - lateral * 0.30, 0.048)
                    * Self.bump(lateral, 0.075, 0.065)
                let deltoidBorder = Self.bump(lateral, 0.177, 0.025) * Self.bump(point.y, 1.348, 0.054)
                let costalArch = Self.bump(point.y, 1.236 - lateral * 0.47, 0.023)
                    * Self.bump(lateral, 0.09, 0.066)
                let oblique = Self.bump(lateral, 0.126, 0.038) * Self.bump(point.y, 1.095, 0.105)
                let iliacCrest = Self.bump(point.y, 0.994 - lateral * 0.20, 0.027)
                    * Self.bump(lateral, 0.133, 0.045)
                let scapularEdge = Self.bump(lateral, 0.118 - (point.y - 1.32) * 0.20, 0.025)
                    * Self.bump(point.y, 1.347, 0.067)
                let lumbarDimple = Self.bump(lateral, 0.047, 0.018) * Self.bump(point.y, 1.008, 0.030)
                displacement.z += trunk * definition * (front * (0.0022 * clavicle + 0.0025 * costalArch
                    + 0.003 * oblique + 0.0025 * iliacCrest - 0.002 * deltoidBorder)
                    + back * (0.0025 * lumbarDimple - 0.0035 * trapezius - 0.002 * scapularEdge))
                displacement.x += side * trunk * 0.0025 * iliacCrest
                if !feminine {
                    displacement.z += back * (0.008 * Self.bump(point.y, 0.928, 0.071)
                        - 0.004 * Self.bump(point.y, 0.852, 0.092)) * Self.bump(lateral, 0.070, 0.080)
                }

                let armCenter = Self.armCenter(at: point.y)
                let armAcross = lateral - armCenter.x
                let armDepth = point.z - armCenter.z
                let armFront = Self.blend((armDepth + 0.004) / 0.030)
                let armBack = Self.blend((-armDepth + 0.004) / 0.030)
                let epicondyle = Self.bump(point.y, 1.120, 0.022) * Self.blend(abs(armAcross) / 0.032)
                let wristBones = Self.bump(point.y, 0.893, 0.019) * Self.blend(abs(armAcross) / 0.024)
                let forearmTendon = Self.bump(armAcross, 0.008, 0.007) * Self.bump(point.y, 0.967, 0.062)
                let olecranon = Self.bump(point.y, 1.118, 0.018) * Self.bump(armAcross, 0, 0.022)
                displacement.x += side * vertex.weights.y * tanh(armAcross / 0.014)
                    * (0.0025 * epicondyle + 0.0018 * wristBones)
                displacement.z += vertex.weights.y * definition * (0.0016 * armFront * forearmTendon - 0.002 * armBack * olecranon)

                let legCenter = Self.interpolate(point.y, knots: [0.14, 0.465, 0.785, 0.94],
                                                  values: [0.085, 0.075, 0.097, 0.097])
                let legAcross = lateral - legCenter
                let kneeRim = Self.bump(point.y, 0.471, 0.033) * Self.bump(abs(legAcross), 0.026, 0.013)
                let patellarTendon = Self.bump(point.y, 0.429, 0.032) * Self.bump(legAcross, -0.003, 0.013)
                let tibia = Self.bump(point.y, 0.296, 0.100) * Self.bump(legAcross, -0.010, 0.015)
                let ankleBone = Self.bump(point.y, legAcross < 0 ? 0.159 : 0.144, 0.022)
                    * Self.blend(abs(legAcross) / 0.025)
                let achilles = Self.bump(point.y, 0.186, 0.060) * Self.bump(legAcross, 0, 0.010)
                displacement.x += side * vertex.weights.z * tanh(legAcross / 0.017)
                    * (0.0025 * kneeRim + 0.0035 * ankleBone)
                displacement.z += vertex.weights.z * definition * (front * (0.002 * patellarTendon + 0.0015 * tibia)
                    - back * 0.0025 * achilles)
                return displacement
            }
            let masculineOffset = offset(feminine: false)
            let feminineOffset = offset(feminine: true)
            result.vertices[index].position += masculineOffset
            result.vertices[index].feminine += feminineOffset - masculineOffset
            result.vertices[index].anatomy += masculineOffset
            result.vertices[index].feminineAnatomy += feminineOffset - masculineOffset
        }
        return result
    }

    private static func blend(_ value: Float) -> Float {
        let fraction = min(max(value, 0), 1)
        return fraction * fraction * (3 - 2 * fraction)
    }

    private mutating func append(_ vertex: Vertex) -> Int {
        let index = vertices.count
        vertices.append(vertex)
        return index
    }

    private mutating func ring(count: Int, vertex: (Float) -> Vertex) -> [Int] {
        (0..<count).map { append(vertex(2 * .pi * Float($0) / Float(count))) }
    }

    private mutating func quad(_ first: Int, _ second: Int, _ third: Int, _ fourth: Int, region: Int) {
        faces.append(Face(indices: [first, second, third, fourth], region: region))
    }

    private mutating func tube(_ rings: [[Int]], region: Int) {
        for row in 0..<(rings.count - 1) {
            for column in rings[row].indices {
                let next = (column + 1) % rings[row].count
                quad(rings[row][column], rings[row + 1][column], rings[row + 1][next], rings[row][next], region: region)
            }
        }
    }

    private mutating func cap(_ loop: [Int], top: Bool, region: Int) {
        faces.append(Face(indices: top ? Array(loop.reversed()) : loop, region: region))
    }

    private static func opening(_ rings: [[Int]], rows: ClosedRange<Int>, column: Int, width: Int) -> [Int] {
        let count = rings[0].count
        let lower = rows.lowerBound
        let upper = rows.upperBound
        let last = column + width
        var loop = (column...last).map { rings[lower][$0 % count] }
        loop += ((lower + 1)...upper).map { rings[$0][last % count] }
        loop += (column..<last).reversed().map { rings[upper][$0 % count] }
        loop += ((lower + 1)..<upper).reversed().map { rings[$0][column % count] }
        return Array(loop.reversed())
    }

    private mutating func join(_ source: [Int], to destination: [Int], startingAt: Int? = nil, region: Int,
                               shape: ((Vertex) -> Vertex)? = nil) {
        guard source.count == destination.count else { return }
        let count = source.count
        let shift: Int
        if let startingAt, let index = destination.firstIndex(of: startingAt) {
            shift = index
        } else {
            shift = (0..<count).min { first, second in
                let firstCost = source.indices.reduce(Float.zero) {
                    $0 + simd_length_squared(vertices[source[$1]].position - vertices[destination[($1 + first) % count]].position)
                }
                let secondCost = source.indices.reduce(Float.zero) {
                    $0 + simd_length_squared(vertices[source[$1]].position - vertices[destination[($1 + second) % count]].position)
                }
                return firstCost < secondCost
            } ?? 0
        }
        let target = (0..<count).map { destination[($0 + shift) % count] }
        let middle = source.indices.map { index in
            let vertex = (vertices[source[index]] + vertices[target[index]]) * 0.5
            return append(shape?(vertex) ?? vertex)
        }
        tube([source, middle, target], region: region)
    }

    private func subdivided() -> Self {
        var result = Self(vertices: vertices)
        let centers = faces.map { face in face.indices.reduce(Vertex()) { $0 + vertices[$1] } * (1 / Float(face.indices.count)) }
        var edgeFaces: [Edge: [Int]] = [:]
        var vertexFaces = Array(repeating: [Int](), count: vertices.count)
        var neighbors = Array(repeating: Set<Int>(), count: vertices.count)
        for (faceIndex, face) in faces.enumerated() {
            for (corner, index) in face.indices.enumerated() {
                let next = face.indices[(corner + 1) % face.indices.count]
                edgeFaces[Edge(index, next), default: []].append(faceIndex)
                vertexFaces[index].append(faceIndex)
                neighbors[index].insert(next)
                neighbors[next].insert(index)
            }
        }
        var edgeIndices: [Edge: Int] = [:]
        for edge in edgeFaces.keys.sorted(by: { $0.first == $1.first ? $0.second < $1.second : $0.first < $1.first }) {
            let adjacent = edgeFaces[edge]!
            let endpoints = vertices[edge.first] + vertices[edge.second]
            let center = adjacent.count == 2
                ? (endpoints + centers[adjacent[0]] + centers[adjacent[1]]) * 0.25 : endpoints * 0.5
            edgeIndices[edge] = result.append(center)
        }
        for index in vertices.indices where !neighbors[index].isEmpty {
            let boundary = neighbors[index].filter { edgeFaces[Edge(index, $0)]?.count == 1 }
            if boundary.count == 2 {
                result.vertices[index] = vertices[index] * 0.75 + boundary.reduce(Vertex()) { $0 + vertices[$1] } * 0.125
            } else {
                let count = Float(neighbors[index].count)
                let faceMean = vertexFaces[index].reduce(Vertex()) { $0 + centers[$1] } * (1 / Float(vertexFaces[index].count))
                let edgeMean = neighbors[index].reduce(Vertex()) { $0 + (vertices[index] + vertices[$1]) * 0.5 } * (1 / count)
                result.vertices[index] = (faceMean + edgeMean * 2 + vertices[index] * (count - 3)) * (1 / count)
            }
        }
        let faceIndices = centers.map { result.append($0) }
        for (faceIndex, face) in faces.enumerated() {
            for (corner, index) in face.indices.enumerated() {
                let next = face.indices[(corner + 1) % face.indices.count]
                let previous = face.indices[(corner + face.indices.count - 1) % face.indices.count]
                result.quad(index, edgeIndices[Edge(index, next)]!, faceIndices[faceIndex], edgeIndices[Edge(previous, index)]!, region: face.region)
            }
        }
        return result
    }

    private static func bump(_ value: Float, _ center: Float, _ radius: Float) -> Float {
        let distance = (value - center) / radius
        return exp(-2 * distance * distance)
    }
}