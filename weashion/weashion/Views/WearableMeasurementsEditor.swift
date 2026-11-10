import SwiftUI

struct WearableMeasurementValue: Identifiable {
    let id: String
    let title: String
    let value: Double
    let unit: String
    let range: ClosedRange<Double>

    var formatted: String { String(format: "%.1f", value) + " " + unit }
}

extension GarmentMeasurements {
    var editorialFields: [WearableMeasurementValue] {
        switch self {
        case .shortSleeve(let input):
            [
                .init(id: "length", title: L("총장"), value: input.length, unit: "cm", range: 20...120),
                .init(id: "shoulder", title: L("어깨너비"), value: input.shoulderWidth, unit: "cm", range: 20...90),
                .init(id: "chest", title: L("가슴단면"), value: input.chestWidth, unit: "cm", range: 25...100),
                .init(id: "sleeve", title: L("소매길이"), value: input.sleeveLength, unit: "cm", range: 5...80),
                .init(id: "sleeveWidth", title: L("소매통"), value: input.sleeveWidthPercent ?? 100, unit: "%", range: 50...150)
            ]
        case .trousers(let input):
            [
                .init(id: "totalLength", title: L("총장"), value: input.totalLength, unit: "cm", range: input.totalLengthRange),
                .init(id: "legWidth", title: L("바지통"), value: input.legWidthPercent ?? 100, unit: "%", range: 50...150),
                .init(id: "waist", title: L("허리단면"), value: input.waistWidth, unit: "cm", range: 20...100),
                .init(id: "hip", title: L("엉덩이단면"), value: input.hipWidth, unit: "cm", range: 25...120),
                .init(id: "rise", title: L("밑위"), value: input.rise, unit: "cm", range: 12...50),
                .init(id: "inseam", title: L("인심"), value: input.inseam, unit: "cm", range: 30...120),
                .init(id: "thigh", title: L("허벅지단면"), value: input.thighWidth, unit: "cm", range: 12.5...60),
                .init(id: "hem", title: L("밑단단면"), value: input.hemWidth, unit: "cm", range: 7.5...45)
            ]
        case .footwear(let input):
            [
                .init(id: "length", title: L("신발 외부 길이"), value: input.length, unit: "mm", range: 150...400),
                .init(id: "width", title: L("신발 외부 너비"), value: input.width, unit: "mm", range: 50...180)
            ]
        }
    }

    var editorialPrimaryFields: [WearableMeasurementValue] {
        switch self {
        case .shortSleeve: editorialFields.filter { ["length", "chest"].contains($0.id) }
        case .trousers: editorialFields.filter { ["waist", "hip", "totalLength"].contains($0.id) }
        case .footwear: editorialFields
        }
    }

    var editorialMeasurementNote: String {
        switch self {
        case .shortSleeve:
            L("가슴단면은 펼친 옷의 폭입니다. 신체 가슴둘레나 착장 후 정면 폭과는 다른 값입니다.")
        case .trousers:
            L("총장은 밑위 + 인심의 근사값입니다. 총장을 바꾸면 밑위는 유지하고 인심을 변경합니다. 단면 × 2로 둘레를 비교하며 인심은 가랑이에서 밑단까지입니다.")
                + "\n" + L("바지통은 입력 단면 치수에 추가 적용하는 비율입니다. 100%가 기본이며 허리·엉덩이·총장은 유지하고 허벅지부터 밑단까지 함께 조절합니다.")
        case .footwear:
            L("신발의 외부 길이·너비(mm)입니다. 브랜드 호수나 신발 내부 치수가 아니며 실제 발의 여유·착화감을 판정하지 않습니다.")
        }
    }

    func editorialDifferences(from previous: GarmentMeasurements) -> [WearableMeasurementValue] {
        switch (previous, self) {
        case (.shortSleeve, .shortSleeve), (.trousers, .trousers), (.footwear, .footwear):
            let before = previous.editorialFields
            return editorialFields.compactMap { field in
                guard let old = before.first(where: { $0.id == field.id }) else { return nil }
                return .init(id: field.id, title: field.title, value: field.value - old.value,
                             unit: field.unit, range: field.range)
            }
        default: return []
        }
    }
}

