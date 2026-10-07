import simd

nonisolated struct BodySkeleton {
    nonisolated enum Joint: Int, CaseIterable {
        case pelvis, lumbar, chest, neck, head
        case rightClavicle, rightShoulder, rightElbow, rightWrist, rightPalm
        case leftClavicle, leftShoulder, leftElbow, leftWrist, leftPalm
        case rightHip, rightKnee, rightAnkle, rightFoot
        case leftHip, leftKnee, leftAnkle, leftFoot

        var parent: Joint? {
            switch self {
            case .pelvis: nil
            case .lumbar, .rightHip, .leftHip: .pelvis
            case .chest: .lumbar
            case .neck, .rightClavicle, .leftClavicle: .chest
            case .head: .neck
            case .rightShoulder: .rightClavicle
            case .rightElbow: .rightShoulder
            case .rightWrist: .rightElbow
            case .rightPalm: .rightWrist
            case .leftShoulder: .leftClavicle
            case .leftElbow: .leftShoulder
            case .leftWrist: .leftElbow
            case .leftPalm: .leftWrist
            case .rightKnee: .rightHip
            case .rightAnkle: .rightKnee
            case .rightFoot: .rightAnkle
            case .leftKnee: .leftHip
            case .leftAnkle: .leftKnee
            case .leftFoot: .leftAnkle
            }
        }

        var endpoint: Joint? {
            switch self {
            case .pelvis: .lumbar
            case .lumbar: .chest
            case .chest: .neck
            case .neck: .head
            case .rightClavicle: .rightShoulder
            case .rightShoulder: .rightElbow
            case .rightElbow: .rightWrist
            case .rightWrist: .rightPalm
            case .leftClavicle: .leftShoulder
            case .leftShoulder: .leftElbow
            case .leftElbow: .leftWrist
            case .leftWrist: .leftPalm
            case .rightHip: .rightKnee
            case .rightKnee: .rightAnkle
            case .rightAnkle: .rightFoot
            case .leftHip: .leftKnee
            case .leftKnee: .leftAnkle
            case .leftAnkle: .leftFoot
            case .head, .rightPalm, .leftPalm, .rightFoot, .leftFoot: nil
            }
        }
    }

    nonisolated struct Influence {
        let joint: Joint
        let weight: Float
    }

    static let referencePositions: [SIMD3<Float>] = [
        [0, 0.94, 0], [0, 1.105, 0], [0, 1.285, 0], [0, 1.477, 0], [0, 1.532, 0],
        [0.055, 1.435, 0], [0.190, 1.43, 0], [0.232, 1.125, -0.013], [0.258, 0.88, 0.023], [0.264, 0.772, 0.033],
        [-0.055, 1.435, 0], [-0.190, 1.43, 0], [-0.232, 1.125, -0.013], [-0.258, 0.88, 0.023], [-0.264, 0.772, 0.033],
        [0.097, 0.94, 0], [0.075, 0.465, 0], [0.085, 0.14, 0], [0.085, 0.022, 0.13],
        [-0.097, 0.94, 0], [-0.075, 0.465, 0], [-0.085, 0.14, 0], [-0.085, 0.022, 0.13]
    ]

    let bindTransforms: [simd_float4x4]
    private let inverseBindTransforms: [simd_float4x4]
    private(set) var localTransforms: [simd_float4x4]
    private(set) var worldTransforms: [simd_float4x4]
    private(set) var skinTransforms: [simd_float4x4]
    private let lengthScales: [Float]
    private var rotations: [simd_quatf]
    private var dualRotations: [SIMD4<Float>]

    init(positions: [SIMD3<Float>], orientations: [Joint: simd_quatf] = [:]) {
        precondition(positions.count == Joint.allCases.count)
        bindTransforms = Self.frames(positions: Self.referencePositions)
        inverseBindTransforms = bindTransforms.map(\.inverse)
        let targets = Self.frames(positions: positions, orientations: orientations)
        localTransforms = Joint.allCases.map { joint in
            guard let parent = joint.parent else { return targets[joint.rawValue] }
            return targets[parent.rawValue].inverse * targets[joint.rawValue]
        }
        lengthScales = Joint.allCases.map { joint in
            guard let endpoint = joint.endpoint else { return 1 }
            return simd_distance(positions[joint.rawValue], positions[endpoint.rawValue])
                / simd_distance(Self.referencePositions[joint.rawValue], Self.referencePositions[endpoint.rawValue])
        }
        worldTransforms = targets
        skinTransforms = Array(repeating: matrix_identity_float4x4, count: targets.count)
        rotations = Array(repeating: simd_quatf(angle: 0, axis: [0, 1, 0]), count: targets.count)
        dualRotations = Array(repeating: .zero, count: targets.count)
        updateTransforms()
    }

    func position(of joint: Joint) -> SIMD3<Float> {
        let translation = worldTransforms[joint.rawValue].columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }

    mutating func rotate(_ joint: Joint, by rotation: simd_quatf) {
        localTransforms[joint.rawValue] *= simd_float4x4(rotation)
        updateTransforms()
    }

    func attachmentTransform(at origin: SIMD3<Float>, joint: Joint, radialScale: Float) -> simd_float4x4 {
        let index = joint.rawValue
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4<Float>(origin, 1)
        let scale = simd_float4x4(diagonal: SIMD4<Float>(radialScale, lengthScales[index], radialScale, 1))
        return worldTransforms[index] * scale * inverseBindTransforms[index] * translation
    }

    func deform(_ point: SIMD3<Float>, influences: [Influence], radialScale: Float = 1) -> SIMD3<Float> {
        guard let first = influences.first else { return point }
        let source = SIMD4<Float>(point, 1)
        var stretched = SIMD3<Float>.zero
        var real = SIMD4<Float>.zero
        var dual = SIMD4<Float>.zero
        let reference = rotations[first.joint.rawValue].vector
        for influence in influences {
            let index = influence.joint.rawValue
            var local = inverseBindTransforms[index] * source
            local.x *= radialScale
            local.z *= radialScale
            local.y *= lengthScales[index]
            let scaled = bindTransforms[index] * local
            stretched += SIMD3<Float>(scaled.x, scaled.y, scaled.z) * influence.weight
            let hemisphere: Float = simd_dot(reference, rotations[index].vector) < 0 ? -1 : 1
            real += rotations[index].vector * (influence.weight * hemisphere)
            dual += dualRotations[index] * (influence.weight * hemisphere)
        }
        let magnitude = simd_length(real)
        guard magnitude > 0.000001 else { return point }
        real /= magnitude
        dual /= magnitude
        dual -= real * simd_dot(real, dual)
        let rotation = simd_quatf(vector: real)
        let translation = (simd_quatf(vector: dual) * rotation.conjugate).imag * 2
        return rotation.act(stretched) + translation
    }

    private mutating func updateTransforms() {
        for joint in Joint.allCases {
            let index = joint.rawValue
            worldTransforms[index] = joint.parent.map { worldTransforms[$0.rawValue] * localTransforms[index] }
                ?? localTransforms[index]
            let stretch = simd_float4x4(diagonal: SIMD4<Float>(1, lengthScales[index], 1, 1))
            skinTransforms[index] = worldTransforms[index] * stretch * inverseBindTransforms[index]
            let rigid = worldTransforms[index] * inverseBindTransforms[index]
            rotations[index] = simd_quatf(rigid)
            let translation = rigid.columns.3
            dualRotations[index] = (simd_quatf(ix: translation.x, iy: translation.y, iz: translation.z, r: 0)
                * rotations[index]).vector * 0.5
        }
    }

    static func chain(_ joints: [Joint], heights: [Float], at height: Float, transition: Float) -> [Influence] {
        for index in 0..<(joints.count - 1) {
            let center = heights[index]
            if height < center - transition { return [.init(joint: joints[index], weight: 1)] }
            if height <= center + transition {
                let fraction = min(max((height - center + transition) / (2 * transition), 0), 1)
                let blend = fraction * fraction * (3 - 2 * fraction)
                return [.init(joint: joints[index], weight: 1 - blend), .init(joint: joints[index + 1], weight: blend)]
            }
        }
        return [.init(joint: joints.last!, weight: 1)]
    }

    private static func frames(positions: [SIMD3<Float>], orientations: [Joint: simd_quatf] = [:]) -> [simd_float4x4] {
        Joint.allCases.map { joint in
            let position = positions[joint.rawValue]
            let direction = joint.endpoint.map { simd_normalize(positions[$0.rawValue] - position) } ?? SIMD3<Float>(0, 1, 0)
            var transform = simd_float4x4(orientations[joint] ?? simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction))
            transform.columns.3 = SIMD4<Float>(position, 1)
            return transform
        }
    }
}