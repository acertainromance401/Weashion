import SwiftUI

struct GarmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var size: GarmentSizeInput
    @State var product = GarmentProductInfo()
    let definition: GarmentDefinition
    let bodyData: UserBody
    let mannequinBase: MannequinBase
    let weather: WeatherInfo
    var sampleDefinitions: [GarmentDefinition] = []
    var showsPreview = true
    var showsProductFields = true
    var requiresSizeLabel = false
    var saveTitle = L("내 마네킹에 적용")
    var isNewSize = false
    var onPreviewChange: ((GarmentSizeInput) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    let onSave: (GarmentSizeInput, GarmentProductInfo) throws -> Void
    @State private var lastValidSize: GarmentSizeInput?
    @State private var saveError: String?
    @FocusState private var focusedField: String?
    @State private var highlightedMeasurement: GarmentPlateMeasurement?

    private var sizeLabelTitle: String { requiresSizeLabel ? L("사이즈명") : L("상품 사이즈명 · 선택") }
    private var labelCalibration: GarmentSizeLabelCalibration {
        .init(templateID: definition.pattern.id)
    }
    private var valid: Bool {
        size.isValid && size.specification.isValid && (!showsProductFields || product.hasValidSource)
            && (!requiresSizeLabel || !product.sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!showsProductFields || !product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var firstInvalidField: String? {
        if showsProductFields && product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L("상품명") }
        if requiresSizeLabel && product.sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return sizeLabelTitle }
        if showsProductFields && !product.hasValidSource { return L("상품 URL · 선택") }
        let measurements: [(String, Double?, ClosedRange<Double>)] = [
            (L("총장"), size.length, 20...120), (L("어깨너비"), size.shoulderWidth, 20...90),
            (L("가슴단면"), size.chestWidth, 25...100), (L("소매길이"), size.sleeveLength, 5...80),
            (L("소매통"), size.sleeveWidthPercent, 50...150),
            (L("밑단단면"), size.hemWidth, 25...100), (L("소매부리단면"), size.sleeveOpeningWidth, 6...40),
            (L("암홀"), size.armhole, 10...45)
        ]
        for (title, value, range) in measurements {
            if let value, !range.contains(value) { return title }
        }
        if let armhole = size.armhole, armhole >= size.length { return L("암홀") }
        return size.specification.isValid ? nil : L("총장")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = EditorialLayout.usesColumns(width: geometry.size.width,
                                                       accessibility: dynamicTypeSize.isAccessibilitySize)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            EditorialPageTitle(number: "02", section: "THE SIZE NOTES",
                                               title: L("사이즈 치수"),
                                               subtitle: L("쇼핑몰의 숫자를, 나의 실루엣으로."), compact: true, style: .statement)
                            if showsPreview && wide {
                                HStack(alignment: .top, spacing: 32) {
                                    preview(height: 420).frame(maxWidth: .infinity)
                                    fields.frame(maxWidth: .infinity)
                                }
                            } else {
                                if showsPreview { preview(height: 230) }
                                fields
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("garmentEditorScroll")
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 10) {
                            if let field = firstInvalidField {
                                Button {
                                    withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) {
                                        proxy.scrollTo(field, anchor: .center)
                                    }
                                    focusedField = field
                                } label: {
                                    Label("\(field) 입력 확인하기", systemImage: "exclamationmark.circle")
                                        .editorialSans(.caption)
                                        .foregroundStyle(Editorial.error)
                                        .frame(minHeight: 44)
                                }
                                .accessibilityIdentifier("reviewInvalidMeasurement")
                            }
                            Button {
                                focusedField = nil
                                do {
                                    try onSave(size, product)
                                    close()
                                } catch {
                                    saveError = error.localizedDescription
                                }
                            } label: {
                                HStack {
                                    Text(saveTitle)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .buttonStyle(EditorialButtonStyle(filled: true))
                            .disabled(!valid)
                            .accessibilityIdentifier("applyGarmentMeasurements")
                        }
                        .padding(20)
                        .background(Editorial.paper)
                        .onChange(of: highlightedMeasurement) { _, measurement in
                            guard let measurement else { return }
                            withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) {
                                proxy.scrollTo(measurement.title, anchor: .center)
                            }
                        }
                    }
                    .background(Editorial.paper)
                }
            }
            .editorialNavigationTitle(L("상품 치수 입력"))
            .interactiveDismissDisabled()
            .editorialError($saveError)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: close)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") { focusedField = nil }
                }
            }
            .onChange(of: size, initial: true) { _, next in
                if next.isValid && next.specification.isValid {
                    lastValidSize = next
                    onPreviewChange?(next)
                }
            }
            .onChange(of: showsPreview) { _, _ in
                if let lastValidSize { onPreviewChange?(lastValidSize) }
            }
            .onChange(of: focusedField) { _, field in
                if let measurement = GarmentPlateMeasurement.allCases.first(where: { $0.title == field }) {
                    highlightedMeasurement = measurement
                }
            }
        }
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .tint(Editorial.accent)
        .buttonStyle(EditorialPressStyle())
        .preferredColorScheme(.light)
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }

    private func preview(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WEASHIONSceneView(
                bodyData: bodyData, mannequinBase: mannequinBase, weather: weather,
                sceneHeight: height,
                garmentOverride: (lastValidSize ?? size).applying(to: definition),
                isGarmentEditor: true, isEditorial: true
            )
            .overlay(Rectangle().strokeBorder(Editorial.rule, lineWidth: 0.5))
            Text(size.isValid && size.specification.isValid ? L("LIVE PREVIEW / 입력 치수 반영") : L("입력 범위를 확인해 주세요 · 직전 유효 치수 표시"))
                .editorialSans(.caption2)
                .foregroundStyle(size.isValid && size.specification.isValid ? Editorial.muted : Editorial.error)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                EditorialHeading(number: "01", title: showsProductFields ? "The garment" : product.name,
                                 subtitle: L("이 상품의 사이즈 치수를 기록합니다."))
                if showsProductFields {
                    textField(L("상품명"), placeholder: L("예: 마음에 든 코튼 반팔"), text: $product.name)
                    textField(L("상품 URL · 선택"), placeholder: "https://", text: $product.source)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if !product.hasValidSource {
                        Text("http 또는 https로 시작하는 올바른 상품 URL을 입력해 주세요.")
                            .editorialSans(.caption).foregroundStyle(Editorial.error)
                    }
                }
                textField(sizeLabelTitle, placeholder: L("예: M / 95 / 2"), text: $product.sizeLabel)
                if isNewSize {
                    Text("초기 치수는 설명용 샘플값입니다. 상품의 실제 사이즈표로 바꿔 입력해 주세요.")
                        .editorialSans(.caption).foregroundStyle(Editorial.warning)
                }
                Text("URL은 원본 상품을 다시 열기 위한 메모입니다. 치수·사진·디자인은 자동으로 불러오지 않습니다.")
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
            }
            VStack(alignment: .leading, spacing: 14) {
                EditorialHeading(number: "02", title: "The measurements",
                                 subtitle: definition.kind == .shortSleeveTShirt
                                    ? L("반팔 사이즈표를 그대로, cm로.") : L("상의 사이즈표를 그대로, cm로."))
                if definition.kind == .shortSleeveTShirt {
                    GarmentMeasurementPlate(size: lastValidSize ?? size, showsValues: false,
                                            selection: $highlightedMeasurement)
                } else {
                    Text("선택한 상의 모델의 치수입니다. 반팔 측정 도식은 사용하지 않습니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
                HStack(spacing: 10) {
                    ForEach(["S", "M", "L"], id: \.self) { label in
                        Button {
                            let fabric = size.fabric
                            guard let sample = sampleInput(label) else { return }
                            size = sample
                            size.fabric = fabric
                            product.sizeLabel = label
                        } label: {
                            Text("샘플 \(label)").editorialSans(.caption)
                        }
                        .buttonStyle(EditorialChoiceStyle(selected: product.sizeLabel == label))
                        .disabled(sampleInput(label) == nil)
                    }
                }
                Text("샘플 S/M/L은 크기 비교용이며 실측 상품 데이터가 아닙니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.warning)
                measurement(L("총장"), number: "1", value: $size.length, range: 20...120, displayScale: labelCalibration.length)
                measurement(L("어깨너비"), number: "2", value: $size.shoulderWidth, range: 20...90, displayScale: labelCalibration.shoulder)
                measurement(L("가슴단면"), number: "3", value: $size.chestWidth, range: 25...100, displayScale: labelCalibration.chest)
                measurement(L("소매길이"), number: "4", value: $size.sleeveLength, range: 5...80, displayScale: labelCalibration.sleeve)
                measurement(L("소매통"), value: Binding(
                    get: { size.sleeveWidthPercent ?? 100 },
                    set: { size.sleeveWidthPercent = $0 == 100 ? nil : $0 }
                ), range: 50...150, unit: "%", displayScale: labelCalibration.sleeveWidth)
                if definition.pattern.id == "meshy-hoodie" {
                    Text("후디 숫자는 보정된 샘플 기준값입니다. 실제 모델 치수와 구분하며, 기존 착용 형태와 저장값은 유지됩니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
                Text("소매통은 입력 치수에 추가 적용하는 비율입니다. 100%가 기본이며 위팔·아래팔·소매 끝을 같은 비율로 조절합니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
                Text("가슴단면은 옷을 평평하게 놓고 잰 너비입니다. 신체 가슴둘레와는 다른 값이에요.")
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
            }
            VStack(alignment: .leading, spacing: 14) {
                EditorialHeading(number: "03", title: "The details", subtitle: L("추가 치수 · 알고 있을 때만 입력하세요."))
                optionalMeasurement(L("밑단단면"), value: $size.hemWidth, fallback: size.chestWidth, range: 25...100)
                optionalMeasurement(L("소매부리단면"), value: $size.sleeveOpeningWidth, fallback: 18, range: 6...40)
                optionalMeasurement(L("암홀"), value: $size.armhole, fallback: 24, range: 10...45)
                Text("추가 치수를 모르면 꺼 두세요. 해당 부위는 샘플의 원본 비율을 사용합니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
            }
            VStack(alignment: .leading, spacing: 14) {
                EditorialHeading(number: "04", title: "The fabric", subtitle: L("추정 소재 특성 · 실측 원단 물성이 아닙니다."))
                Picker("신축성", selection: fabricBinding(\.stretch)) {
                    ForEach(GarmentFabricSettings.Stretch.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("촉감", selection: fabricBinding(\.softness)) {
                    ForEach(GarmentFabricSettings.Softness.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("두께", selection: fabricBinding(\.thickness)) {
                    ForEach(GarmentFabricSettings.Thickness.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Text("소재 선택은 계산용 추정치이며 실측 신축률·원단 물성이 아닙니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
            }
            .pickerStyle(.menu)
            if !size.isValid || !size.specification.isValid {
                Label("입력 가능한 치수 범위와 치수 간 비율을 확인해 주세요. 잘못된 값은 적용할 수 없습니다.",
                      systemImage: "exclamationmark.circle")
                    .editorialSans(.caption).foregroundStyle(Editorial.error)
            }
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Editorial.rule).frame(height: 1)
                Text("A preview, not a promise.").font(Editorial.headline(22))
                Text(definition.kind == .shortSleeveTShirt
                     ? L("코튼 반팔 샘플에 치수와 추정 소재 특성을 적용합니다. 실제 상품의 패턴·실측 원단 물성과 다르며 정확한 핏이나 착용 가능 여부를 보장하지 않습니다.")
                     : L("선택한 상의 샘플에 치수와 추정 소재 특성을 적용합니다. 실제 상품의 패턴·실측 원단 물성과 다르며 정확한 핏이나 착용 가능 여부를 보장하지 않습니다."))
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
            }
        }
    }

    private func sampleInput(_ label: String) -> GarmentSizeInput? {
        if let sample = sampleDefinitions.first(where: {
            $0.pattern.id == definition.pattern.id && $0.kind == definition.kind && $0.selectionLabel == label
        })?.measurements?.shortSleeve {
            return sample
        }
        guard definition.kind == .shortSleeveTShirt else { return nil }
        switch label {
        case "S": return .small
        case "L": return .large
        default: return .medium
        }
    }

    private func fabricBinding<Value>(_ keyPath: WritableKeyPath<GarmentFabricSettings, Value>) -> Binding<Value> {
        Binding(
            get: { (size.fabric ?? definition.material.fabricSettings)[keyPath: keyPath] },
            set: { value in
                var fabric = size.fabric ?? definition.material.fabricSettings
                fabric[keyPath: keyPath] = value
                size.fabric = fabric
            }
        )
    }

    private func textField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).editorialSans(.caption).foregroundStyle(Editorial.muted)
            TextField(placeholder, text: text)
                .editorialSans(.subheadline)
                .focused($focusedField, equals: title)
                .editorialInput(focused: focusedField == title,
                                invalid: title == L("상품 URL · 선택") && !product.hasValidSource)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focusedField = title })
                .accessibilityLabel(title)
        }
        .id(title)
    }

    private func measurement(_ title: String, number: String? = nil,
                             value: Binding<Double>, range: ClosedRange<Double>, unit: String = "cm",
                             displayScale: Double = 1) -> some View {
        let displayed = Binding(get: { value.wrappedValue * displayScale },
                                set: { value.wrappedValue = $0 / displayScale })
        let highlighted = number.map { highlightedMeasurement?.number == $0 } ?? false
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                HStack(spacing: 12) {
                    if let number {
                        Text(number).editorialSans(.caption).monospacedDigit()
                            .foregroundStyle(highlighted ? Editorial.accent : Editorial.muted)
                            .accessibilityHidden(true)
                    }
                    Text(title).editorialSans(.subheadline)
                        .foregroundStyle(highlighted ? Editorial.accent : Editorial.ink)
                }
                HStack(spacing: 12) {
                    Spacer(minLength: 8)
                    TextField(title, value: displayed, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: title)
                        .frame(minWidth: 72, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 72,
                               minHeight: 20)
                        .editorialInput(focused: focusedField == title, invalid: !range.contains(value.wrappedValue))
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { focusedField = title })
                        .accessibilityLabel(unit == "cm" ? "\(title) 센티미터" : "\(title) %")
                        .accessibilityIdentifier("measurement-\(title)")
                    Text(unit).editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
            }
            .id(title)
            if !range.contains(value.wrappedValue) {
                Group {
                    if unit == "%" && displayScale == 1 {
                        Text("50–150% 범위로 입력해 주세요.")
                    } else if unit == "%" {
                        Text("\(range.lowerBound * displayScale, specifier: "%.1f")–\(range.upperBound * displayScale, specifier: "%.1f")% 범위로 입력해 주세요.")
                    } else {
                        Text("\(range.lowerBound * displayScale, specifier: "%.0f")–\(range.upperBound * displayScale, specifier: "%.0f") cm 범위로 입력해 주세요.")
                    }
                }
                .editorialSans(.caption).foregroundStyle(Editorial.error)
            }
        }
    }

    private func optionalMeasurement(_ title: String, value: Binding<Double?>, fallback: Double,
                                     range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { value.wrappedValue != nil }, set: {
                value.wrappedValue = $0 ? fallback : nil
            })) {
                Text(title).editorialSans(.subheadline)
            }
            .tint(Editorial.accent)
            if value.wrappedValue != nil {
                measurement(title, value: Binding(get: { value.wrappedValue ?? fallback }, set: {
                    value.wrappedValue = $0
                }), range: range)
                .transition(.opacity)
            }
        }
        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: value.wrappedValue != nil)
    }
}
