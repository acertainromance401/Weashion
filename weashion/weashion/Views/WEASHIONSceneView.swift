import SwiftUI
import RealityKit
import SceneKit
import UIKit
import simd
import Observation

private struct MannequinRenderView: UIViewRepresentable {
    let surface: MannequinSceneSurface
    let state: MannequinSceneSurface.State
    // Explicit inputs forward observable changes to the retained UIKit surface.
    let revision: UInt64
    let garmentRevision: UInt64
    let settling: Bool
    let pose: EditorialScenePose
    let make: (MannequinSceneSurface) -> Void
    let update: (MannequinSceneSurface) -> Void

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        surface.removeFromSuperview()
        surface.frame = host.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(surface)
        surface.activate(state)
        make(surface)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        guard surface.superview === host else { return }
        update(surface)
    }

    static func dismantleUIView(_ host: UIView, coordinator: ()) {
        for surface in host.subviews.compactMap({ $0 as? MannequinSceneSurface }) {
            surface.removeFromSuperview()
        }
    }
}

final class MannequinSceneSurface: SCNView {
    struct RenderedEntity {
        let node = SCNNode()
        let geometry = SCNNode()
        var mesh: MeshResource?
    }
    final class State {
        let scene = SCNScene()
        var sourceRoot: Entity?
        var rendered: [ObjectIdentifier: RenderedEntity] = [:]
        var geometryBuildCount = 0

        init() {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 25
            scene.rootNode.addChildNode(ambient)
        }
    }
    private var state: State?
    var sourceRoot: Entity? {
        get { state?.sourceRoot }
        set { state?.sourceRoot = newValue }
    }

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        isOpaque = false
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { isPlaying = false }
    }

    func activate(_ state: State) {
        self.state = state
        scene = state.scene
    }

    func isDisplaying(_ state: State) -> Bool {
        self.state === state && window != nil
    }

    func releaseDetachedState(_ state: State) {
        guard self.state === state, window == nil else { return }
        pointOfView = nil
        scene = nil
        self.state = nil
    }

    func synchronize() {
        guard let state, let sourceRoot, let scene else { return }
        var active: Set<ObjectIdentifier> = []
        func synchronize(_ entity: Entity, parent: SCNNode) {
            let identifier = ObjectIdentifier(entity)
            active.insert(identifier)
            var entry = state.rendered[identifier] ?? RenderedEntity()
            let node = entry.node
            node.name = entity.name
            node.simdTransform = entity.transform.matrix
            node.isHidden = !entity.isEnabled
            if node.parent !== parent { parent.addChildNode(node) }
            if entry.geometry.parent == nil { node.addChildNode(entry.geometry) }
            if let model = entity.components[ModelComponent.self], entry.mesh !== model.mesh {
                state.geometryBuildCount += 1
                for child in entry.geometry.childNodes { child.removeFromParentNode() }
                for meshModel in model.mesh.contents.models {
                    for part in meshModel.parts {
                        guard let indices = part.triangleIndices else { continue }
                        var sources = [SCNGeometrySource(vertices: part.positions.map { SCNVector3($0) })]
                        if let normals = part.normals {
                            sources.append(SCNGeometrySource(normals: normals.map { SCNVector3($0) }))
                        }
                        let data = indices.elements.withUnsafeBytes { Data($0) }
                        let element = SCNGeometryElement(data: data, primitiveType: .triangles,
                                                         primitiveCount: indices.count / 3,
                                                         bytesPerIndex: MemoryLayout<UInt32>.stride)
                        let geometry = SCNGeometry(sources: sources, elements: [element])
                        let material = SCNMaterial()
                        material.lightingModel = .physicallyBased
                        if model.materials.indices.contains(part.materialIndex),
                           let source = model.materials[part.materialIndex] as? SimpleMaterial {
                            material.diffuse.contents = source.color.tint
                            if case .float(let roughness) = source.roughness {
                                material.roughness.contents = roughness
                            }
                            if case .float(let metallic) = source.metallic {
                                material.metalness.contents = metallic
                            }
                        }
                        geometry.materials = [material]
                        entry.geometry.addChildNode(SCNNode(geometry: geometry))
                    }
                }
                entry.mesh = model.mesh
            }
            if let camera = entity as? PerspectiveCamera {
                if node.camera == nil { node.camera = SCNCamera() }
                node.camera?.fieldOfView = CGFloat(camera.camera.fieldOfViewInDegrees)
                node.camera?.zNear = 0.01
                node.camera?.zFar = 100
                node.camera?.wantsHDR = true
                node.camera?.wantsExposureAdaptation = false
                pointOfView = node
            }
            if let light = entity as? DirectionalLight {
                if node.light == nil { node.light = SCNLight() }
                node.light?.type = .directional
                node.light?.intensity = CGFloat(light.light.intensity) * 0.225
            } else if let light = entity as? PointLight {
                if node.light == nil { node.light = SCNLight() }
                node.light?.type = .omni
                node.light?.intensity = CGFloat(light.light.intensity) * 0.15
            }
            state.rendered[identifier] = entry
            for child in entity.children { synchronize(child, parent: node) }
        }
        synchronize(sourceRoot, parent: scene.rootNode)
        for identifier in Set(state.rendered.keys).subtracting(active) {
            state.rendered.removeValue(forKey: identifier)?.node.removeFromParentNode()
        }
    }
}

