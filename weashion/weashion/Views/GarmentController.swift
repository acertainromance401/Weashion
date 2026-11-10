import Foundation
import Observation
import RealityKit
import simd

enum GarmentFittingPhase {
    case preparing, correcting, displaying

    var title: String {
        switch self {
        case .preparing: L("의류 표면 준비 중")
        case .correcting: L("신체·안쪽 옷 겹침 보정 중")
        case .displaying: L("착장 화면 준비 중")
        }
    }
}

@Observable
@MainActor
final class GarmentController {
    let root = Entity()
    private(set) var isSettling = false
    private(set) var fitMessage: String?
    private(set) var fitSummary: GarmentFitSummary?
    private(set) var settlementRequestCount = 0
    private(set) var surfaceRevision: UInt64 = 0
    private var request: Request?
    private var snapshot: GarmentBodySnapshot?
    private var settlingTask: Task<Void, Never>?
    private let draper = GarmentDraper.shared
    private var slots: [OutfitSlot: GarmentController] = [:]
    private var outfitRequest: OutfitRequest?
    private var fittedResult: GarmentDrapeResult?
    private(set) var slotMessages: [OutfitSlot: String] = [:]
    private(set) var visibleSlots = Set<OutfitSlot>()
    private(set) var fittedResults: [OutfitSlot: GarmentDrapeResult] = [:]
    private var focusedSlot: OutfitSlot?
    private(set) var fittingPhase: GarmentFittingPhase?
    private(set) var activeSlot: OutfitSlot?
    private(set) var wasCancelled = false

    var activeFittingPhase: GarmentFittingPhase? {
        activeSlot.flatMap { slots[$0]?.fittingPhase } ?? fittingPhase
    }

    var completedSlotCount: Int { visibleSlots.count }
    var requestedSlotCount: Int { outfitRequest?.definitions.count ?? (request == nil ? 0 : 1) }

    func update(outfit: [GarmentDefinition], focused: GarmentDefinition?, mannequin: WEASHIONMannequin) {
        guard let body = mannequin.garmentBodyRequest, mannequin.loadError == nil else {
            update(definition: nil, mannequin: mannequin)
            return
        }
        focusedSlot = focused?.kind.slot
        let next = OutfitRequest(definitions: outfit, body: body)
        if outfitRequest == next {
            fitSummary = focused.flatMap { visibleSlots.contains($0.kind.slot) ? slots[$0.kind.slot]?.fitSummary : nil }
            return
        }
        settlingTask?.cancel()
        request = nil
        for controller in slots.values where controller.isSettling { controller.cancelSettling() }
        outfitRequest = next
        wasCancelled = false
        activeSlot = nil
        settlementRequestCount += 1
        fitSummary = nil
        fitMessage = nil
        slotMessages = [:]
        visibleSlots = []
        fittedResults = [:]
        root.isEnabled = !outfit.isEmpty
        // All solver inputs stay barefoot; one shared display offset raises the entire outfit.
        mannequin.setFootwearElevation(0)
        root.position = .zero
        for child in Array(root.children) { child.removeFromParent() }
        let active = Set(outfit.map { $0.kind.slot })
        for slot in Array(slots.keys) where !active.contains(slot) {
            slots.removeValue(forKey: slot)?.cancelSettling()
        }
        isSettling = !outfit.isEmpty
        surfaceRevision &+= 1
        settlingTask = Task { [weak self] in
            guard let self else { return }
            var layers: [GarmentCollisionLayer] = []
            var elevation: Float = 0
            for slot in OutfitSlot.fittingOrder {
                guard !Task.isCancelled, self.outfitRequest == next else { return }
                guard let definition = outfit.first(where: { $0.kind.slot == slot }) else { continue }
                let controller = self.slots[slot] ?? GarmentController()
                self.slots[slot] = controller
                self.activeSlot = slot
                self.root.addChild(controller.root)
                controller.update(definition: definition, mannequin: mannequin, layers: layers, managesElevation: false,
                                  onPreview: { [weak self] in self?.surfaceRevision &+= 1 })
                await controller.settlingTask?.value
                guard !Task.isCancelled, self.outfitRequest == next else { return }
                if let message = controller.fitMessage { self.slotMessages[slot] = message }
                if controller.root.isEnabled, let result = controller.fittedResult {
                    self.root.addChild(controller.root)
                    self.visibleSlots.insert(slot)
                    self.fittedResults[slot] = result
                    elevation = max(elevation, result.asset.footwear?.soleThickness ?? 0)
                    let anchor = controller.root.position
                    layers.append(.init(
                        key: .init(pattern: definition.pattern, fabric: definition.material.fabricSettings),
                        surface: .init(vertices: result.positions.map { $0 + anchor },
                                       indices: result.asset.indices,
                                       armTriangles: result.asset.collisionArmTriangles)
                    ))
                } else {
                    // A missing inner surface must not be presented as a successfully layered outer fit.
                    break
                }
                if slot == self.focusedSlot { self.fitSummary = controller.fitSummary }
                self.surfaceRevision &+= 1
                await Task.yield()
            }
            guard !Task.isCancelled, self.outfitRequest == next else { return }
            mannequin.setFootwearElevation(elevation)
            self.root.position.y = elevation
            self.root.isEnabled = !self.visibleSlots.isEmpty
            self.fitSummary = self.focusedSlot.flatMap { self.visibleSlots.contains($0) ? self.slots[$0]?.fitSummary : nil }
            self.fitMessage = OutfitSlot.fittingOrder.compactMap { slot in
                self.slotMessages[slot].map { "\(slot.title): \($0)" }
            }.joined(separator: "\n")
            if self.fitMessage?.isEmpty == true { self.fitMessage = nil }
            self.isSettling = false
            self.activeSlot = nil
            self.settlingTask = nil
            self.surfaceRevision &+= 1
        }
    }

