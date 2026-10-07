import SwiftUI
import RealityKit
import UIKit
import simd

struct WEASHIONSceneView: View {

    let bodyData: UserBody
    let mannequinBase: MannequinBase
    let weather: WeatherInfo
    @State private var mannequin = WEASHIONMannequin()
    @State private var garment = GarmentController()
    @State private var garmentID: String? = GarmentCatalog.samples.first?.id
    @State private var displayRoot = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var rotation: Float = 0
    @State private var zoom: Float = 1
    @State private var focus = SIMD3<Float>.zero

    private let cameraOffset = SIMD3<Float>(0, 0.06, 3.25)
    private let zoomRange: ClosedRange<Float> = 0.75...3
    private let garments = GarmentCatalog.samples

    private var selectedGarment: GarmentDefinition? {
        garments.first { $0.id == garmentID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(selectedGarment?.name ?? "의류", systemImage: "tshirt")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("샘플")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("샘플 의류", selection: $garmentID) {
                Text("미착용").tag(Optional<String>.none)
                ForEach(garments) { item in
                    Text(item.selectionLabel).tag(Optional(item.id))
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                if let message = mannequin.loadError {
                    Image(systemName: "exclamationmark.circle")
                    Text(message)
                } else if garment.isSettling {
                    ProgressView()
                        .controlSize(.small)
                    Text("착장 계산 중")
                } else if let message = garment.fitMessage {
                    Image(systemName: "exclamationmark.circle")
                    Text(message)
                } else if garments.isEmpty {
                    Text("의류 목록을 불러올 수 없습니다")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minHeight: 24, alignment: .leading)
            mannequinScene
            viewControls
        }
        .onAppear {
            mannequin.update(body: bodyData, base: mannequinBase)
            garment.update(definition: selectedGarment, mannequin: mannequin)
        }
        .onDisappear { garment.cancelSettling() }
    }

    private var mannequinScene: some View {
        RealityView {

            content in

            content.camera = .virtual

            let scene = Entity()
            scene.name = "WEASHION_SCENE"

            mannequin.update(body: bodyData, base: mannequinBase)
            garment.update(definition: selectedGarment, mannequin: mannequin)
            displayRoot.addChild(mannequin.root)
            displayRoot.addChild(garment.root)
            scene.addChild(displayRoot)


            let ground = makeGround(
                weather: weather
            )

            scene.addChild(ground)

            content.add(scene)


            camera.camera.fieldOfViewInDegrees = 38
            updateViewpoint()

            content.add(camera)


            let light = DirectionalLight()

            light.light.intensity = 1400
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

            content.add(light)


            let ambientLight = PointLight()

            ambientLight.light.intensity = 300

            ambientLight.position = [
                2,
                1.8,
                2
            ]

            content.add(ambientLight)

        } update: {

            content in

            mannequin.update(body: bodyData, base: mannequinBase)
            garment.update(definition: selectedGarment, mannequin: mannequin)
            updateViewpoint()
        }
        .frame(height: 500)
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
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24
            )
        )
    }

    private var viewControls: some View {
        HStack(spacing: 4) {
            viewControl("Rotate left", symbol: "rotate.left") {
                rotate(by: -.pi / 4)
            }
            viewControl("Rotate right", symbol: "rotate.right") {
                rotate(by: .pi / 4)
            }
            viewControl("Zoom out", symbol: "minus.magnifyingglass") {
                changeZoom(by: 1 / 1.2)
            }
            .disabled(zoom <= zoomRange.lowerBound)
            viewControl("Zoom in", symbol: "plus.magnifyingglass") {
                changeZoom(by: 1.2)
            }
            .disabled(zoom >= zoomRange.upperBound)
            viewControl("Reset view", symbol: "arrow.counterclockwise") {
                rotation = 0
                zoom = 1
                focus = .zero
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
    }

    private func updateViewpoint() {
        displayRoot.orientation = simd_quatf(angle: rotation, axis: [0, 1, 0])
        let target = focus + SIMD3<Float>(0, Float(bodyData.height) / 200, 0)
        camera.look(
            at: target,
            from: target + cameraOffset / zoom,
            relativeTo: nil
        )
    }

    private func rotate(by angle: Float) {
        rotation = (rotation + angle).truncatingRemainder(dividingBy: 2 * .pi)
    }

    private func changeZoom(by factor: Float, at location: CGPoint? = nil, in size: CGSize = .zero) {
        let nextZoom = min(max(zoom * factor, zoomRange.lowerBound), zoomRange.upperBound)
        if let location, size.width > 0, size.height > 0 {
            let forward = -simd_normalize(cameraOffset)
            let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
            let up = simd_cross(right, forward)
            let visibleHeight = 2 * simd_length(cameraOffset) / zoom * tan(Float(19) * .pi / 180)
            let horizontal = Float(location.x / size.width - 0.5) * visibleHeight * Float(size.width / size.height)
            let vertical = Float(0.5 - location.y / size.height) * visibleHeight
            focus += (right * horizontal + up * vertical) * (1 - zoom / nextZoom)
        }
        zoom = nextZoom
    }

    private func viewControl(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