enum EditorialSceneStatus: Equatable {
    case preparing
    case bodyReference
    case undressed
    case reference(String)
    case updating(String)
    case cancelled
    case warning(String)
    case failure(String)

    static func resolve(bodyError: String? = nil, bodyPreparing: Bool = false, bodyPreview: Bool = false, updating: Bool = false,
                        sizeLabel: String? = nil, garmentMessage: String? = nil, cancelled: Bool = false,
                        hasVisibleGarment: Bool = false, missingCatalog: Bool = false) -> Self {
        if let bodyError { return .failure(bodyError) }
        if bodyPreparing { return .preparing }
        if bodyPreview { return .bodyReference }
        if cancelled { return .cancelled }
        if updating { return .updating(sizeLabel ?? L("선택한")) }
        if let garmentMessage {
            return hasVisibleGarment ? .warning(garmentMessage) : .failure(garmentMessage)
        }
        if missingCatalog { return .failure(L("의류 목록을 불러올 수 없습니다.")) }
        return sizeLabel.map { .reference($0) } ?? .undressed
    }

    var title: String {
        switch self {
        case .preparing: L("미리보기를 준비하고 있어요")
        case .bodyReference: L("나의 기준 체형")
        case .undressed: L("의류 미착용")
        case .reference(let size): L("\(size) 사이즈 · 입력 치수 기준")
        case .updating(let size): L("\(size) 사이즈 착장 계산 중")
        case .cancelled: L("착장 계산을 취소했어요")
        case .warning: L("착장 확인 사항")
        case .failure: L("미리보기를 표시하지 못했어요")
        }
    }

    var detail: String? {
        switch self {
        case .preparing: nil
        case .bodyReference: nil
        case .undressed: L("상품과 사이즈를 선택해 입혀보세요.")
        case .reference: L("실제 상품의 핏과 다를 수 있는 근사 미리보기입니다.")
        case .updating: L("이전 의류는 숨기고 선택한 치수로 계산하고 있어요.")
        case .cancelled: L("선택한 옷과 치수는 유지됩니다. 다시 계산하거나 다른 옷을 선택해 주세요.")
        case .warning(let message), .failure(let message): message
        }
    }

    var tone: EditorialNoticeTone {
        switch self {
        case .preparing, .updating: .progress
        case .warning: .warning
        case .failure: .error
        default: .information
        }
    }

    /// States that deserve attention even on surfaces that hide the informational line.
    var isProblem: Bool {
        switch self {
        case .preparing, .updating, .cancelled, .warning, .failure: true
        default: false
        }
    }
}

enum EditorialBackdropStyle {
    case studio, transparent
}

struct EditorialScenePose: Equatable {
    var rotation: Float = 0
    var zoom: Float = 1
    var focus = SIMD3<Float>.zero
}

@MainActor @Observable
final class EditorialSceneLink {
    var pose = EditorialScenePose()
    private(set) var fitting = EditorialSceneState()
    private(set) var body = EditorialSceneState()
    @ObservationIgnored private var surface: MannequinSceneSurface?
    @ObservationIgnored private(set) var surfaceCreationCount = 0

    func renderSurface() -> MannequinSceneSurface {
        if let surface { return surface }
        let created = MannequinSceneSurface(frame: .zero)
        surface = created
        surfaceCreationCount += 1
        return created
    }