    func update(definition: GarmentDefinition?, mannequin: WEASHIONMannequin,
                layers: [GarmentCollisionLayer] = [], managesElevation: Bool = true,
                onPreview: (() -> Void)? = nil) {
        guard let definition, mannequin.loadError == nil, let bodyRequest = mannequin.garmentBodyRequest else {
            if managesElevation { mannequin.setFootwearElevation(0) }
            cancelSettling()
            let changed = root.isEnabled || !root.children.isEmpty
            for child in Array(root.children) { child.removeFromParent() }
            root.isEnabled = false
            fitMessage = nil
            fitSummary = nil
            fittedResult = nil
            fittedResults = [:]
            visibleSlots = []
            if changed { surfaceRevision &+= 1 }
            return
        }
        if managesElevation, definition.kind != .shoes { mannequin.setFootwearElevation(0) }
        let anchor = mannequin.garmentAnchor(definition.pattern.anchor ?? .shoulders)
        let bodyKey = GarmentBodyKey(body: bodyRequest, anchor: anchor)
        let next = Request(definition: definition, body: bodyKey, layers: layers.map(\.key))
        guard request != next else { return }
        settlementRequestCount += 1
        let shouldDebounce = request.map {
            $0.body != bodyKey || ($0.definition.id == definition.id
                && ($0.definition.pattern != definition.pattern
                    || $0.definition.material.fabricSettings != definition.material.fabricSettings))
        } ?? false
        settlingTask?.cancel()
        // Never present the previous garment as the result of the new measurements.
        root.isEnabled = false
        surfaceRevision &+= 1
        request = next
        wasCancelled = false
        fittingPhase = .preparing
        fitMessage = nil
        fitSummary = nil
        fittedResult = nil
        if snapshot?.key != bodyKey || snapshot?.layers.map(\.key) != layers.map(\.key) {
            let offset = mannequin.topGarmentAnchor - anchor
            snapshot = GarmentBodySnapshot(
                key: bodyKey,
                collision: mannequin.garmentCollisionMesh.map { mesh in
                    GarmentCollisionMesh(vertices: mesh.vertices.map { $0 + offset }, indices: mesh.indices,
                                         armTriangles: mesh.armTriangles)
                },
                fitProfile: mannequin.garmentFitProfile?.translated(by: offset),
                layers: layers.map { layer in
                    .init(key: layer.key, surface: .init(
                        vertices: layer.surface.vertices.map { $0 - anchor },
                        indices: layer.surface.indices, armTriangles: layer.surface.armTriangles))
                }
            )
        }
        guard let body = snapshot else { return }
        let worker = draper
        isSettling = true
        settlingTask = Task(priority: .userInitiated) { [weak self] in
            do {
                if shouldDebounce { try await Task.sleep(for: .milliseconds(120)) }
                try Task.checkCancellation()
                let preview = try await worker.preview(definition: definition, body: body)
                guard !Task.isCancelled, let self, self.request == next else { return }
                guard let previewModel = GarmentRenderer.makeModel(
                    asset: preview.asset, positions: preview.positions, display: preview.surface,
                    appearance: definition.appearance) else { throw GarmentDrapeError.initializationFailed }
                previewModel.name = definition.id
                for child in Array(self.root.children) { child.removeFromParent() }
                self.root.position = definition.kind == .shoes ? .zero : anchor
                self.root.addChild(previewModel)
                self.root.isEnabled = true
                self.surfaceRevision &+= 1
                onPreview?()
                self.fittingPhase = .correcting
                let result = try await worker.settle(definition: definition, body: body)
                guard !Task.isCancelled, self.request == next else { return }
                self.fittingPhase = .displaying
                defer { self.surfaceRevision &+= 1 }
                self.isSettling = false
                self.settlingTask = nil
                guard let model = GarmentRenderer.makeModel(
                    asset: result.asset, positions: result.positions,
                    display: GarmentSurface(vertices: result.displayVertices, indices: result.displayIndices),
                    appearance: definition.appearance) else {
                    for child in Array(self.root.children) { child.removeFromParent() }
                    if managesElevation { mannequin.setFootwearElevation(0) }
                    self.fitMessage = L("옷 모델을 표시하지 못했습니다")
                    return
                }
                model.name = definition.id
                for child in Array(self.root.children) { child.removeFromParent() }
                self.root.position = anchor
                if let footwear = result.asset.footwear {
                    if managesElevation { mannequin.setFootwearElevation(footwear.soleThickness) }
                    self.root.position.y = managesElevation ? footwear.soleThickness : 0
                }
                self.root.addChild(model)
                self.root.isEnabled = true
                self.fitSummary = result.summary
                self.fittedResult = result
                if let summary = result.summary, let length = summary.footLengthEase, let width = summary.footWidthEase {
                    if result.displayBodyOverlap > 0.002 {
                        self.fitMessage = L("신발 표면에 신체 겹침이 남아 있습니다 · 내부 착화감은 검증하지 않습니다")
                    } else {
                        self.fitMessage = min(length, width) < 0
                            ? L("신발 외형보다 발이 큽니다 · 내부 착화감·충돌 보정은 지원하지 않습니다")
                            : L("신발 외형 치수 비교 · 내부 착화감·충돌 보정은 지원하지 않습니다")
                    }
                } else if result.remainingOverlap > 0.002 {
                    self.fitMessage = L("일부 영역에 겹침이 남아 있습니다")
                } else if let summary = result.summary, let waist = summary.waistEase, let hip = summary.hipEase {
                    if let clearance = summary.hemFloorClearance, clearance < -0.01 {
                        self.fitMessage = L("바지 밑단이 바닥 아래로 내려갑니다 · 기장을 확인해 주세요")
                    } else if min(waist, hip) < 0 {
                        self.fitMessage = L("허리 또는 엉덩이가 조이는 핏 · 원단 물성은 추정값입니다")
                    } else if min(waist, hip) < 0.04 {
                        self.fitMessage = L("허리 또는 엉덩이 여유가 적은 착장입니다")
                    } else {
                        self.fitMessage = result.maximumStrain > definition.material.maximumStrain
                            ? L("당김이 큰 부위가 있습니다 · 소재는 추정값입니다") : nil
                    }
                } else if let summary = result.summary, summary.chestEase < -0.002,
                          let chest = result.asset.sizing?.reference.chestCircumference {
                    let stretch = -summary.chestEase / chest
                    let percentText = "\(Int((stretch * 100).rounded()))%"
                    self.fitMessage = stretch > definition.material.fabricSettings.estimatedMaximumExtension
                        ? L("가슴이 꽉 끼는 핏 · 원단 약 \(percentText) 늘어나 불편할 수 있음")
                        : L("가슴이 몸에 붙는 핏 · 원단 약 \(percentText) 늘어남")
                } else if let summary = result.summary, summary.chestEase < 0.04 {
                    self.fitMessage = L("가슴 여유가 적은 착장입니다")
                } else if result.maximumStrain > definition.material.maximumStrain {
                    self.fitMessage = L("당김이 큰 부위가 있습니다 · 소재는 추정값입니다")
                } else {
                    self.fitMessage = nil
                }
                if definition.pattern.fittingMode == .shapePreserving {
                    self.fitMessage = ([L("형상 유지형 착장 · 처짐·동적 주름 계산은 생략합니다")] +
                        [self.fitMessage].compactMap { $0 }).joined(separator: "\n")
                }
            } catch {
                guard !Task.isCancelled, let self, self.request == next else { return }
                defer { self.surfaceRevision &+= 1 }
                self.isSettling = false
                self.settlingTask = nil
                for child in Array(self.root.children) { child.removeFromParent() }
                if managesElevation { mannequin.setFootwearElevation(0) }
                switch error as? GarmentDrapeError {
                case .invalidAsset:
                    self.fitMessage = L("의류 데이터를 불러올 수 없습니다")
                case .initializationFailed:
                    self.fitMessage = L("착장 표면을 준비하지 못했습니다")
                case .simulationFailed:
                    self.fitMessage = L("신체 겹침 보정에 실패했습니다")
                case nil:
                    self.fitMessage = L("옷을 표시하지 못했습니다")
                }
            }
        }
    }

    func cancelSettling() {
        settlingTask?.cancel()
        settlingTask = nil
        request = nil
        outfitRequest = nil
        for controller in slots.values { controller.cancelSettling() }
        isSettling = false
        fittingPhase = nil
        activeSlot = nil
        wasCancelled = false
    }

    func cancelFitting() {
        guard isSettling else { return }
        cancelSettling()
        for (slot, controller) in slots where !visibleSlots.contains(slot) {
            controller.root.removeFromParent()
        }
        if slots.isEmpty {
            for child in Array(root.children) { child.removeFromParent() }
            root.isEnabled = false
        } else {
            root.isEnabled = !visibleSlots.isEmpty
        }
        fitSummary = nil
        wasCancelled = true
        surfaceRevision &+= 1
    }

    private struct Request: Equatable {
        let definition: GarmentDefinition
        let body: GarmentBodyKey
        let layers: [GarmentLayerKey]
    }

    private struct OutfitRequest: Equatable {
        let definitions: [GarmentDefinition]
        let body: BodyPreviewRenderer.Request
    }
}