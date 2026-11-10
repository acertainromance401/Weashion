import SwiftUI

enum GarmentPlateMeasurement: Int, CaseIterable, Identifiable {
    case length = 1, shoulder, chest, sleeve
    var id: Int { rawValue }
    var number: String { String(rawValue) }
    var title: String {
        switch self {
        case .length: L("총장")
        case .shoulder: L("어깨너비")
        case .chest: L("가슴단면")
        case .sleeve: L("소매길이")
        }
    }

    func value(in size: GarmentSizeInput) -> Double {
        switch self {
        case .length: size.length
        case .shoulder: size.shoulderWidth
        case .chest: size.chestWidth
        case .sleeve: size.sleeveLength
        }
    }
}

struct GarmentMeasurementPlate: View {
    let size: GarmentSizeInput
    var showsValues = true
    var selection: Binding<GarmentPlateMeasurement?>? = nil
    @State private var localSelection: GarmentPlateMeasurement?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    private var focus: Binding<GarmentPlateMeasurement?> { selection ?? $localSelection }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsValues && !dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 36) {
                        diagram.frame(width: 280)
                        measurementNotes.frame(minWidth: 240)
                    }
                    .frame(minWidth: 560)
                    VStack(alignment: .leading, spacing: 24) {
                        diagram
                        measurementNotes
                    }
                }
            } else {
                diagram
                if showsValues { measurementNotes }
            }
            EditorialFigureCaption(number: "02", text: L("샘플 반팔 측정 위치 도식 · 실제 상품 이미지나 비율 재현이 아닙니다."))
        }
    }

    private var diagram: some View {
        GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                ZStack {
                    GarmentIllustration()
                        .padding(.horizontal, w * 0.14)
                        .padding(.vertical, h * 0.05)
                        .accessibilityHidden(true)
                    Canvas { context, canvas in
                        let lines: [(CGPoint, CGPoint)] = [
                            (.init(x: 0.89, y: 0.16), .init(x: 0.89, y: 0.86)),
                            (.init(x: 0.29, y: 0.13), .init(x: 0.71, y: 0.13)),
                            (.init(x: 0.35, y: 0.56), .init(x: 0.65, y: 0.56)),
                            (.init(x: 0.7, y: 0.2), .init(x: 0.82, y: 0.4))
                        ]
                        for (index, line) in lines.enumerated() {
                            let (start, end) = line
                            let a = CGPoint(x: start.x * canvas.width, y: start.y * canvas.height)
                            let b = CGPoint(x: end.x * canvas.width, y: end.y * canvas.height)
                            let length = hypot(b.x - a.x, b.y - a.y)
                            let dx = -(b.y - a.y) / length * 4
                            let dy = (b.x - a.x) / length * 4
                            var path = Path()
                            path.move(to: a)
                            path.addLine(to: b)
                            for point in [a, b] {
                                path.move(to: .init(x: point.x - dx, y: point.y - dy))
                                path.addLine(to: .init(x: point.x + dx, y: point.y + dy))
                            }
                            let selected = focus.wrappedValue?.rawValue == index + 1
                            context.stroke(path, with: .color(selected ? Editorial.accent : Editorial.ink),
                                           lineWidth: selected ? 2 : 0.8)
                        }
                    }
                    .accessibilityHidden(true)
                    marker(.length, x: w * 0.94, y: h * 0.51, width: w)
                    marker(.shoulder, x: w * 0.5, y: h * 0.03, width: w)
                    marker(.chest, x: w * 0.5, y: h * 0.66, width: w)
                    marker(.sleeve, x: w * 0.81, y: h * 0.24, width: w)
                }
        }
        .frame(height: showsValues ? 255 : 180)
    }

    private var measurementNotes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: 24) {
            ForEach(GarmentPlateMeasurement.allCases) { measurement in
                note(measurement)
            }
        }
    }

    private func marker(_ measurement: GarmentPlateMeasurement, x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Text(measurement.number)
                .font(Editorial.serif(19, italic: true))
                .foregroundStyle(Editorial.accent)
                .padding(.horizontal, 4)
                .background(focus.wrappedValue == measurement ? Editorial.stock : Editorial.paper)
                .position(x: x, y: y)
                .accessibilityHidden(true)
            Button { focus.wrappedValue = measurement } label: {
                Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(measurement.title) · 측정 위치 \(measurement.number)")
            .accessibilityValue(Text("\(measurement.value(in: size), specifier: "%.1f") cm"))
            .accessibilityAddTraits(focus.wrappedValue == measurement ? .isSelected : [])
            .accessibilityIdentifier("garment-marker-\(measurement.number)")
            .position(x: min(max(x, 22), width - 22), y: y)
        }
    }

    private func note(_ measurement: GarmentPlateMeasurement) -> some View {
        let number = measurement.number
        let title = measurement.title
        let value = measurement.value(in: size)
        let selected = focus.wrappedValue == measurement
        return Button { focus.wrappedValue = measurement } label: {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("0\(number)").font(Editorial.serif(12, italic: true)).foregroundStyle(Editorial.accent)
                Text(title).editorialSans(.caption)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value, specifier: "%.1f")")
                    .font(Editorial.serif(48 * min(scale, 1.3))).monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: value)
                Text("cm").font(Editorial.serif(13, italic: true)).foregroundStyle(Editorial.muted)
            }
            Rectangle().fill(selected ? Editorial.accent : Editorial.rule).frame(height: 0.5)
        }
        .foregroundStyle(selected ? Editorial.accent : Editorial.ink)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) · 측정 위치 \(number)")
        .accessibilityValue(Text("\(value, specifier: "%.1f") cm"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("garment-note-\(number)")
    }
}