    func cancelPreparation() {
        fitting.cancelPreparation()
        body.cancelPreparation()
    }

    func releaseInactiveResources(keepingBody: Bool) {
        let inactive = keepingBody ? fitting : body
        guard surface?.isDisplaying(inactive.native) != true else { return }
        surface?.releaseDetachedState(inactive.native)
        inactive.cancelPreparation()
        if keepingBody { fitting = EditorialSceneState() }
        else { body = EditorialSceneState() }
    }
}

@MainActor @Observable
final class EditorialSceneState {
    let mannequin = WEASHIONMannequin()
    let garment = GarmentController()
    let displayRoot = Entity()
    let camera = PerspectiveCamera()
    let native = MannequinSceneSurface.State()
    @ObservationIgnored private var surface: MannequinSceneSurface?
    @ObservationIgnored private var preparation: Task<Void, Error>?
    @ObservationIgnored private var pendingRequest: BodyPreviewRenderer.Request?
    @ObservationIgnored private var generation = 0
    private(set) var preparedRequest: BodyPreviewRenderer.Request?
    private(set) var isPreparing = false

    fileprivate func renderSurface() -> MannequinSceneSurface {
        if let surface { return surface }
        let created = MannequinSceneSurface(frame: .zero)
        surface = created
        return created
    }

    func prepare(_ request: BodyPreviewRenderer.Request, bodyOnly: Bool) async throws {
        try Task.checkCancellation()
        if preparedRequest == request { return }
        let task: Task<Void, Error>
        let token: Int
        if pendingRequest == request, let preparation {
            task = preparation
            token = generation
        } else {
            preparation?.cancel()
            generation += 1
            token = generation
            garment.update(definition: nil, mannequin: mannequin)
            preparedRequest = nil
            isPreparing = true
            let mannequin = mannequin
            task = Task {
                if bodyOnly {
                    guard let prepared = try await BodyPreviewRenderer.shared.render(request) else {
                        throw BodyPreviewRenderer.PreparationError.invalidBody
                    }
                    try await mannequin.applyPreview(prepared)
                } else {
                    try await mannequin.prepareFitting(request)
                }
            }
            preparation = task
            pendingRequest = request
        }
        do {
            try await task.value
            if generation == token, pendingRequest == request {
                preparedRequest = request
                pendingRequest = nil
                preparation = nil
                isPreparing = false
            }
            try Task.checkCancellation()
        } catch {
            if generation == token, pendingRequest == request {
                pendingRequest = nil
                preparation = nil
                isPreparing = false
                if !(error is CancellationError) { mannequin.fittingFailed() }
            }
            throw error
        }
    }

    func cancelPreparation() {
        generation += 1
        preparation?.cancel()
        preparation = nil
        pendingRequest = nil
        isPreparing = false
        garment.cancelSettling()
        mannequin.cancelPreview()
    }
}

