import Foundation
import simd

nonisolated enum FemaleBodyFramePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case neutral, straight, wave, natural

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutral: L("기본")
        case .straight: L("스트레이트")
        case .wave: L("웨이브")
        case .natural: L("내추럴")
        }
    }
}

nonisolated enum BodyShapePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case slim, standard, full, muscular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slim: L("마름")
        case .standard: L("보통")
        case .full: L("지방형")
        case .muscular: L("근육형")
        }
    }
}

nonisolated struct BodyShapeProfile: Hashable, Sendable {
    let preset: BodyShapePreset
    let feminine: Bool
    let framePreset: FemaleBodyFramePreset
    let stature: Float
    let fat: Float
    let muscle: Float

    init(preset: BodyShapePreset, height: Double, weight: Double, feminine: Bool = false,
         framePreset: FemaleBodyFramePreset = .neutral) {
        self.preset = preset
        self.feminine = feminine
        self.framePreset = feminine ? framePreset : .neutral
        let referenceHeight = feminine ? 1.60 : 1.75
        let referenceWeight = feminine ? 57.5 : 70.0
        let heightMeters = height.isFinite ? min(max(height / 100, 1), 2.5) : referenceHeight
        let kilograms = weight.isFinite ? min(max(weight, 25), 250) : referenceWeight
        stature = Float(heightMeters / referenceHeight)
        let intensity = Float(tanh((kilograms / (heightMeters * heightMeters)
            - referenceWeight / (referenceHeight * referenceHeight)) / 9))
        switch preset {
        case .slim:
            fat = feminine ? -0.25 + intensity * 0.32 : -0.30 + intensity * 0.38
            muscle = feminine ? -0.12 + intensity * 0.14 : -0.16 + intensity * 0.16
        case .standard:
            fat = feminine ? intensity * 0.60 : 0.06 + intensity * 0.70
            muscle = intensity * (feminine ? 0.14 : 0.18)
        case .full:
            fat = feminine ? 0.38 + intensity * 0.55 : 0.42 + intensity * 0.65
            muscle = intensity * (feminine ? 0.06 : 0.08)
        case .muscular:
            fat = feminine ? -0.10 + intensity * 0.22 : -0.12 + intensity * 0.28
            muscle = feminine ? 0.40 + intensity * 0.34 : 0.50 + intensity * 0.42
        }
    }

    var referenceCircumferences: SIMD3<Float> {
        (feminine ? SIMD3<Float>(0.92, 0.70, 0.85) : SIMD3<Float>(0.98, 0.82, 0.98)) * stature
    }

    var estimatedCircumferences: SIMD3<Float> {
        if feminine {
            return referenceCircumferences * SIMD3<Float>(
                1 + fat * 0.22 + muscle * 0.14,
                1 + fat * 0.20 + muscle * 0.02,
                1 + fat * 0.14 + muscle * 0.045)
        }
        return referenceCircumferences * SIMD3<Float>(
            1 + fat * 0.12 + muscle * 0.06,
            1 + fat * 0.24 + muscle * 0.02,
            1 + fat * 0.12 + muscle * 0.18)
    }

    func offset(for part: BodyAnatomy.Part, radial: SIMD3<Float>, torsoProgress: Float,
                limbProgress: Float) -> SIMD3<Float> {
        let front = max(radial.z, 0)
        let back = min(radial.z, 0)
        let belly = exp(-pow((torsoProgress - 0.48) / 0.35, 2))
        let bellyFront = front / max(abs(radial.z) + abs(radial.x) * 0.35, 0.001)
        let limbFullness = sin(Float.pi * min(max(limbProgress, 0), 1))
        var baseOffset = SIMD3<Float>.zero
        var fatOffset = SIMD3<Float>.zero
        var muscleOffset = SIMD3<Float>.zero
        switch part {
        case .abdomen:
            fatOffset = [radial.x * 0.24, 0, front * 0.20 + 0.075 * stature * belly * bellyFront]
            muscleOffset = [radial.x * 0.04, 0, front * 0.025]
        case .waist:
            fatOffset = [radial.x * 0.28, 0, front * 0.18 + 0.025 * stature * belly * bellyFront]
            muscleOffset = [radial.x * 0.04, 0, front * 0.025]
        case .leftFlank, .rightFlank:
            fatOffset = [radial.x * 0.32, 0, radial.z * 0.22]
            muscleOffset = [radial.x * 0.025, 0, radial.z * 0.025]
        case .lowerBack:
            fatOffset = [radial.x * 0.12, 0, back * 0.32]
            muscleOffset = [radial.x * 0.08, 0, back * 0.12]
        case .chest, .leftChestVolume, .rightChestVolume:
            let lower = 1 - min(max(torsoProgress, 0), 1)
            fatOffset = [radial.x * 0.12, 0, front * (0.25 + lower * 0.35)]
            muscleOffset = [radial.x * 0.28, 0, front * 0.40]
        case .upperBack:
            fatOffset = [radial.x * 0.10, 0, back * 0.20]
            muscleOffset = [radial.x * 0.28, 0, back * 0.32]
        case .pelvis:
            fatOffset = [radial.x * 0.12, 0, front * 0.14]
        case .leftButtock, .rightButtock:
            fatOffset = [radial.x * 0.17, 0, back * 0.32]
            muscleOffset = [radial.x * 0.10, 0, back * 0.28]
        case .leftShoulder, .rightShoulder:
            fatOffset = radial * 0.10
            muscleOffset = radial * 0.45
        case .leftUpperArm, .rightUpperArm:
            fatOffset = radial * (0.18 + limbFullness * 0.14)
            fatOffset.z += back * 0.12
            muscleOffset = radial * (0.24 + limbFullness * 0.36)
        case .leftForearm, .rightForearm:
            fatOffset = radial * (0.09 + limbFullness * 0.04)
            muscleOffset = radial * (0.12 + limbFullness * 0.20)
        case .leftThigh, .rightThigh:
            fatOffset = radial * (0.16 + limbFullness * 0.14)
            fatOffset.z += back * 0.10
            muscleOffset = radial * (0.16 + limbFullness * 0.28)
            muscleOffset.z += front * 0.10
        case .leftCalf, .rightCalf:
            fatOffset = radial * (0.07 + limbFullness * 0.04)
            muscleOffset = radial * (0.10 + limbFullness * 0.28)
            muscleOffset.z += back * 0.16 * limbFullness
        case .leftKnee, .rightKnee, .leftElbow, .rightElbow:
            fatOffset = radial * 0.06
        case .neck:
            fatOffset = radial * 0.08
            muscleOffset = radial * 0.06
        default:
            break
        }
        if feminine {
            switch part {
            case .abdomen, .waist:
                fatOffset *= SIMD3<Float>(0.95, 1, 0.80)
                muscleOffset *= 0.80
            case .leftFlank, .rightFlank:
                fatOffset *= 0.95
            case .chest:
                muscleOffset *= SIMD3<Float>(0.55, 1, 0.40)
            case .leftChestVolume, .rightChestVolume:
                fatOffset *= 0.80
                muscleOffset *= 0.12
            case .upperBack:
                muscleOffset *= 0.75
            case .pelvis:
                fatOffset *= SIMD3<Float>(1.70, 1, 1.10)
            case .leftButtock, .rightButtock:
                fatOffset *= 1.35
            case .leftShoulder, .rightShoulder:
                fatOffset *= 0.90
                muscleOffset *= 0.70
            case .leftUpperArm, .rightUpperArm:
                fatOffset *= 1.25
                muscleOffset *= 0.80
            case .leftThigh, .rightThigh:
                fatOffset *= 1.40
                muscleOffset *= 0.90
            default:
                break
            }
        } else {
            switch part {
            case .abdomen:
                fatOffset *= SIMD3<Float>(1.10, 1, 1.20)
            case .waist, .leftFlank, .rightFlank:
                fatOffset *= 1.15
            case .lowerBack, .chest, .leftChestVolume, .rightChestVolume:
                fatOffset *= 1.10
            case .leftButtock, .rightButtock, .leftThigh, .rightThigh:
                fatOffset *= 0.90
            default:
                break
            }
        }
        var result = baseOffset + fatOffset * fat + muscleOffset * muscle
        result.y = 0
        return result
    }
}