import SwiftUI

struct BodySetupView: View {
    @ObservedObject var room: FittingRoom
    let isInitialSetup: Bool
    var onFinish: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: BodySetupDraft
    @State private var activateOnSave = true
    @State private var showsDetails = false
    @State private var showsCustomization = false
    @State private var errorMessage: String?
    @State private var lastValidBody: UserBody?
    @FocusState private var focusedField: BodyMeasurement?
    @Namespace private var progress

    init(room: FittingRoom, isInitialSetup: Bool, draft: BodySetupDraft? = nil,
         onFinish: @escaping () -> Void = {}) {
        self.room = room
        self.isInitialSetup = isInitialSetup
        self.onFinish = onFinish
        _draft = State(initialValue: draft ?? (isInitialSetup ? room.library.setupDraft : nil) ?? BodySetupDraft())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = EditorialLayout.usesColumns(width: geometry.size.width,
                                                       accessibility: dynamicTypeSize.isAccessibilitySize)
                let layout = wide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 36))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline) {
                            EditorialEyebrow(text: "A PERSONAL BEGINNING")
                            Spacer()
                            Text("\(draft.step + 1) / 3")
                                .editorialSans(.subheadline).monospacedDigit()
                                .foregroundStyle(Editorial.muted)
                                .contentTransition(.numericText())
                                .accessibilityLabel("3단계 중 \(draft.step + 1)단계")
                        }
                        HStack(spacing: 12) {
                            ForEach(0..<3) { step in
                                VStack(alignment: .leading, spacing: 9) {
                                    Text([L("기준 선택"), L("기본 치수"), L("마네킹 확인")][step])
                                        .editorialSans(.caption)
                                        .foregroundStyle(step == draft.step ? Editorial.accent : Editorial.muted)
                                    Rectangle().fill(Editorial.rule).frame(height: 2)
                                        .overlay {
                                            if step == draft.step {
                                                Rectangle().fill(Editorial.accent)
                                                    .matchedGeometryEffect(id: "setup-step", in: progress)
                                            }
                                        }
                                }
                            }
                        }
                        .accessibilityHidden(true)
                        EditorialTitle(text: title, pointSize: wide ? 44 : 34, style: .statement)
                            .id(draft.step)
                        // The first decision (base model) stays above the fold on narrow screens.
                        if !wide && draft.base == nil {
                            stepFields
                                .frame(maxWidth: .infinity, alignment: .leading)
                            preview(height: 250)
                                .frame(maxWidth: .infinity)
                        } else {
                            layout {
                                preview(height: wide ? 460 : draft.step == 2 ? 350 : 250)
                                    .frame(maxWidth: .infinity)
                                stepFields
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(wide ? 36 : 24)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { controls }
                .background(Editorial.paper)
            }
            .editorialNavigationTitle(isInitialSetup ? "WEASHION" : L("새 체형 만들기"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if draft.step > 0 {
                        Button("이전") {
                            focusedField = nil
                            draft.step -= 1
                            persistDraft()
                        }
                    } else if !isInitialSetup {
                        EditorialToolbarButton("취소") { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") { focusedField = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isInitialSetup && draft.step > 0 {
                        EditorialToolbarButton("취소") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showsCustomization) {
                if let base = draft.base {
                    NavigationStack {
                        BodyEditorView(bodyData: draft.previewBody, mannequinBase: base) { body, base, _ in
                            draft.body = body
                            draft.base = base
                            draft.height = body.height
                            draft.weight = body.weight
                            persistDraft()
                        }
                    }
                    .presentationDetents([.large])
                }
            }
        }
        .tint(Editorial.accent)
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .buttonStyle(EditorialPressStyle())
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .editorialError($errorMessage)
        .sensoryFeedback(.selection, trigger: draft.base)
        .sensoryFeedback(.selection, trigger: draft.step)
        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: draft.step)
        .onChange(of: draft.height) { _, _ in persistDraft() }
        .onChange(of: draft.weight) { _, _ in persistDraft() }
        .onChange(of: draft.name) { _, _ in persistDraft() }
        .onChange(of: BodyPreviewRenderer.Request(body: draft.previewBody, base: draft.base ?? .male), initial: true) { _, _ in
            if hasValidPreview { lastValidBody = draft.previewBody }
        }
    }

    private var hasValidPreview: Bool {
        BodyProfile(id: "setup-preview", name: L("미리보기"), body: draft.previewBody,
                    base: draft.base ?? .male).validationMessage == nil
    }

    private var title: String {
        switch draft.step {
        case 0: L("나의 기준부터.")
        case 1: L("나의 비율을\n알려주세요.")
        default: L("이제, 나의 마네킹.")
        }
    }

    @ViewBuilder
    private func preview(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let base = draft.base {
                WEASHIONSceneView(bodyData: hasValidPreview ? draft.previewBody : lastValidBody ?? .defaults(for: base),
                                  mannequinBase: base, weather: .sample,
                                  isBodyPreview: true, sceneHeight: height, isEditorial: true)
                    .overlay(Rectangle().strokeBorder(Editorial.rule, lineWidth: 0.5))
                EditorialFigureCaption(number: "01", text: !hasValidPreview
                    ? L("치수 범위 확인 필요 · 직전 유효 체형 또는 기준 모델을 표시합니다.")
                    : draft.hasValidBasics
                    ? L("기본 정보 기반 근사 마네킹 · 회전하며 확인하세요.")
                    : L("기준 모델 미리보기 · 유효한 입력값만 반영합니다."))
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    EditorialEyebrow(text: "THE ORIGINAL IS YOU", color: Editorial.paper.opacity(0.7))
                    EditorialTitle(text: "You,\nfirst.", pointSize: 64, color: Editorial.paper)
                    EditorialRule(color: Editorial.paper)
                    Text("옷을 보기 전에,\n나를 위한 한 마네킹부터.")
                        .font(Editorial.hangul(16, relativeTo: .subheadline)).lineSpacing(5)
                }
                .foregroundStyle(Editorial.paper)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                .background(Editorial.ink)
                .overlay(alignment: .topTrailing) {
                    EditorialRunningHead(text: "A PERSONAL BEGINNING", color: Editorial.paper.opacity(0.45))
                        .padding(.trailing, 6)
                        .padding(.top, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var stepFields: some View {
        switch draft.step {
        case 0:
            VStack(alignment: .leading, spacing: 20) {
                Text("개인 마네킹의 기준 모델을 선택해 주세요.").editorialSans(.headline, weight: .medium)
                let choices = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 12))
                    : AnyLayout(HStackLayout(spacing: 12))
                choices {
                    baseChoice(L("남성"), base: .male)
                    baseChoice(L("여성"), base: .female)
                }
                Text("이후 내 체형의 커스터마이징에서 변경할 수 있어요. 기본 모델을 선택한 다음 직접 입력한 치수로 조절합니다.")
                    .editorialSans(.subheadline).foregroundStyle(Editorial.muted)
            }
        case 1:
            VStack(alignment: .leading, spacing: 24) {
                basicField(.height, value: $draft.height)
                basicField(.weight, value: $draft.weight)
                Text("키와 몸무게로 기본 형태를 조절합니다. 사진 스캔이나 실제 체형 복원이 아니며, 다음 단계에서 상세 치수를 추가할 수 있어요.")
                    .editorialSans(.subheadline).foregroundStyle(Editorial.muted)
            }
        default:
            VStack(alignment: .leading, spacing: 22) {
                EditorialTextField(title: L("체형 이름"), text: $draft.name,
                                   invalid: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("setup-profile-name")
                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("체형 이름을 입력해 주세요.").editorialSans(.caption).foregroundStyle(Editorial.error)
                }
                Text("\(draft.previewBody.height, specifier: "%.1f") cm / \(draft.previewBody.weight, specifier: "%.1f") kg")
                    .font(Editorial.serif(26)).monospacedDigit()
                DisclosureGroup(isExpanded: $showsDetails) {
                    VStack(spacing: 18) {
                        ForEach([BodyMeasurement.shoulderWidth, .chest, .waist, .hip, .legLength]) { measurement in
                            detailField(measurement)
                        }
                    }
                    .padding(.top, 16)
                } label: {
                    Text("상세 치수 조절 · 선택").frame(minHeight: 44)
                }
                .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: showsDetails)
                Button("세부 체형 커스터마이징") { showsCustomization = true }
                    .frame(minHeight: 44)
                    .underline()
                Text("직접 입력하지 않은 치수는 기본값 또는 추정값입니다. 상세 치수는 나중에도 수정할 수 있어요.")
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
                if !isInitialSetup {
                    Toggle("저장 후 이 체형 사용", isOn: $activateOnSave)
                    Text("끄면 기존 활성 체형을 유지하고 새 체형만 보관합니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
            }
        }
    }

    private func baseChoice(_ title: String, base: MannequinBase) -> some View {
        let selected = draft.base == base
        return Button {
            draft.selectBase(base)
            persistDraft()
        } label: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(base == .male ? "01" : "02").font(Editorial.serif(16, italic: true))
                        .foregroundStyle(selected ? Editorial.accent : Editorial.muted)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .editorialSans(.subheadline)
                        .foregroundStyle(selected ? Editorial.accent : Editorial.muted)
                }
                Text(title).editorialSans(.title, weight: .semibold)
                Text("기준 모델").editorialSans(.caption)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Editorial.ink)
            .background(selected ? Editorial.accent.opacity(0.07) : Editorial.stock.opacity(0.4))
            .overlay(Rectangle().strokeBorder(selected ? Editorial.accent : Editorial.rule,
                                             lineWidth: selected ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: draft.base)
        .accessibilityIdentifier("setup-base-\(base.rawValue)")
        .accessibilityAddTraits(draft.base == base ? .isSelected : [])
    }

    private func basicField(_ measurement: BodyMeasurement, value: Binding<Double?>) -> some View {
        let range = measurement.range(for: draft.base ?? .male)
        return VStack(alignment: .leading, spacing: 8) {
            Text(measurement.title).editorialSans(.headline)
            HStack {
                TextField(measurement.title, value: value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: measurement)
                    .editorialSans(.title2).monospacedDigit()
                    .editorialInput(focused: focusedField == measurement,
                                    invalid: value.wrappedValue.map { !range.contains($0) } ?? false)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { focusedField = measurement })
                    .accessibilityIdentifier("setup-\(measurement.rawValue)")
                Text(measurement.unit).editorialSans(.body)
            }
            Text("\(range.lowerBound, specifier: "%.0f")–\(range.upperBound, specifier: "%.0f") \(measurement.unit)")
                .editorialSans(.caption).foregroundStyle(Editorial.muted)
            if let number = value.wrappedValue, !range.contains(number) {
                Text("입력 가능한 범위를 확인해 주세요.").editorialSans(.caption).foregroundStyle(Editorial.error)
            }
        }
    }

    private func detailField(_ measurement: BodyMeasurement) -> some View {
        let range = measurement.range(for: draft.base ?? .male)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(measurement.title)
                Spacer()
                Text(measurement.unit).foregroundStyle(Editorial.muted)
            }
            TextField(measurement.title, value: Binding(
                get: { draft.previewBody.measurementValue(measurement, base: draft.base ?? .male) },
                set: { value in
                    draft.body.setMeasurement(value, for: measurement)
                    draft.body.measuredFields = (draft.body.measuredFields ?? []).union([measurement])
                    persistDraft()
                }
            ), format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: measurement)
            .editorialInput(focused: focusedField == measurement,
                            invalid: !range.contains(draft.previewBody[keyPath: measurement.keyPath]))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { focusedField = measurement })
            Text(draft.body.measuredFields?.contains(measurement) == true ? L("직접 입력") : L("기본값 / 추정값"))
                .editorialSans(.caption).foregroundStyle(Editorial.muted)
            if !range.contains(draft.previewBody[keyPath: measurement.keyPath]) {
                Text("\(range.lowerBound, specifier: "%.0f")–\(range.upperBound, specifier: "%.0f") \(measurement.unit) 범위를 확인해 주세요.")
                    .editorialSans(.caption).foregroundStyle(Editorial.error)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                focusedField = nil
                if draft.step < 2 {
                    draft.step += 1
                    persistDraft()
                } else {
                    do {
                        try room.addProfile(draft.makeProfile(), activate: isInitialSetup || activateOnSave)
                        onFinish()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    Text(draft.step == 0 ? L("다음") : draft.step == 1 ? L("마네킹 확인하기") :
                            isInitialSetup ? L("이 마네킹으로 시작하기") : activateOnSave ? L("저장하고 사용하기") : L("체형 저장"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(EditorialButtonStyle(filled: true))
            .disabled(draft.base == nil || draft.step > 0 && !draft.hasValidBasics)
            .accessibilityIdentifier("setupNext")
        }
        .padding(20)
        .background(Editorial.paper)
    }

    private func persistDraft() {
        guard isInitialSetup else { return }
        do {
            try room.saveSetupDraft(draft)
        } catch {
            errorMessage = L("초기 설정을 임시 저장하지 못했습니다. 입력은 이 화면에 유지됩니다.\n\(error.localizedDescription)")
        }
    }
}
