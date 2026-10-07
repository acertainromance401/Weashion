import Observation
import RealityKit
import simd
import UIKit

enum MannequinBase: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }
}

nonisolated struct GarmentCollisionBand: Sendable {
    let vertices: [SIMD3<Float>]
}

@Observable
@MainActor
final class WEASHIONMannequin {
    let root = Entity()
    let garmentBodyID = UUID()
    private(set) var garmentRevision = 0
    private(set) var garmentWaistAnchor = SIMD3<Float>(0, 1.1, 0)
    private(set) var topGarmentAnchor = SIMD3<Float>(0, 1.505, 0)
    private(set) var garmentFitProfile: GarmentBodyFitProfile?
    private(set) var garmentCollisionBands: [GarmentCollisionBand] = []
    private(set) var loadError: String?

    private static let maleMesh = MannequinMesh.load(resource: "male_body_40k")
    private static let femaleMesh = MannequinMesh.load(resource: "female_body_40k")
    private static let material = SimpleMaterial(color: UIColor(white: 0.84, alpha: 1), roughness: 0.48, isMetallic: false)

    private let skin = ModelEntity()
    private var lastMeasurements: [Double] = []
    private var lastBase: MannequinBase?

    init() {
        root.name = "WEASHION_Mannequin"
        skin.name = "WEASHION_ImportedBody"
        root.addChild(skin)
    }

    func garmentAnchor(_ anchor: GarmentAnchor) -> SIMD3<Float> {
        anchor == .waist ? garmentWaistAnchor : topGarmentAnchor
    }

    func update(body: UserBody, base: MannequinBase = .male) {
        let values = [body.height, body.weight, body.shoulderWidth, body.chest, body.waist,
                      body.hip, body.legLength, body.armSize, body.legSize]
        guard values != lastMeasurements || base != lastBase else { return }
        let measurements = ParametricBody.Measurements(
            height: Float(body.height / 100), weight: Float(body.weight), shoulderWidth: Float(body.shoulderWidth / 100),
            chest: Float(body.chest / 100), waist: Float(body.waist / 100), hip: Float(body.hip / 100),
            inseam: Float(body.legLength / 100), armSize: Float(body.armSize), legSize: Float(body.legSize), feminine: base == .female)
        lastMeasurements = values
        lastBase = base
        guard let mesh = base == .female ? Self.femaleMesh : Self.maleMesh,
              let fitted = mesh.fitted(to: measurements),
              let model = fitted.surface.model(material: Self.material) else {
            skin.isEnabled = false
            loadError = "신체 에셋을 불러올 수 없습니다"
            return
        }
        loadError = nil
        skin.isEnabled = true
        skin.model = model
        topGarmentAnchor = fitted.anchor
        garmentWaistAnchor = fitted.profile.waist.center + fitted.anchor
        garmentFitProfile = fitted.profile
        garmentCollisionBands = fitted.collisionBands
        garmentRevision += 1
    }
}