import Observation
import RealityKit
import simd
import UIKit

enum MannequinBase: String, CaseIterable, Identifiable, Codable {
    case male
    case female

    var id: String { rawValue }
}

nonisolated struct GarmentCollisionMesh: Sendable {
    var vertices: [SIMD3<Float>]
    var indices: [UInt32]
    var armTriangles: [UInt8]
}

@Observable
@MainActor
final class WEASHIONMannequin {
    let root = Entity()
    private var barefootWaistAnchor = SIMD3<Float>(0, 1.1, 0)
    private var barefootTopAnchor = SIMD3<Float>(0, 1.505, 0)
    var garmentWaistAnchor: SIMD3<Float> { barefootWaistAnchor + root.position }
    var topGarmentAnchor: SIMD3<Float> { barefootTopAnchor + root.position }
    private(set) var garmentFitProfile: GarmentBodyFitProfile?
    private(set) var garmentCollisionMesh: GarmentCollisionMesh?
    private(set) var bodyAnatomy: BodyAnatomy?
    private(set) var bodyLandmarks: [BodyAnatomy.LandmarkID: SIMD3<Float>] = [:]
    private(set) var loadError: String?
    private(set) var surfaceRevision: UInt64 = 0

    private static let material = SimpleMaterial(color: UIColor(white: 0.84, alpha: 1), roughness: 0.48, isMetallic: false)

    private let skin = ModelEntity()
    private(set) var garmentBodyRequest: BodyPreviewRenderer.Request?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPreview: BodyPreviewRenderer.Request?
    @ObservationIgnored private var previewGeneration = 0
    @ObservationIgnored private var nextPreviewUpdate = ContinuousClock.now

    init() {
        root.name = "WEASHION_Mannequin"
        skin.name = "WEASHION_ImportedBody"
        root.addChild(skin)
    }

    func garmentAnchor(_ anchor: GarmentAnchor) -> SIMD3<Float> {
        switch anchor {
        case .shoulders: topGarmentAnchor
        case .waist: garmentWaistAnchor
        case .feet: root.position
        }
    }

    func setFootwearElevation(_ height: Float) {
        guard root.position.y != height else { return }
        root.position.y = height
        surfaceRevision &+= 1
    }

    func applyPreview(_ prepared: BodySurfaceMesh.Prepared) async throws {
        let model = try await prepared.model(material: Self.material)
        try Task.checkCancellation()
        skin.model = model
        skin.isEnabled = true
        loadError = nil
        surfaceRevision &+= 1
    }

    func previewFailed() {
        loadError = L("신체 미리보기를 생성할 수 없습니다")
    }

    func requestPreview(_ request: BodyPreviewRenderer.Request) {
        pendingPreview = request
        guard previewTask == nil else { return }
        previewGeneration += 1
        let generation = previewGeneration
        previewTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if previewGeneration == generation { previewTask = nil }
            }
            while pendingPreview != nil && !Task.isCancelled {
                do {
                    try await Task.sleep(until: nextPreviewUpdate, clock: .continuous)
                    try Task.checkCancellation()
                    guard let latest = pendingPreview else { break }
                    pendingPreview = nil
                    nextPreviewUpdate = .now.advanced(by: .milliseconds(40))
                    guard let prepared = try await BodyPreviewRenderer.shared.render(latest) else {
                        try Task.checkCancellation()
                        if pendingPreview == nil { previewFailed() }
                        continue
                    }
                    try Task.checkCancellation()
                    if let pending = pendingPreview, pending.base != latest.base { continue }
                    try await applyPreview(prepared)
                } catch {
                    if Task.isCancelled { break }
                    if pendingPreview == nil { previewFailed() }
                }
            }
        }
    }

    func cancelPreview() {
        previewGeneration += 1
        previewTask?.cancel()
        previewTask = nil
        pendingPreview = nil
    }

    func prepareFitting(_ request: BodyPreviewRenderer.Request) async throws {
        try Task.checkCancellation()
        guard request != garmentBodyRequest else { return }
        skin.isEnabled = false
        garmentBodyRequest = nil
        loadError = nil
        surfaceRevision &+= 1
        let prepared = try await BodyPreviewRenderer.shared.prepareFitting(request)
        let model = try await prepared.surface.model(material: Self.material)
        try Task.checkCancellation()
        let fitted = prepared.fitted
        loadError = nil
        garmentBodyRequest = request
        skin.isEnabled = true
        skin.model = model
        barefootTopAnchor = fitted.anchor
        barefootWaistAnchor = fitted.profile.waist.center + fitted.anchor
        garmentFitProfile = fitted.profile
        garmentCollisionMesh = fitted.collisionMesh
        bodyAnatomy = fitted.anatomy
        bodyLandmarks = fitted.landmarks
        surfaceRevision &+= 1
    }

    func fittingFailed() {
        skin.isEnabled = false
        garmentBodyRequest = nil
        bodyAnatomy = nil
        bodyLandmarks = [:]
        loadError = L("신체 에셋을 불러올 수 없습니다")
        surfaceRevision &+= 1
    }
}