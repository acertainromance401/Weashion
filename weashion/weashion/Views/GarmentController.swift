import Foundation
import Observation
import RealityKit
import simd

@Observable
@MainActor
final class GarmentController {
    let root = Entity()
    private(set) var isSettling = false
    private(set) var fitMessage: String?
    private var request: Request?
    private var snapshot: GarmentBodySnapshot?
    private var settlingTask: Task<Void, Never>?
    private let draper = GarmentDraper.shared

    func update(definition: GarmentDefinition?, mannequin: WEASHIONMannequin) {
        guard let definition, mannequin.loadError == nil else {
            cancelSettling()
            for child in Array(root.children) { child.removeFromParent() }
            root.isEnabled = false
            fitMessage = nil
            return
        }
        let anchor = mannequin.garmentAnchor(definition.pattern.anchor ?? .shoulders)
        root.isEnabled = true
        let bodyKey = GarmentBodyKey(id: mannequin.garmentBodyID, revision: mannequin.garmentRevision, anchor: anchor)
        let next = Request(definition: definition, body: bodyKey)
        guard request != next else { return }
        let isBodyChange = request.map { $0.body != bodyKey } ?? false
        settlingTask?.cancel()
        request = next
        fitMessage = nil
        if snapshot?.key != bodyKey {
            let offset = mannequin.topGarmentAnchor - anchor
            snapshot = GarmentBodySnapshot(
                key: bodyKey,
                bands: mannequin.garmentCollisionBands.map { band in
                    GarmentCollisionBand(vertices: band.vertices.map { $0 + offset })
                },
                fitProfile: mannequin.garmentFitProfile?.translated(by: offset)
            )
        }
        guard let body = snapshot else { return }
        let worker = draper
        isSettling = true
        settlingTask = Task(priority: .userInitiated) { [weak self] in
            do {
                if isBodyChange { try await Task.sleep(for: .milliseconds(120)) }
                try Task.checkCancellation()
                let result = try await worker.settle(definition: definition, body: body)
                guard !Task.isCancelled, let self, self.request == next else { return }
                self.isSettling = false
                self.settlingTask = nil
                guard let model = GarmentRenderer.makeModel(asset: result.asset, positions: result.positions, appearance: definition.appearance) else {
                    for child in Array(self.root.children) { child.removeFromParent() }
                    self.fitMessage = "옷 모델을 표시하지 못했습니다"
                    return
                }
                model.name = definition.id
                for child in Array(self.root.children) { child.removeFromParent() }
                self.root.position = anchor
                self.root.addChild(model)
                if result.remainingOverlap > 0.002 {
                    self.fitMessage = "일부 영역에 겹침이 남아 있습니다"
                } else if result.maximumStrain > definition.material.maximumStrain {
                    self.fitMessage = "체형 보정이 커 실제 핏과 다를 수 있습니다"
                } else {
                    self.fitMessage = nil
                }
            } catch {
                guard !Task.isCancelled, let self, self.request == next else { return }
                self.isSettling = false
                self.settlingTask = nil
                for child in Array(self.root.children) { child.removeFromParent() }
                switch error as? GarmentDrapeError {
                case .invalidAsset:
                    self.fitMessage = "의류 데이터를 불러올 수 없습니다"
                case .initializationFailed:
                    self.fitMessage = "착장 표면을 준비하지 못했습니다"
                case .simulationFailed:
                    self.fitMessage = "신체 겹침 보정에 실패했습니다"
                case nil:
                    self.fitMessage = "옷을 표시하지 못했습니다"
                }
            }
        }
    }

    func cancelSettling() {
        settlingTask?.cancel()
        settlingTask = nil
        request = nil
        isSettling = false
    }

    private struct Request: Equatable {
        let definition: GarmentDefinition
        let body: GarmentBodyKey
    }
}