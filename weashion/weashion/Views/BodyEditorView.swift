import SwiftUI


struct BodyEditorView: View {
    
    @Binding var bodyData: UserBody
    @Binding var mannequinBase: MannequinBase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var activeSheet: EditorSheet?
    @State private var draftBody: UserBody
    @State private var draftBase: MannequinBase

    init(bodyData: Binding<UserBody>, mannequinBase: Binding<MannequinBase>) {
        _bodyData = bodyData
        _mannequinBase = mannequinBase
        _draftBody = State(initialValue: bodyData.wrappedValue)
        _draftBase = State(initialValue: mannequinBase.wrappedValue)
    }
    
    var body: some View {
        
        Form {

            Section("Base Body") {
                Picker("Body type", selection: $draftBase) {
                    Text("Male").tag(MannequinBase.male)
                    Text("Female").tag(MannequinBase.female)
                }
                .pickerStyle(.segmented)
            }
            
            Section("기본 정보") {
                parameter(.height)
                parameter(.weight)
            }

            Section("신체 치수") {
                parameter(.shoulderWidth)
                parameter(.chest)
                parameter(.waist)
                parameter(.hip)
                parameter(.legLength)
            }

            Section("시각 조절") {
                parameter(.armSize)
                parameter(.legSize)
            }

            Section {
                Button {
                    activeSheet = .comparison
                } label: {
                    Label("옷 치수와 비교", systemImage: "tshirt")
                }
            }
        }
        .navigationTitle("Customize Avatar")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") {
                    bodyData = draftBody
                    mannequinBase = draftBase
                    dismiss()
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .measurement(let measurement):
                BodyMeasurementGuideSheet(
                    measurement: measurement,
                    value: measurementBinding(measurement),
                    locale: locale,
                    isMeasured: draftBody.measuredFields?.contains(measurement) == true
                ) { confirmed in
                    if measurement.isPhysical && confirmed {
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
    
    
    // MARK: - Slider UI
    
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
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(measurement.formatted(draftBody[keyPath: measurement.keyPath], locale: locale)) \(measurement.unit)")
                        .monospacedDigit()
                    Text(sourceLabel(for: measurement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Slider(
                value: measurementBinding(measurement),
                in: measurement.range,
                step: measurement.step
            )
            .accessibilityLabel(measurement.title)
            .accessibilityValue("\(measurement.formatted(draftBody[keyPath: measurement.keyPath], locale: locale)) \(measurement.unit)")
        }
    }

    private func measurementBinding(_ measurement: BodyMeasurement) -> Binding<Double> {
        Binding(
            get: { draftBody[keyPath: measurement.keyPath] },
            set: {
                draftBody[keyPath: measurement.keyPath] = $0
                draftBody.measuredFields?.remove(measurement)
            }
        )
    }

    private func sourceLabel(for measurement: BodyMeasurement) -> String {
        if !measurement.isPhysical { return "시각 조절" }
        if draftBody.measuredFields?.contains(measurement) == true { return "직접 측정" }
        return draftBody[keyPath: measurement.keyPath] == UserBody()[keyPath: measurement.keyPath]
            ? "기본값" : "조절값"
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