struct WEASHIONSceneView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bodyData: UserBody
    let mannequinBase: MannequinBase
    let weather: WeatherInfo
    var isBodyPreview = false
    var sceneHeight: CGFloat = 500
    var garmentSelection: Binding<String?>? = nil
    var isCompactComparison = false
    var garmentSizes: Binding<[String: GarmentSizeInput]>? = nil
    var garmentOverride: GarmentDefinition? = nil
    var outfitOverride: [GarmentDefinition]? = nil
    var isGarmentEditor = false
    var isEditorial = false
    var fitSummaryOutput: Binding<GarmentFitSummary?>? = nil
    var showsViewControls = true
    var showsSceneStatus = true
    var statusOutput: Binding<EditorialSceneStatus?>? = nil
    var editorialBackdropStyle = EditorialBackdropStyle.studio
    var editorialChromeInset: CGFloat = 16
    var sceneLink: EditorialSceneLink? = nil
    var onSceneReady: (() -> Void)? = nil
    @State private var localScene = EditorialSceneState()
    @State private var garmentID: String? = GarmentCatalog.samples.first?.id
    @State private var localPose = EditorialScenePose()
    @State private var localSizes: [String: GarmentSizeInput] = [:]
    @State private var localMeasurements: [String: GarmentMeasurements] = [:]
    @State private var showGarmentEditor = false

    private let cameraOffset = SIMD3<Float>(0, 0.06, 3.25)
    private let zoomRange: ClosedRange<Float> = 0.75...3
    private let garments = GarmentCatalog.samples
    private var sceneState: EditorialSceneState {
        guard let sceneLink else { return localScene }
        return isBodyPreview ? sceneLink.body : sceneLink.fitting
    }
    private var mannequin: WEASHIONMannequin { sceneState.mannequin }
    private var garment: GarmentController { sceneState.garment }
    private var displayRoot: Entity { sceneState.displayRoot }
    private var camera: PerspectiveCamera { sceneState.camera }
    private var bodyRequest: BodyPreviewRenderer.Request {
        BodyPreviewRenderer.Request(body: bodyData, base: mannequinBase)
    }
    private struct ScenePreparationRequest: Equatable {
        let body: BodyPreviewRenderer.Request
        let garment: GarmentDefinition?
        let outfit: [GarmentDefinition]
    }

    private var selectedOutfit: [GarmentDefinition] {
        isBodyPreview ? [] : outfitOverride ?? selectedGarment.map { [$0] } ?? []
    }

    private var viewpoint: Binding<EditorialScenePose> {
        if let sceneLink, !isBodyPreview {
            Binding(get: { sceneLink.pose }, set: { sceneLink.pose = $0 })
        } else {
            $localPose
        }
    }

    private var selectedGarment: GarmentDefinition? {
        guard !isBodyPreview else { return nil }
        let definition: GarmentDefinition
        if let garmentOverride {
            definition = garmentOverride
        } else {
            let selectedID = garmentSelection.map { $0.wrappedValue } ?? garmentID
            guard let selected = garments.first(where: { $0.id == selectedID }) else { return nil }
            definition = selected
        }
        if let measurements = localMeasurements[definition.id],
           let resized = measurements.applying(to: definition) { return resized }
        let sizes = garmentSizes?.wrappedValue ?? localSizes
        if let input = sizes[definition.id],
           let resized = GarmentMeasurements.shortSleeve(input).applying(to: definition) { return resized }
        return definition
    }

    private var activeGarmentSelection: Binding<String?> {
        garmentSelection ?? $garmentID
    }

    private var previewRequest: BodyPreviewRenderer.Request? {
        isBodyPreview ? BodyPreviewRenderer.Request(body: bodyData, base: mannequinBase) : nil
    }

    var body: some View {
        let _ = mannequin.surfaceRevision
        let _ = viewpoint.wrappedValue
        VStack(alignment: .leading, spacing: isEditorial ? 0 : 10) {
            if !isBodyPreview && !isGarmentEditor && !isEditorial {
                if isCompactComparison {
                    HStack(spacing: 4) {
                        Label(selectedGarment?.selectionLabel ?? L("미착용"), systemImage: "hanger")
                            .editorialSans(.caption, weight: .medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 0)

                        garmentPicker
                            .pickerStyle(.menu)
                    }
                } else {
                    HStack {
                        Label(selectedGarment?.name ?? L("의류"), systemImage: "hanger")
                            .editorialSans(.subheadline, weight: .medium)
                        Spacer()
                        editGarmentButton
                    }
                    if garments.count > 3 {
                        garmentPicker.pickerStyle(.menu)
                    } else {
                        garmentPicker.pickerStyle(.segmented)
                    }
                }
                if isCompactComparison { editGarmentButton }
            }

            if isEditorial {
                mannequinScene
                    .background { editorialBackdrop }
                if showsViewControls { viewControls }
                if showsSceneStatus { sceneStatus }
            } else {
                sceneStatus
                mannequinScene
                viewControls
            }
            if !isBodyPreview && !isEditorial, let measurements = selectedGarment?.measurements {
                if case .shortSleeve = measurements, let dimensions = selectedGarment?.pattern.dimensions {
                    garmentMeasurements(dimensions)
                } else {
                    WearableMeasurementSummary(measurements: measurements)
                    Text(measurements.editorialMeasurementNote)
                        .editorialSans(.caption).foregroundStyle(.secondary)
                }
            }
            if !isBodyPreview && !isEditorial, let summary = garment.fitSummary {
                garmentFitResults(summary)
            }
        }
        .task(id: ScenePreparationRequest(body: bodyRequest, garment: selectedGarment, outfit: selectedOutfit)) {
            guard !isBodyPreview || sceneLink != nil else { return }
            do {
                try await sceneState.prepare(bodyRequest, bodyOnly: isBodyPreview)
                try Task.checkCancellation()
                garment.update(outfit: selectedOutfit, focused: selectedGarment, mannequin: mannequin)
                onSceneReady?()
            } catch is CancellationError {
                // A superseded or disappearing view does not publish an error.
            } catch {
                mannequin.fittingFailed()
                onSceneReady?()
            }
        }
        .onDisappear {
            if sceneLink == nil { sceneState.cancelPreparation() }
        }
        .onChange(of: previewRequest, initial: true) { _, request in
            guard sceneLink == nil else { return }
            if let request { mannequin.requestPreview(request) }
            else { mannequin.cancelPreview() }
        }
        .onChange(of: garment.fitSummary, initial: true) { _, summary in
            fitSummaryOutput?.wrappedValue = summary
        }
        .onChange(of: currentStatus, initial: true) { _, status in
            statusOutput?.wrappedValue = status
        }
        .sheet(isPresented: $showGarmentEditor) {
            if let definition = selectedGarment, definition.pattern.source == .mesh,
               let measurements = definition.measurements, measurements.supports(definition.kind) {
                switch measurements {
                case .shortSleeve(let input):
                    GarmentEditorView(
                        size: (garmentSizes?.wrappedValue ?? localSizes)[definition.id] ?? input,
                        definition: definition, bodyData: bodyData, mannequinBase: mannequinBase, weather: weather,
                        sampleDefinitions: garments,
                        showsProductFields: false
                    ) { size, _ in
                        if let garmentSizes { garmentSizes.wrappedValue[definition.id] = size }
                        else { localSizes[definition.id] = size }
                    }
                case .trousers, .footwear:
                    WearableMeasurementsEditor(
                        measurements: localMeasurements[definition.id] ?? measurements, sizeLabel: definition.selectionLabel,
                        definition: definition, bodyData: bodyData, mannequinBase: mannequinBase, weather: weather,
                        sampleDefinitions: garments, requiresSizeLabel: false,
                        saveTitle: L("내 마네킹에 적용")
                    ) { measurements, _ in
                        localMeasurements[definition.id] = measurements
                    }
                }
            }
        }
    }

    private var currentStatus: EditorialSceneStatus {
        EditorialSceneStatus.resolve(
            bodyError: mannequin.loadError, bodyPreparing: sceneState.isPreparing,
            bodyPreview: isBodyPreview, updating: garment.isSettling,
            sizeLabel: selectedGarment?.selectionLabel ?? selectedOutfit.first?.selectionLabel, garmentMessage: garment.fitMessage,
            cancelled: garment.wasCancelled,
            hasVisibleGarment: garment.root.isEnabled, missingCatalog: garments.isEmpty && selectedGarment == nil
        )
    }

    @ViewBuilder
    private var sceneStatus: some View {
        let status = currentStatus
        if status != .bodyReference {
            EditorialNotice(title: status.title, detail: status.detail, tone: status.tone,
                            rule: isEditorial && showsViewControls ? [] : .top)
                .frame(maxWidth: .infinity, minHeight: isEditorial ? 68 : 44, alignment: .leading)
                .padding(.horizontal, isEditorial ? editorialChromeInset : 0)
                .background(Editorial.paper)
                .contentTransition(.opacity)
                .animation(EditorialMotion.feedback(reduceMotion: reduceMotion), value: status)
                .accessibilityIdentifier(status.tone == .progress ? "garmentUpdating" : "sceneStatus")
        }
    }

    @ViewBuilder
    private var editorialBackdrop: some View {
        switch editorialBackdropStyle {
        case .transparent:
            Color.clear
        case .studio:
            EditorialStudioBackdrop()
        }
    }

    private var editGarmentButton: some View {
        Button {
            showGarmentEditor = true
        } label: {
            Label("치수", systemImage: "ruler")
                .editorialSans(.caption)
                .frame(minHeight: EditorialLayout.minimumControlSize)
        }
        .disabled(selectedGarment?.pattern.source != .mesh || selectedGarment?.measurements == nil)
        .accessibilityLabel("의상 치수 조절")
        .help("의상 치수 조절")
    }

    private func garmentMeasurements(_ dimensions: SampleTShirtSpecification) -> some View {
        let displayed = GarmentSizeLabelCalibration(templateID: selectedGarment?.pattern.id ?? "")
            .displayed(GarmentSizeInput(dimensions: dimensions))
        return VStack(alignment: .leading, spacing: 4) {
            Text("의상 치수 · cm")
                .editorialSans(.caption, weight: .medium)
            Text("총장 \(displayed.length, specifier: "%.1f") · 어깨 \(displayed.shoulderWidth, specifier: "%.1f")")
            Text("가슴단면 \(displayed.chestWidth, specifier: "%.1f") · 소매 \(displayed.sleeveLength, specifier: "%.1f")")
        }
        .editorialSans(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func garmentFitResults(_ summary: GarmentFitSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch selectedGarment?.kind {
            case .shoes:
                if let ease = summary.footLengthEase {
                    Text("외부 길이 차이 \(String(format: "%+.1f", ease * 1000)) mm")
                }
                if let ease = summary.footWidthEase {
                    Text("외부 너비 차이 \(String(format: "%+.1f", ease * 1000)) mm")
                }
                Text("신발 외부 치수와 발의 차이입니다. 내부 공간·실제 착화감 또는 천 충돌 시뮬레이션을 뜻하지 않습니다.")
                    .foregroundStyle(.secondary)
            case .pants:
                if let ease = summary.waistEase {
                    Text("허리둘레 여유 \(String(format: "%+.1f", ease * 100)) cm")
                }
                if let ease = summary.hipEase {
                    Text("엉덩이둘레 여유 \(String(format: "%+.1f", ease * 100)) cm")
                }
                Text("착장 길이(수직) \(summary.verticalLength * 100, specifier: "%.1f") cm")
                Text("단면 × 2와 신체 둘레의 근사 비교이며 실제 착용감과 다를 수 있습니다.")
                    .foregroundStyle(.secondary)
            default:
                Text("가슴 여유 \(String(format: "%+.1f", summary.chestEase * 100)) cm")
                    .foregroundStyle(summary.chestEase < 0 ? .orange : .primary)
                Text("어깨 차이 \(String(format: "%+.1f", summary.shoulderEase * 100)) cm")
                if let chest = summary.wornChest {
                    Text("착장 가슴둘레(근사) \(chest * 100, specifier: "%.1f") cm")
                }
                Text("착장 총장(수직) \(summary.verticalLength * 100, specifier: "%.1f") cm")
                Text("표면 늘어남(상위 5%) \(String(format: "%.1f%%", summary.maximumStrain * 100))")
                Text("원단 물성 · 신축률 미확인")
                    .foregroundStyle(.secondary)
            }
        }
        .editorialSans(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var garmentPicker: some View {
        Picker("의상 사이즈", selection: activeGarmentSelection) {
            Text("미착용").tag(Optional<String>.none)
            ForEach(garments) { item in
                Text(garments.count > 3 ? "\(item.name) · \(item.selectionLabel)" : item.selectionLabel)
                    .tag(Optional(item.id))
            }
        }
    }

    private var mannequinScene: some View {
        MannequinRenderView(surface: sceneLink?.renderSurface() ?? sceneState.renderSurface(),
                            state: sceneState.native, revision: mannequin.surfaceRevision,
                            garmentRevision: garment.surfaceRevision,
                            settling: garment.isSettling, pose: viewpoint.wrappedValue) {

            content in

            guard content.sourceRoot == nil else {
                updateViewpoint()
                content.synchronize()
                return
            }
            let scene = Entity()
            scene.name = "WEASHION_SCENE"

            displayRoot.addChild(mannequin.root)
            displayRoot.addChild(garment.root)
            scene.addChild(displayRoot)


            let ground = makeGround(
                weather: weather
            )

            if !isEditorial { scene.addChild(ground) }

            content.sourceRoot = scene


            camera.camera.fieldOfViewInDegrees = 38
            updateViewpoint()

            scene.addChild(camera)


            let light = DirectionalLight()

            light.light.intensity = 1000
            light.shadow = DirectionalLightComponent.Shadow()

            light.position = [
                -3,
                4,
                3
            ]

            light.look(
                at: [0, 0.9, 0],
                from: light.position,
                relativeTo: nil
            )

            scene.addChild(light)


            let ambientLight = PointLight()

            ambientLight.light.intensity = 150

            ambientLight.position = [
                2,
                1.8,
                2
            ]

            scene.addChild(ambientLight)
            content.synchronize()

        } update: {

            content in

            let _ = garment.isSettling
            let _ = garment.fitSummary
            updateViewpoint()
            content.synchronize()
        }
        .frame(height: sceneHeight)
        .frame(maxWidth: .infinity)
        .blur(radius: fittingIsObscured ? 5 : 0)
        .overlay {
            MannequinInteractionView(
                onRotate: { translation in
                    rotate(by: Float(translation) * 0.01)
                },
                onZoom: { scale, location, size in
                    changeZoom(by: Float(scale), at: location, in: size)
                }
            )
            .accessibilityHidden(true)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBodyPreview ? L("체형 3D 미리보기") : L("피팅 3D 미리보기"))
        .accessibilityValue(currentStatus.tone == .progress || currentStatus.tone == .error || garment.wasCancelled ? currentStatus.title :
                            isBodyPreview ? L("나의 기준 체형") :
                            (selectedGarment ?? selectedOutfit.first).map { L("선택한 사이즈 \($0.selectionLabel)") } ?? L("의류 미착용"))
        .accessibilityHint(showsViewControls ? L("아래 회전·확대·초기화 버튼으로 확인할 수 있습니다.") : L("피팅룸에서 회전하고 확대할 수 있습니다."))
        .accessibilityIdentifier("mannequinScene")
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .overlay {
            if fittingIsObscured {
                fittingLoadingOverlay
                    // Replace the accessibility subtree when switching between cancel and retry.
                    .id(garment.wasCancelled)
            }
        }
    }

    private var fittingIsObscured: Bool {
        !isBodyPreview && mannequin.loadError == nil && (sceneState.isPreparing || garment.isSettling || garment.wasCancelled)
    }

    private var fittingLoadingOverlay: some View {
        ZStack {
            Editorial.paper.opacity(0.82)
            VStack(spacing: 14) {
                if garment.wasCancelled {
                    Image(systemName: "pause.circle")
                        .font(.title2)
                } else {
                    ProgressView().tint(Editorial.accent)
                        .accessibilityLabel(L("착장 계산 중"))
                }
                Text(garment.wasCancelled ? L("착장 계산을 취소했어요") :
                        sceneState.isPreparing ? L("미리보기를 준비하고 있어요") : L("옷을 체형에 맞추고 있어요"))
                    .editorialSans(.headline)
                    .multilineTextAlignment(.center)
                if !garment.wasCancelled {
                    Text(sceneState.isPreparing ? L("마네킹 표면 준비 중") :
                            garment.activeFittingPhase?.title ?? L("의류 표면 준비 중"))
                        .editorialSans(.subheadline)
                        .accessibilityIdentifier("fittingLoadingStage")
                    if let slot = garment.activeSlot {
                        Text("\(slot.title) · \(garment.completedSlotCount) / \(garment.requestedSlotCount)")
                            .editorialSans(.caption).monospacedDigit()
                            .accessibilityIdentifier("fittingLoadingSlot")
                    }
                }
                Text(garment.wasCancelled
                     ? L("선택한 옷과 치수는 유지됩니다. 다시 계산하거나 다른 옷을 선택해 주세요.")
                     : L("미완성 형상은 흐리게 표시합니다. 다른 옷을 선택하면 최신 선택으로 다시 계산합니다."))
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
                    .multilineTextAlignment(.center)
                if garment.wasCancelled {
                    Button(L("다시 계산")) {
                        garment.update(outfit: selectedOutfit, focused: selectedGarment, mannequin: mannequin)
                    }
                    .accessibilityIdentifier("retryFitting")
                } else if garment.isSettling {
                    Button(L("계산 취소")) { garment.cancelFitting() }
                        .accessibilityIdentifier("cancelFitting")
                }
            }
            .padding(24)
            .foregroundStyle(Editorial.ink)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fittingLoadingOverlay")
    }

    private var viewControls: some View {
        HStack(spacing: 0) {
            EditorialEyebrow(text: "VIEW")
                .padding(.leading, editorialChromeInset)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                viewControl("Rotate left", title: L("왼쪽으로 회전"), symbol: "rotate.left") {
                    rotate(by: -.pi / 4)
                }
                viewControl("Rotate right", title: L("오른쪽으로 회전"), symbol: "rotate.right") {
                    rotate(by: .pi / 4)
                }
                viewControl("Zoom out", title: L("축소"), symbol: "minus.magnifyingglass") {
                    changeZoom(by: 1 / 1.2)
                }
                .disabled(viewpoint.wrappedValue.zoom <= zoomRange.lowerBound)
                viewControl("Zoom in", title: L("확대"), symbol: "plus.magnifyingglass") {
                    changeZoom(by: 1.2)
                }
                .disabled(viewpoint.wrappedValue.zoom >= zoomRange.upperBound)
                viewControl("Reset view", title: L("보기 초기화"), symbol: "arrow.counterclockwise") {
                    viewpoint.wrappedValue = EditorialScenePose()
                }
            }
            .padding(.trailing, max(editorialChromeInset - 8, 8))
            .padding(.trailing, isEditorial ? 0 : 4)
        }
        .frame(minHeight: EditorialLayout.minimumControlSize + 12)
        .background(Editorial.paper)
        .overlay(alignment: .top) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneControls")
    }

    private func updateViewpoint() {
        let pose = viewpoint.wrappedValue
        displayRoot.orientation = simd_quatf(angle: pose.rotation, axis: [0, 1, 0])
        let target = pose.focus + SIMD3<Float>(0, Float(bodyData.height) / 200, 0)
        camera.look(
            at: target,
            from: target + cameraOffset / pose.zoom,
            relativeTo: nil
        )
    }

    private func rotate(by angle: Float) {
        viewpoint.wrappedValue.rotation = (viewpoint.wrappedValue.rotation + angle).truncatingRemainder(dividingBy: 2 * .pi)
    }

    private func changeZoom(by factor: Float, at location: CGPoint? = nil, in size: CGSize = .zero) {
        var pose = viewpoint.wrappedValue
        let nextZoom = min(max(pose.zoom * factor, zoomRange.lowerBound), zoomRange.upperBound)
        if let location, size.width > 0, size.height > 0 {
            let forward = -simd_normalize(cameraOffset)
            let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
            let up = simd_cross(right, forward)
            let visibleHeight = 2 * simd_length(cameraOffset) / pose.zoom * tan(Float(19) * .pi / 180)
            let horizontal = Float(location.x / size.width - 0.5) * visibleHeight * Float(size.width / size.height)
            let vertical = Float(0.5 - location.y / size.height) * visibleHeight
            pose.focus += (right * horizontal + up * vertical) * (1 - pose.zoom / nextZoom)
        }
        pose.zoom = nextZoom
        viewpoint.wrappedValue = pose
    }

    private func viewControl(_ identifier: String, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .frame(width: EditorialLayout.minimumControlSize, height: EditorialLayout.minimumControlSize)
                .overlay(alignment: .leading) { Rectangle().fill(Editorial.rule).frame(width: 0.5, height: 18) }
                .contentShape(Rectangle())
        }
        .buttonStyle(EditorialPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .help(title)
    }


    private func makeGround(
        weather: WeatherInfo
    ) -> ModelEntity {

        let condition = weather.condition.lowercased()

        let isRain =
            condition.contains("rain") ||
            condition.contains("drizzle") ||
            condition.contains("비")

        let color: UIColor

        if isRain {

            color = UIColor(
                white: 0.16,
                alpha: 1
            )

        } else {

            color = UIColor(
                white: 0.25,
                alpha: 1
            )
        }


        let ground = ModelEntity(
            mesh: .generatePlane(
                width: 10,
                depth: 8
            ),
            materials: [
                SimpleMaterial(
                    color: color,
                    isMetallic: false
                )
            ]
        )

        ground.position = [
            0,
            -0.002,
            0
        ]

        return ground
    }
}

private struct MannequinInteractionView: UIViewRepresentable {
    let onRotate: (CGFloat) -> Void
    let onZoom: (CGFloat, CGPoint, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.rotate(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MannequinInteractionView

        init(parent: MannequinInteractionView) {
            self.parent = parent
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func rotate(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended else { return }
            parent.onRotate(recognizer.translation(in: recognizer.view).x)
            recognizer.setTranslation(.zero, in: recognizer.view)
        }

        @objc func zoom(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended,
                  let view = recognizer.view else { return }
            parent.onZoom(recognizer.scale, recognizer.location(in: view), view.bounds.size)
            recognizer.scale = 1
        }
    }
}
