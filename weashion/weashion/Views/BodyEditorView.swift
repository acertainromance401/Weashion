import SwiftUI


struct BodyEditorView: View {
    
    let onSave: (UserBody, MannequinBase, String?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeSheet: EditorSheet?
    @State private var draftBody: UserBody
    @State private var draftBase: MannequinBase
    @State private var profileName: String?
    @State private var saveError: String?
    @State private var expandedPartGroup: PartGroup? = .torso

    init(bodyData: UserBody, mannequinBase: MannequinBase, profileName: String? = nil,
         onSave: @escaping (UserBody, MannequinBase, String?) throws -> Void) {
        self.onSave = onSave
        var draft = bodyData
        draft.synchronizePartScales()
        _draftBody = State(initialValue: draft)
        _draftBase = State(initialValue: mannequinBase)
        _profileName = State(initialValue: profileName)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                WEASHIONSceneView(bodyData: draftBody, mannequinBase: draftBase, weather: .sample,
                                  isBodyPreview: true, sceneHeight: max(70, min(230, geometry.size.height * 0.32)),
                                  isEditorial: true)
                    .padding(.horizontal)
                EditorialFigureCaption(number: "03", text: L("THE BODY FILE / 나의 기준 체형을 편집합니다."))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                editorForm
            }
            .background(Editorial.paper)
        }
        .editorialNavigationTitle(L("내 체형 편집"))
        .tint(Editorial.accent)
        .editorialSans(.body)
        .buttonStyle(EditorialPressStyle())
        .interactiveDismissDisabled()
        .editorialError($saveError)
        .sensoryFeedback(.selection, trigger: draftBase)
        .onChange(of: draftBase) { previous, next in
            draftBody.applyDefaults(from: previous, to: next)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                EditorialToolbarButton("취소") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                EditorialToolbarButton("완료") {
                    do {
                        try onSave(draftBody, draftBase, profileName)
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .accessibilityIdentifier("saveBodyProfile")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .measurement(let measurement):
                BodyMeasurementGuideSheet(
                    measurement: measurement,
                    base: draftBase,
                    value: measurementBinding(measurement),
                    locale: locale,
                    isMeasured: draftBody.measuredFields?.contains(measurement) == true
                ) { confirmed in
                    if measurement.isPhysical && confirmed {
                        let value = draftBody.measurementValue(measurement, base: draftBase)
                        draftBody.setMeasurement(value, for: measurement)
                        draftBody.measuredFields = (draftBody.measuredFields ?? []).union([measurement])
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .comparison:
                ClothingMeasurementComparisonSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var editorForm: some View {
        List {
            if profileName != nil {
                Section("체형 이름") {
                    TextField("체형 이름", text: Binding(
                        get: { profileName ?? "" }, set: { profileName = $0 }
                    ))
                    .accessibilityIdentifier("profileName")
                }
            }
            Section("01 / 기준 마네킹") {
                Picker("기준 체형", selection: $draftBase) {
                    Text("남성").tag(MannequinBase.male)
                    Text("여성").tag(MannequinBase.female)
                }
                .pickerStyle(.segmented)
                Text("기준 체형을 바꿔도 직접 입력한 치수는 유지합니다. 기본값·추정 형태는 달라질 수 있으며 완료 전에는 저장되지 않습니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
            }

            Section("02 / 기본 정보") {
                parameter(.height)
                parameter(.weight)
            }

            Section("03 / 체형") {
                Picker("체형", selection: Binding(
                    get: { draftBody.shapePreset ?? .standard },
                    set: { draftBody.shapePreset = $0 }
                )) {
                    ForEach(BodyShapePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                if draftBase == .female {
                    Picker("골격 실루엣", selection: Binding(
                        get: { draftBody.femaleFramePreset ?? .neutral },
                        set: { draftBody.femaleFramePreset = $0 }
                    )) {
                        ForEach(FemaleBodyFramePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("femaleBodyFramePreset")
                }
                LabeledContent("BMI", value: (draftBody.weight / pow(draftBody.height / 100, 2))
                    .formatted(.number.locale(locale).precision(.fractionLength(1))))
            }

            Section("04 / 신체 치수") {
                parameter(.shoulderWidth)
                parameter(.chest)
                parameter(.waist)
                parameter(.hip)
                parameter(.legLength)
            }

            Section("05 / 시각 조절") {
                parameter(.armSize)
                parameter(.legSize)
                ForEach(BodyAnatomy.ShapeAdjustment.allCases.filter { draftBase == .female || !$0.isFemaleOnly }) { adjustment in
                    shapeParameter(adjustment)
                }
            }

            Section("06 / 세부 부위") {
                ForEach(PartGroup.allCases) { group in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedPartGroup == group },
                        set: { expanded in
                            if expanded { expandedPartGroup = group }
                            else if expandedPartGroup == group { expandedPartGroup = nil }
                        }
                    )) {
                        ForEach(group.parts) { part in
                            partParameter(part)
                        }
                    } label: {
                        Text(group.title)
                    }
                    .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: expandedPartGroup == group)
                }
                Button("세부 조절 초기화", systemImage: "arrow.counterclockwise") {
                    draftBody.partScales = nil
                }
                .disabled(draftBody.partScales == nil)
            }

            Section {
                Button {
                    activeSheet = .comparison
                } label: {
                    Label("옷 치수와 비교", systemImage: "tshirt")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }
    
    
    // MARK: - Slider UI

    private func shapeParameter(_ adjustment: BodyAnatomy.ShapeAdjustment) -> some View {
        let percentage = Int((draftBody.shapeScale(for: adjustment) * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(adjustment.title)
                Spacer()
                Text("\(percentage)%")
                    .monospacedDigit()
            }
            Slider(value: Binding(
                get: { draftBody.shapeScale(for: adjustment) },
                set: { draftBody.setShapeScale($0, for: adjustment) }
            ), in: adjustment.adjustmentRange, step: 0.01)
            .accessibilityLabel(adjustment.title)
            .accessibilityValue("\(percentage)%")
        }
        .padding(.vertical, 6)
    }

    private func partParameter(_ part: BodyAnatomy.Part) -> some View {
        let title = partTitle(part)
        let percentage = Int((draftBody.partScale(for: part) * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text("\(percentage)%")
                    .monospacedDigit()
            }
            Slider(value: Binding(
                get: { draftBody.partScale(for: part) },
                set: { draftBody.setPartScale($0, for: part, mirrored: true) }
            ), in: part.adjustmentRange, step: 0.01)
            .accessibilityLabel(title)
            .accessibilityValue("\(percentage)%")
        }
        .padding(.vertical, 6)
    }

    private func partTitle(_ part: BodyAnatomy.Part) -> String {
        let name: String
        switch part {
        case .head: name = L("머리 크기")
        case .neck: name = L("목 굵기")
        case .chest: name = L("흉곽")
        case .abdomen: name = L("복부")
        case .waist: name = L("허리")
        case .pelvis: name = L("골반")
        case .leftChestVolume, .rightChestVolume: name = L("가슴 볼륨")
        case .leftFlank, .rightFlank: name = L("옆구리")
        case .upperBack: name = L("등 상부")
        case .lowerBack: name = L("등 하부")
        case .leftButtock, .rightButtock: name = L("엉덩이")
        case .leftShoulder, .rightShoulder: name = L("어깨 두께")
        case .leftUpperArm, .rightUpperArm: name = L("위팔 굵기")
        case .leftElbow, .rightElbow: name = L("팔꿈치 굵기")
        case .leftForearm, .rightForearm: name = L("전완 굵기")
        case .leftWrist, .rightWrist: name = L("손목 굵기")
        case .leftHand, .rightHand: name = L("손 두께")
        case .leftThigh, .rightThigh: name = L("허벅지 굵기")
        case .leftKnee, .rightKnee: name = L("무릎 굵기")
        case .leftCalf, .rightCalf: name = L("종아리 굵기")
        case .leftAnkle, .rightAnkle: name = L("발목 굵기")
        case .leftFoot, .rightFoot: name = L("발 크기")
        }
        return name
    }

    private enum PartGroup: String, CaseIterable, Identifiable {
        case head, torso, arms, legs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .head: L("머리 · 목")
            case .torso: L("몸통")
            case .arms: L("팔 · 손")
            case .legs: L("다리 · 발")
            }
        }

        var parts: [BodyAnatomy.Part] {
            switch self {
            case .head: [.head, .neck]
            case .torso: [.chest, .leftChestVolume, .abdomen, .waist, .leftFlank,
                         .upperBack, .lowerBack, .pelvis, .leftButtock]
            case .arms: [.leftShoulder, .leftUpperArm, .leftElbow, .leftForearm, .leftWrist, .leftHand]
            case .legs: [.leftThigh, .leftKnee, .leftCalf, .leftAnkle, .leftFoot]
            }
        }
    }
    
    private func parameter(_ measurement: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(measurement.title)
                Button {
                    activeSheet = .measurement(measurement)
                } label: {
                    Image(systemName: "info.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(measurement.title) 기준과 입력")
                .help("\(measurement.title) 기준과 입력")
                     if [.chest, .waist, .hip].contains(measurement),
                   !draftBody.usesEstimatedMeasurement(measurement, base: draftBase) {
                    Button {
                        draftBody.restoreEstimate(for: measurement, base: draftBase)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(measurement.title) 체형 추정값으로 복원")
                    .help("체형 추정값으로 복원")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(measurement.formatted(draftBody.measurementValue(measurement, base: draftBase), locale: locale)) \(measurement.unit)")
                        .monospacedDigit()
                    Text(sourceLabel(for: measurement))
                        .editorialSans(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Slider(
                value: measurementBinding(measurement),
                in: measurement.range(for: draftBase),
                step: measurement.step
            )
            .accessibilityLabel(measurement.title)
            .accessibilityValue("\(measurement.formatted(draftBody.measurementValue(measurement, base: draftBase), locale: locale)) \(measurement.unit)")
        }
    }

    private func measurementBinding(_ measurement: BodyMeasurement) -> Binding<Double> {
        Binding(
            get: { draftBody.measurementValue(measurement, base: draftBase) },
            set: { draftBody.setMeasurement($0, for: measurement) }
        )
    }

    private func sourceLabel(for measurement: BodyMeasurement) -> String {
        if !measurement.isPhysical { return L("시각 조절") }
        if draftBody.measuredFields?.contains(measurement) == true { return L("직접 측정") }
        if draftBody.usesEstimatedMeasurement(measurement, base: draftBase) { return L("체형 추정") }
        if draftBody.adjustedFields?.contains(measurement) == true { return L("조절값") }
        return draftBody[keyPath: measurement.keyPath] == UserBody.defaults(for: draftBase)[keyPath: measurement.keyPath]
            ? L("기본값") : L("조절값")
    }

    private enum EditorSheet: Identifiable {
        case measurement(BodyMeasurement)
        case comparison

        var id: String {
            switch self {
            case .measurement(let measurement): return measurement.rawValue
            case .comparison: return "comparison"
            }
        }
    }
}
