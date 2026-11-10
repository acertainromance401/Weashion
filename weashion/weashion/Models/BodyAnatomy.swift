import Foundation
import simd

nonisolated struct BodyAnatomy: Decodable, Sendable {
    nonisolated enum Part: String, CaseIterable, Identifiable, Sendable {
        case head, neck, chest, abdomen, waist, pelvis
        case leftChestVolume, rightChestVolume
        case leftFlank, rightFlank, upperBack, lowerBack
        case leftButtock, rightButtock
        case leftShoulder, rightShoulder
        case leftUpperArm, rightUpperArm, leftElbow, rightElbow
        case leftForearm, rightForearm, leftWrist, rightWrist, leftHand, rightHand
        case leftThigh, rightThigh, leftKnee, rightKnee
        case leftCalf, rightCalf, leftAnkle, rightAnkle, leftFoot, rightFoot

        var id: String { rawValue }

        var adjustmentRange: ClosedRange<Double> {
            switch self {
            case .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftAnkle, .rightAnkle:
                0.9...1.1
            default:
                0.85...1.15
            }
        }

        var counterpart: Part? {
            if rawValue.hasPrefix("left") {
                return Part(rawValue: "right" + rawValue.dropFirst(4))
            }
            if rawValue.hasPrefix("right") {
                return Part(rawValue: "left" + rawValue.dropFirst(5))
            }
            return nil
        }

        fileprivate var axisLandmarks: (LandmarkID, LandmarkID)? {
            switch self {
            case .leftShoulder, .leftUpperArm: (.leftShoulder, .leftElbow)
            case .rightShoulder, .rightUpperArm: (.rightShoulder, .rightElbow)
            case .leftElbow: (.leftShoulder, .leftWrist)
            case .rightElbow: (.rightShoulder, .rightWrist)
            case .leftForearm, .leftWrist, .leftHand: (.leftElbow, .leftWrist)
            case .rightForearm, .rightWrist, .rightHand: (.rightElbow, .rightWrist)
            case .leftThigh: (.leftHip, .leftKnee)
            case .rightThigh: (.rightHip, .rightKnee)
            case .leftKnee: (.leftHip, .leftAnkle)
            case .rightKnee: (.rightHip, .rightAnkle)
            case .leftCalf, .leftAnkle: (.leftKnee, .leftAnkle)
            case .rightCalf, .rightAnkle: (.rightKnee, .rightAnkle)
            default: nil
            }
        }
    }

    nonisolated enum ShapeAdjustment: String, CaseIterable, Identifiable, Sendable {
        case torsoDepth = "shape.torsoDepth"
        case abdomenProjection = "shape.abdomenProjection"
        case breastSize = "shape.breastSize"
        case latissimusSize = "shape.latissimusSize"

        var id: String { rawValue }

        var isFemaleOnly: Bool { self == .breastSize }

        var title: String {
            switch self {
            case .torsoDepth: L("몸통 앞뒤 두께")
            case .abdomenProjection: L("복부 앞쪽 돌출")
            case .breastSize: L("유방 크기")
            case .latissimusSize: L("광배 크기")
            }
        }

        var adjustmentRange: ClosedRange<Double> {
            switch self {
            case .torsoDepth: 0.85...1.15
            case .abdomenProjection: 0.75...1.25
            case .breastSize: 0.65...1.50
            case .latissimusSize: 0.50...1.50
            }
        }

        func scale(in scales: [String: Double]) -> Double {
            guard let value = scales[rawValue], value.isFinite else { return 1 }
            return min(max(value, adjustmentRange.lowerBound), adjustmentRange.upperBound)
        }
    }

    nonisolated enum LandmarkID: String, CaseIterable, Sendable {
        case crown, chin, neckBase, chestCenter, waistCenter, pelvisCenter, crotch
        case leftShoulder, rightShoulder, leftElbow, rightElbow
        case leftWrist, rightWrist, leftHip, rightHip
        case leftKnee, rightKnee, leftAnkle, rightAnkle
        case leftHeel, rightHeel, leftToe, rightToe
    }

    nonisolated struct Binding: Decodable, Sendable {
        let indices: [UInt32]
        let weights: [Float]

        func isValid(vertexCount: Int) -> Bool {
            !indices.isEmpty && indices.count == weights.count
                && indices.allSatisfy { Int($0) < vertexCount }
                && zip(indices, indices.dropFirst()).allSatisfy { $0 < $1 }
                && weights.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1 }
        }
    }

    let version: Int
    let landmarkSource: String
    let parts: [String: Binding]
    let landmarks: [String: Binding]

    func isValid(vertexCount: Int) -> Bool {
        guard version == 1, landmarkSource == "surfaceEstimated",
              Set(parts.keys) == Set(Part.allCases.map(\.rawValue)),
              Set(landmarks.keys) == Set(LandmarkID.allCases.map(\.rawValue)),
              parts.values.allSatisfy({ $0.isValid(vertexCount: vertexCount) }),
              landmarks.values.allSatisfy({ $0.isValid(vertexCount: vertexCount)
                  && abs($0.weights.reduce(0, +) - 1) < 0.001 }) else { return false }
        var totals = Array(repeating: Float(0), count: vertexCount)
        for part in parts.values {
            for (index, weight) in zip(part.indices, part.weights) {
                totals[Int(index)] += weight
            }
        }
        return totals.allSatisfy { abs($0 - 1) < 0.001 }
    }

    func binding(for part: Part) -> Binding? {
        parts[part.rawValue]
    }

    func landmarkPositions(in vertices: [SIMD3<Float>]) -> [LandmarkID: SIMD3<Float>] {
        var result: [LandmarkID: SIMD3<Float>] = [:]
        for landmark in LandmarkID.allCases {
            guard let binding = landmarks[landmark.rawValue] else { continue }
            var position = SIMD3<Float>.zero
            for (index, weight) in zip(binding.indices, binding.weights) {
                position += vertices[Int(index)] * weight
            }
            result[landmark] = position
        }
        return result
    }

    func adjustedVertices(_ vertices: [SIMD3<Float>], scales: [String: Double],
                          feminine: Bool = false) -> [SIMD3<Float>] {
        guard !scales.isEmpty else { return vertices }
        return prepareDeformation(in: vertices, feminine: feminine).vertices(scales: scales)
    }

    nonisolated struct BreastMorphs: Sendable {
        let small: [SIMD3<Float>]
        let large: [SIMD3<Float>]
    }

    nonisolated struct Deformation: Sendable {
        fileprivate let source: [SIMD3<Float>]
        fileprivate let influences: [Influence]
        fileprivate let breastMorphs: BreastMorphs?
        fileprivate let latissimusOffsets: [SIMD3<Float>]
        fileprivate let pelvisHeight: Float
        fileprivate let chestHeight: Float
        fileprivate let crotchHeight: Float

        fileprivate nonisolated struct Influence: Sendable {
            let part: Part
            let indices: [UInt32]
            let offsets: [SIMD3<Float>]
            let weights: [Float]
            let progress: [Float]
        }

        func vertices(scales: [String: Double]) -> [SIMD3<Float>] {
            var result = source
            let depthAdjustment = Float(ShapeAdjustment.torsoDepth.scale(in: scales) - 1)
            let abdomenAdjustment = Float(ShapeAdjustment.abdomenProjection.scale(in: scales) - 1)
            for influence in influences {
                let value = scales[influence.part.rawValue] ?? 1
                let range = influence.part.adjustmentRange
                let scale = value.isFinite ? Float(min(max(value, range.lowerBound), range.upperBound) - 1) : 0
                let depth: Float
                switch influence.part {
                case .chest, .abdomen, .waist, .pelvis, .leftChestVolume, .rightChestVolume,
                     .leftFlank, .rightFlank, .upperBack, .lowerBack, .leftButtock, .rightButtock:
                    depth = depthAdjustment
                default:
                    depth = 0
                }
                let projection = influence.part == .abdomen ? abdomenAdjustment : 0
                let usesBreastMorph = breastMorphs != nil
                    && (influence.part == .leftChestVolume || influence.part == .rightChestVolume)
                guard (!usesBreastMorph && scale != 0) || depth != 0 || projection != 0 else { continue }
                for offsetIndex in influence.indices.indices {
                    let index = Int(influence.indices[offsetIndex])
                    let offset = influence.offsets[offsetIndex]
                    if !usesBreastMorph {
                        result[index] += offset * scale
                    }
                    result[index].z += offset.z * depth + max(offset.z, 0) * projection
                }
            }
            if let breastMorphs {
                let size = Float(ShapeAdjustment.breastSize.scale(in: scales))
                let partSizes: [Float] = [Part.leftChestVolume, .rightChestVolume].map { part in
                    let value = scales[part.rawValue] ?? 1
                    let range = part.adjustmentRange
                    return value.isFinite ? Float(min(max(value, range.lowerBound), range.upperBound)) : 1
                }
                for index in result.indices {
                    let side = min(max(0.5 + source[index].x / 0.04, 0), 1)
                    let blend = side * side * (3 - 2 * side)
                    let partSize = partSizes[0] + (partSizes[1] - partSizes[0]) * blend
                    let scale = min(max(size * partSize, 0.65), 1.50)
                    if scale < 1 {
                        result[index] += breastMorphs.small[index] * ((1 - scale) / 0.35)
                    } else if scale > 1 {
                        result[index] += breastMorphs.large[index] * ((scale - 1) / 0.50)
                    }
                }
            }
            let latissimus = Float(ShapeAdjustment.latissimusSize.scale(in: scales) - 1)
            if latissimus != 0 {
                for index in result.indices {
                    result[index] += latissimusOffsets[index] * latissimus
                }
            }
            return result
        }

        func vertices(profile: BodyShapeProfile) -> [SIMD3<Float>] {
            guard profile.feminine || profile.fat != 0 || profile.muscle != 0 else { return source }
            var result = source
            for influence in influences {
                for offsetIndex in influence.indices.indices {
                    let index = Int(influence.indices[offsetIndex])
                    let weight = influence.weights[offsetIndex]
                    let radial = influence.offsets[offsetIndex] / weight
                    let torsoProgress = (source[index].y - pelvisHeight) / max(chestHeight - pelvisHeight, 0.01)
                    result[index] += profile.offset(for: influence.part, radial: radial,
                        torsoProgress: torsoProgress, limbProgress: influence.progress[offsetIndex]) * weight
                }
            }
            for index in result.indices where source[index].y < crotchHeight - 0.025 * profile.stature {
                let side: Float = source[index].x < 0 ? -1 : 1
                let minimum = min(abs(source[index].x), 0.002 * profile.stature)
                result[index].x = side * max(result[index].x * side, minimum)
            }
            return result
        }
    }

    func prepareDeformation(in vertices: [SIMD3<Float>], feminine: Bool = false,
                            breastMorphs: BreastMorphs? = nil) -> Deformation {
        let anchors = landmarkPositions(in: vertices)
        var influences: [Deformation.Influence] = []
        for part in Part.allCases {
            guard let binding = binding(for: part) else { continue }
            var centroid = SIMD3<Float>.zero
            var total: Float = 0
            for (index, weight) in zip(binding.indices, binding.weights) {
                centroid += vertices[Int(index)] * weight
                total += weight
            }
            guard total > 0 else { continue }
            centroid /= total
            var origin = centroid
            var axis = SIMD3<Float>(0, 1, 0)
            var length: Float = 1
            if let endpoints = part.axisLandmarks, let start = anchors[endpoints.0], let end = anchors[endpoints.1] {
                let direction = end - start
                guard simd_length_squared(direction) > 0.000001 else { continue }
                origin = start
                axis = simd_normalize(direction)
                length = simd_length(direction)
            } else {
                let anchor: LandmarkID
                switch part {
                case .head, .neck: anchor = .neckBase
                case .chest, .leftChestVolume, .rightChestVolume, .upperBack: anchor = .chestCenter
                case .pelvis, .leftButtock, .rightButtock: anchor = .pelvisCenter
                case .leftFoot: anchor = .leftAnkle
                case .rightFoot: anchor = .rightAnkle
                default: anchor = .waistCenter
                }
                origin = anchors[anchor] ?? centroid
                if part == .leftChestVolume || part == .rightChestVolume {
                    origin.x = centroid.x
                }
            }
            let offsets = zip(binding.indices, binding.weights).map { index, weight in
                let offset = vertices[Int(index)] - origin
                let radial = offset - axis * simd_dot(offset, axis)
                return radial * weight
            }
            let progress = binding.indices.map { simd_dot(vertices[Int($0)] - origin, axis) / length }
            influences.append(.init(part: part, indices: binding.indices, offsets: offsets,
                                    weights: binding.weights, progress: progress))
        }
        var backWeights = Array(repeating: Float(0), count: vertices.count)
        for part in [Part.upperBack, .lowerBack, .leftFlank, .rightFlank] {
            guard let binding = binding(for: part) else { continue }
            for (index, weight) in zip(binding.indices, binding.weights) {
                backWeights[Int(index)] += weight
            }
        }
        let chest = anchors[.chestCenter] ?? SIMD3<Float>(0, 1.3, 0)
        let waist = anchors[.waistCenter] ?? SIMD3<Float>(0, 1.1, 0)
        let leftShoulder = anchors[.leftShoulder] ?? SIMD3<Float>(-0.2, 1.45, 0)
        let rightShoulder = anchors[.rightShoulder] ?? SIMD3<Float>(0.2, 1.45, 0)
        let shoulderHeight = (leftShoulder.y + rightShoulder.y) * 0.5
        let halfWidth = max(abs(rightShoulder.x - leftShoulder.x) * 0.5, 0.05)
        let torsoHeight = max(shoulderHeight - waist.y, 0.1)
        let latissimusOffsets = vertices.indices.map { index -> SIMD3<Float> in
            let relative = vertices[index] - chest
            let lateral = GarmentFitProfile.smoothBlend((abs(relative.x) / halfWidth - 0.30) / 0.35)
                * (1 - GarmentFitProfile.smoothBlend((abs(relative.x) / halfWidth - 0.80) / 0.25))
            let rear = GarmentFitProfile.smoothBlend((-relative.z - torsoHeight * 0.15) / (torsoHeight * 0.20))
            let vertical = exp(-pow((vertices[index].y - chest.y - (shoulderHeight - chest.y) * 0.25)
                / (torsoHeight * 0.55), 2))
            let lower = GarmentFitProfile.smoothBlend((vertices[index].y - waist.y + torsoHeight * 0.10) / (torsoHeight * 0.35))
            let upper = GarmentFitProfile.smoothBlend((shoulderHeight - vertices[index].y) / (torsoHeight * 0.20))
            let influence = min(backWeights[index], 1) * lateral * rear * vertical * lower * upper
            return SIMD3<Float>(relative.x * 0.16, 0, min(relative.z, 0) * 0.25) * influence
        }
        return Deformation(source: vertices, influences: influences,
                           breastMorphs: feminine ? breastMorphs : nil,
                           latissimusOffsets: latissimusOffsets,
                           pelvisHeight: anchors[.pelvisCenter]?.y ?? 0.9,
                           chestHeight: anchors[.chestCenter]?.y ?? 1.3,
                           crotchHeight: anchors[.crotch]?.y ?? 0.8)
    }
}