struct EditorialSizeSpread: View {
    let product: GarmentProduct
    let selectedID: String?
    let supportsFitting: Bool
    var margin: CGFloat = 20
    var onBrowse: (() -> Void)? = nil
    let onSelect: (ProductSize) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    @Namespace private var selection

    private let paper = Editorial.paper

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    EditorialEyebrow(text: L("THE SIZE EDIT · 사이즈 노트"), color: paper.opacity(0.7))
                    Spacer()
                    Text("N° 02").font(Editorial.serif(14, italic: true)).foregroundStyle(paper.opacity(0.7))
                        .accessibilityHidden(true)
                }
                Text("Size matters.")
                    .font(Editorial.serif(52 * min(scale, 1.2), italic: true))
                    .foregroundStyle(paper)
                    .editorialReveal(from: .leading, distance: 64)
                Text(product.name)
                    .editorialSans(.title3, weight: .semibold)
                    .foregroundStyle(paper)
                    .fixedSize(horizontal: false, vertical: true)
                    .editorialReveal(from: .leading)
                if product.sizes.isEmpty {
                    Label("이 상품에 사이즈를 추가해 주세요.", systemImage: "ruler")
                        .editorialSans(.subheadline)
                        .foregroundStyle(paper)
                } else {
                    VStack(spacing: 0) {
                        ForEach(product.sizes) { size in
                            sizeNote(size)
                                .editorialReveal(distance: 40)
                        }
                    }
                    Text("그림이 아니라 숫자가 비교 기준입니다.")
                        .editorialSans(.caption)
                        .foregroundStyle(paper.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onBrowse {
                    Button(action: onBrowse) {
                        HStack(spacing: 8) {
                            Text("모든 상품과 사이즈").editorialSans(.caption, weight: .medium).underline()
                            Image(systemName: "arrow.right").font(.caption2)
                        }
                        .foregroundStyle(paper)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EditorialPressStyle())
                    .accessibilityIdentifier("browseProducts")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            EditorialRunningHead(text: "THE SIZE STUDY / 002", color: paper.opacity(0.6),
                                 font: .system(size: 9, design: .monospaced), tracking: 1.5, thickness: 14)
                .padding(.leading, 12)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, margin)
        .padding(.top, 48)
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.ink)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("사이즈 노트, \(product.name)")
    }

    private func sizeNote(_ size: ProductSize) -> some View {
        let measurements = size.measurements?.displayed(for: product.templateID)
        let selected = size.id == selectedID
        let available = supportsFitting && size.hasValidMeasurements && measurements?.supports(product.kind) == true
        let latin = size.label.unicodeScalars.allSatisfy { $0.isASCII }
        return Button { onSelect(size) } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 22))
            VStack(alignment: .leading, spacing: 0) {
                layout {
                    Text(size.label)
                        .font(latin ? Editorial.serif((size.label.count > 3 ? 40 : 64) * min(scale, 1.3)) : Editorial.hangul(28, relativeTo: .largeTitle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 0 : 76, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        if let measurements, measurements.supports(product.kind) {
                            ForEach(measurements.editorialPrimaryFields) { field in
                                Text("\(field.title) \(field.formatted)")
                                    .editorialSans(.caption).monospacedDigit()
                            }
                        } else {
                            Text("치수 정보 없음 · 종류 확인").editorialSans(.caption)
                        }
                        EditorialEyebrow(text: size.isSample ? "SAMPLE" : "YOUR NOTES", color: paper.opacity(0.55))
                        if size.isSample {
                            Text("설명용 치수 · 실측 상품 아님").editorialSans(.caption2)
                        }
                    }
                    .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : 10)
                    Spacer(minLength: 0)
                    Text(!available ? L("피팅 준비 필요") : selected ? L("선택됨") : L("입혀보기"))
                        .editorialSans(.caption)
                        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : 12)
                    Image(systemName: selected ? "checkmark" : "arrow.right")
                        .editorialSans(.caption, weight: .medium)
                        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : 12)
                }
                .padding(.vertical, 14)
                Rectangle().fill(paper.opacity(0.18)).frame(height: 0.5)
                    .overlay(alignment: .leading) {
                        if selected {
                            Rectangle().fill(paper).frame(height: 1.5)
                                .matchedGeometryEffect(id: "size-note", in: selection)
                        }
                    }
            }
            .foregroundStyle(paper.opacity(selected || available ? 1 : 0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(EditorialPressStyle())
        .disabled(!available)
        .accessibilityLabel("\(size.label) 치수 노트 선택")
        .accessibilityValue(measurements.map {
            $0.supports(product.kind)
                ? $0.editorialPrimaryFields.map { "\($0.title) \($0.formatted)" }.joined(separator: ", ")
                : L("치수 종류를 확인해 주세요.")
        } ?? L("치수 정보 없음"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("size-note-\(size.id)")
        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: selectedID)
    }
}

struct EditorialGarmentArtwork: View {
    let number: String
    var selected = false
    var kind: GarmentKind = .shortSleeveTShirt

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Editorial.studio
                Rectangle()
                    .fill(Editorial.paper)
                    .frame(width: geometry.size.width * 0.36)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(number)
                    .font(Editorial.serif(min(geometry.size.height * 0.82, 160), italic: true))
                    .foregroundStyle(Editorial.ink.opacity(0.06))
                    .padding(.leading, 8)
                Group {
                    if kind == .shortSleeveTShirt {
                        GarmentIllustration(tint: Color(red: 0.46, green: 0.47, blue: 0.47))
                    } else {
                        WearableSilhouette(kind: kind)
                            .fill(Color(red: 0.46, green: 0.47, blue: 0.47).opacity(0.75))
                            .overlay(WearableSilhouette(kind: kind).stroke(Editorial.ink.opacity(0.4), lineWidth: 0.8))
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.13)
                .padding(.vertical, geometry.size.height * 0.08)
                .rotationEffect(.degrees(-7))
                if selected {
                    Label("선택됨", systemImage: "checkmark")
                        .editorialSans(.caption2, weight: .medium)
                        .padding(8)
                        .foregroundStyle(Editorial.accent)
                        .background(Editorial.paper)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WearableSilhouette: Shape {
    let kind: GarmentKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint]
        switch kind {
        case .pants, .shorts:
            let hem: CGFloat = kind == .shorts ? 0.62 : 0.96
            points = [
                .init(x: 0.28, y: 0.04), .init(x: 0.72, y: 0.04),
                .init(x: 0.8, y: hem), .init(x: 0.56, y: hem),
                .init(x: 0.5, y: 0.37), .init(x: 0.44, y: hem),
                .init(x: 0.2, y: hem)
            ]
        case .shoes:
            points = [
                .init(x: 0.12, y: 0.52), .init(x: 0.22, y: 0.35),
                .init(x: 0.36, y: 0.48), .init(x: 0.53, y: 0.3),
                .init(x: 0.72, y: 0.56), .init(x: 0.91, y: 0.63),
                .init(x: 0.96, y: 0.76), .init(x: 0.87, y: 0.82),
                .init(x: 0.1, y: 0.82), .init(x: 0.08, y: 0.68)
            ]
        case .knitwear:
            points = [
                .init(x: 0.4, y: 0.19), .init(x: 0.4, y: 0.05),
                .init(x: 0.5, y: 0), .init(x: 0.6, y: 0.05),
                .init(x: 0.6, y: 0.19), .init(x: 0.75, y: 0.25),
                .init(x: 0.96, y: 0.78), .init(x: 0.82, y: 0.86),
                .init(x: 0.68, y: 0.48), .init(x: 0.7, y: 0.96),
                .init(x: 0.3, y: 0.96), .init(x: 0.32, y: 0.48),
                .init(x: 0.18, y: 0.86), .init(x: 0.04, y: 0.78),
                .init(x: 0.25, y: 0.25)
            ]
        default:
            points = [
                .init(x: 0.4, y: 0.08), .init(x: 0.5, y: 0.16),
                .init(x: 0.6, y: 0.08), .init(x: 0.75, y: 0.18),
                .init(x: 0.98, y: 0.79), .init(x: 0.83, y: 0.88),
                .init(x: 0.69, y: 0.43), .init(x: 0.7, y: 0.96),
                .init(x: 0.3, y: 0.96), .init(x: 0.31, y: 0.43),
                .init(x: 0.17, y: 0.88), .init(x: 0.02, y: 0.79),
                .init(x: 0.25, y: 0.18)
            ]
        }
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}