struct WearableMeasurementSummary: View {
    let measurements: GarmentMeasurements
    var primaryOnly = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: 18) {
            ForEach(primaryOnly ? measurements.editorialPrimaryFields : measurements.editorialFields) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.title).editorialSans(.caption).foregroundStyle(Editorial.muted)
                    Text(field.formatted).font(Editorial.serif(28)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct WearableMeasurementsEditor: View {
    @State var measurements: GarmentMeasurements
    @State var sizeLabel: String
    let definition: GarmentDefinition
    let bodyData: UserBody
    let mannequinBase: MannequinBase
    let weather: WeatherInfo
    var sampleDefinitions: [GarmentDefinition] = []
    var showsPreview = true
    var requiresSizeLabel = true
    var saveTitle = L("사이즈 저장")
    var isNewSize = false
    var onPreviewChange: ((GarmentMeasurements) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    let onSave: (GarmentMeasurements, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: String?
    @State private var drafts: [String: String] = [:]
    @State private var lastValidMeasurements: GarmentMeasurements?
    @State private var saveError: String?

    private var fields: [WearableMeasurementValue] {
        measurements.editorialFields.map { field in
            let riseText = (drafts["rise"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard field.id == "totalLength", let rise = Double(riseText), (12...50).contains(rise) else { return field }
            return .init(id: field.id, title: field.title, value: field.value, unit: field.unit, range: (rise + 30)...(rise + 120))
        }
    }
    private var compatible: Bool {
        switch measurements {
        case .trousers, .footwear: measurements.supports(definition.kind)
        case .shortSleeve: false
        }
    }
    private var validLabel: Bool {
        !requiresSizeLabel || !sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var valid: Bool { compatible && validLabel && candidate != nil }
    private var firstInvalidField: String? {
        if !validLabel { return "label" }
        return fields.first { field in
            guard let value = parsed(field) else { return true }
            return !field.range.contains(value)
        }?.id
    }

    private func text(_ field: WearableMeasurementValue) -> String {
        drafts[field.id] ?? String(format: "%.1f", field.value)
    }

    private func parsed(_ field: WearableMeasurementValue) -> Double? {
        Double(text(field).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var candidate: GarmentMeasurements? {
        guard compatible, fields.allSatisfy({ field in
            parsed(field).map { $0.isFinite && field.range.contains($0) } ?? false
        }) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            parsed(field).map { (field.id, $0) }
        })
        let next: GarmentMeasurements
        switch measurements {
        case .trousers(var input):
            input.waistWidth = values["waist"]!
            input.hipWidth = values["hip"]!
            input.rise = values["rise"]!
            input.inseam = values["inseam"]!
            input.thighWidth = values["thigh"]!
            input.hemWidth = values["hem"]!
            input.legWidthPercent = values["legWidth"]! == 100 ? nil : values["legWidth"]!
            next = .trousers(input)
        case .footwear(var input):
            input.length = values["length"]!
            input.width = values["width"]!
            next = .footwear(input)
        case .shortSleeve: return nil
        }
        return next.isValid ? next : nil
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
                                               title: L("사이즈 치수"), subtitle: definition.name,
                                               compact: true, style: .statement)
                            if showsPreview && wide {
                                HStack(alignment: .top, spacing: 32) {
                                    preview(height: 420).frame(maxWidth: .infinity)
                                    measurementFields.frame(maxWidth: .infinity)
                                }
                            } else {
                                if showsPreview { preview(height: 260) }
                                measurementFields
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
                                    Label("사이즈명과 입력 범위를 확인해 주세요.", systemImage: "exclamationmark.circle")
                                        .editorialSans(.caption).foregroundStyle(Editorial.error)
                                        .frame(minHeight: 44)
                                }
                                .accessibilityIdentifier("reviewInvalidMeasurement")
                            }
                            Button {
                                guard valid, let candidate else { return }
                                focusedField = nil
                                do {
                                    try onSave(candidate, sizeLabel.trimmingCharacters(in: .whitespacesAndNewlines))
                                    close()
                                } catch { saveError = error.localizedDescription }
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
                    }
                }
            }
            .background(Editorial.paper)
            .editorialNavigationTitle(L("상품 치수 입력"))
            .interactiveDismissDisabled()
            .editorialError($saveError)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소", action: close) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") { focusedField = nil }
                }
            }
            .onChange(of: candidate, initial: true) { _, next in
                if let next {
                    lastValidMeasurements = next
                    onPreviewChange?(next)
                }
            }
            .onChange(of: showsPreview) { _, _ in
                if let lastValidMeasurements { onPreviewChange?(lastValidMeasurements) }
            }
        }
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .tint(Editorial.accent)
        .buttonStyle(EditorialPressStyle())
        .preferredColorScheme(.light)
    }

    private var measurementFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !compatible {
                EditorialNotice(title: L("기준 모델과 치수 종류가 다릅니다."),
                                detail: L("기존 기록은 보존됩니다. 이 모델에 맞는 새 사이즈를 추가해 주세요."), tone: .error)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(requiresSizeLabel ? L("사이즈명") : L("상품 사이즈명 · 선택"))
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
                TextField(L("예: S / M / L"), text: $sizeLabel)
                    .focused($focusedField, equals: "label")
                    .editorialInput(focused: focusedField == "label", invalid: !validLabel)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { focusedField = "label" })
                    .accessibilityLabel("사이즈명")
                    .accessibilityIdentifier("wearableSizeLabel")
                if !validLabel {
                    Text("사이즈명을 입력해 주세요.").editorialSans(.caption).foregroundStyle(Editorial.error)
                }
            }
            .id("label")
            if isNewSize {
                Text("초기 치수는 설명용 샘플입니다. 상품의 실제 사이즈표로 바꿔 입력해 주세요.")
                    .editorialSans(.caption).foregroundStyle(Editorial.warning)
            }
            Text(measurements.editorialMeasurementNote)
                .editorialSans(.caption).foregroundStyle(Editorial.muted)
            if !sampleDefinitions.isEmpty {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    ForEach(sampleDefinitions.filter { $0.pattern.id == definition.pattern.id && $0.kind == definition.kind }) { sample in
                        Button {
                            guard var next = sample.measurements, next.supports(definition.kind) else { return }
                            if case .trousers(var input) = next, case .trousers(let previous) = measurements {
                                input.fabric = previous.fabric
                                next = .trousers(input)
                            }
                            measurements = next
                            drafts = [:]
                            sizeLabel = sample.selectionLabel
                        } label: {
                            Text("샘플 \(sample.selectionLabel)").editorialSans(.caption)
                        }
                        .buttonStyle(EditorialChoiceStyle(selected: sizeLabel == sample.selectionLabel))
                    }
                }
                Text("S/M/L은 크기 차이 확인용이며 실제 브랜드 호수나 실측 상품 데이터가 아닙니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.warning)
            }
            ForEach(fields) { field in
                measurementField(field)
            }
            Text("A preview, not a promise.").font(Editorial.headline(22))
            Text("치수 편집 미리보기는 이 상품만 표시합니다. 피팅룸에서는 상의·하의·신발·아우터를 함께 확인할 수 있습니다.")
                .editorialSans(.caption).foregroundStyle(Editorial.muted)
        }
    }

    private func measurementField(_ field: WearableMeasurementValue) -> some View {
        let invalid = parsed(field).map { !field.range.contains($0) } ?? true
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                Text(field.title).editorialSans(.subheadline)
                HStack {
                    Spacer(minLength: 0)
                    TextField(field.title, text: Binding(get: { text(field) }, set: { updateDraft($0, field: field.id) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: field.id)
                        .frame(minWidth: 72, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 96)
                        .editorialInput(focused: focusedField == field.id, invalid: invalid)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { focusedField = field.id })
                        .accessibilityLabel("\(field.title) \(field.unit)")
                        .accessibilityIdentifier("measurement-\(field.title)")
                    Text(field.unit).editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
            }
            if invalid {
                Text("\(field.range.lowerBound, specifier: "%.1f")–\(field.range.upperBound, specifier: "%.1f") \(field.unit) 범위로 입력해 주세요.")
                    .editorialSans(.caption).foregroundStyle(Editorial.error)
            }
        }
        .id(field.id)
    }

    private func preview(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preview = (lastValidMeasurements ?? measurements).applying(to: definition) {
                WEASHIONSceneView(bodyData: bodyData, mannequinBase: mannequinBase, weather: weather,
                                  sceneHeight: height, garmentOverride: preview,
                                  isGarmentEditor: true, isEditorial: true)
                    .overlay(Rectangle().strokeBorder(Editorial.rule, lineWidth: 0.5))
            }

            Text(candidate != nil ? L("LIVE PREVIEW / 입력 치수 반영") : L("입력 범위를 확인해 주세요 · 직전 유효 치수 표시"))
                .editorialSans(.caption2).foregroundStyle(candidate != nil ? Editorial.muted : Editorial.error)
        }
    }

    private func updateDraft(_ text: String, field: String) {
        drafts[field] = text
        func number(_ text: String) -> Decimal? {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite else { return nil }
            return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        }
        guard case .trousers(let input) = measurements,
              let value = number(text),
              let rise = number(drafts["rise"] ?? String(format: "%.1f", input.rise)) else { return }
        if field == "totalLength" {
            drafts["inseam"] = NSDecimalNumber(decimal: value - rise).stringValue
        } else if field == "inseam" || field == "rise" {
            guard let inseam = number(drafts["inseam"] ?? String(format: "%.1f", input.inseam)) else { return }
            drafts["totalLength"] = NSDecimalNumber(decimal: rise + inseam).stringValue
        }
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }
}
