import SwiftUI

extension BodyMeasurement {
    var guidance: (location: String, posture: String, caution: String, clothing: String) {
        switch self {
        case .height:
            return (
                "평평한 바닥부터 머리 꼭대기까지 수직으로 측정합니다. 책을 머리 위에 수평으로 대고 벽에 높이를 표시하면 편합니다.",
                "맨발로 서서 시선은 정면을 향합니다. 발뒤꿈치를 바닥에 붙이고 등을 자연스럽게 폅니다.",
                "머리카락의 부피와 신발 높이는 제외합니다. 발끝으로 서거나 고개를 젖히지 않습니다.",
                "상의·바지의 전체 길이를 판단하는 보조 기준입니다. 같은 키라도 상체와 다리 비율은 다릅니다."
            )
        case .weight:
            return (
                "체중계를 단단하고 평평한 바닥에 놓고 표시되는 체중을 확인합니다.",
                "가벼운 옷차림으로 체중계 중앙에 서서 움직이지 않습니다.",
                "가능하면 비슷한 시간과 옷차림으로 측정합니다. 체중만으로 가슴·허리·팔다리 둘레를 알 수는 없습니다.",
                "전반적인 체형의 보조 정보이며 의류 사이즈와 직접 대응하는 실측값은 아닙니다."
            )
        case .shoulderWidth:
            return (
                "양쪽 어깨 바깥쪽의 뼈 끝 지점을 찾고, 뒤에서 두 지점 사이의 수평 너비를 측정합니다.",
                "팔을 자연스럽게 내리고 어깨를 편안하게 둡니다. 다른 사람의 도움을 받는 것이 좋습니다.",
                "줄자를 등 굴곡에 눌러 감지 않습니다. 어깨를 으쓱하거나 가슴을 과하게 펴지 않습니다.",
                "상의 어깨선 위치와 관련됩니다. 드롭숄더·래글런 의류의 어깨 치수는 신체 어깨너비와 직접 비교하기 어렵습니다."
            )
        case .chest:
            return (
                "가슴의 가장 돌출된 부분을 지나 등까지 줄자를 수평으로 한 바퀴 둘러 측정합니다.",
                "얇은 옷차림으로 팔을 편하게 내립니다. 평소처럼 호흡하고 숨을 참거나 가슴을 부풀리지 않습니다.",
                "줄자는 몸에 가볍게 밀착하되 살을 누르지 않도록 합니다. 등 쪽 줄자가 처지지 않았는지 확인합니다.",
                "상의 가슴단면과 착용 여유에 관련됩니다. 옷의 가슴단면을 두 배 한 값에는 여유분이 포함될 수 있습니다."
            )
        case .waist:
            return (
                "맨 아래 갈비뼈와 골반뼈 윗부분 사이의 중간 높이를 줄자로 수평으로 한 바퀴 둘러 측정합니다.",
                "배에 힘을 주지 않고 편안하게 선 상태에서 자연스럽게 숨을 내쉰 뒤 측정합니다.",
                "배꼽이나 바지 허리선이 항상 이 위치와 같지는 않습니다. 측정 위치를 일정하게 유지합니다.",
                "상의 허리 부분과 하의 허리 치수의 참고 기준입니다. 바지가 실제로 걸리는 높이의 둘레는 따로 다를 수 있습니다."
            )
        case .hip:
            return (
                "엉덩이가 가장 돌출된 높이를 찾아 줄자를 수평으로 한 바퀴 둘러 측정합니다.",
                "두 발을 모으고 양발에 체중을 고르게 싣습니다. 옆모습을 보거나 다른 사람의 도움을 받아 높이를 확인합니다.",
                "골반뼈의 너비가 아니라 엉덩이를 포함한 가장 큰 둘레입니다. 주머니 속 물건과 두꺼운 옷은 제외합니다.",
                "바지·치마의 엉덩이 단면과 움직일 때 필요한 여유에 관련됩니다."
            )
        case .legLength:
            return (
                "다리가 갈라지는 안쪽 기준점부터 바닥까지 수직 거리를 측정합니다. 얇은 책을 다리 사이에 수평으로 대고 위쪽 모서리를 기준점으로 삼을 수 있습니다.",
                "맨발로 똑바로 서고 책을 몸에 가볍게 댑니다. 다른 사람이 책의 위쪽 모서리부터 바닥까지 측정하면 편합니다.",
                "허리부터 바닥까지의 길이나 바지 바깥쪽 총장과 다릅니다. 책을 지나치게 밀어 올리지 않습니다.",
                "바지 인심과 관련됩니다. 바지 인심은 가랑이 봉제선부터 밑단까지이므로 원하는 밑단 위치와 신발도 고려합니다."
            )
        case .armSize:
            return (
                "팔 전체 굵기의 단위 없는 배율입니다. 1.00배가 기준형이며 cm 단위의 실측 둘레가 아닙니다.",
                "팔을 자연스럽게 내린 상태의 전체 실루엣을 기준으로 합니다.",
                "위팔둘레나 옷의 소매단면 수치를 배율 값으로 입력하지 않습니다.",
                "소매통의 외형을 이해하는 보조 기준입니다. 정확한 비교에는 위팔둘레와 의류의 착용 여유가 필요합니다."
            )
        case .legSize:
            return (
                "다리 전체 굵기의 단위 없는 배율입니다. 1.00배가 기준형이며 cm 단위의 실측 둘레가 아닙니다.",
                "양발에 체중을 고르게 싣고 선 상태의 전체 실루엣을 기준으로 합니다.",
                "허벅지와 종아리 굵기는 서로 다릅니다. 하나의 배율을 특정 부위의 실측 둘레로 해석하지 않습니다.",
                "바지통의 외형을 이해하는 보조 기준입니다. 정확한 비교에는 허벅지·종아리 둘레를 각각 측정해야 합니다."
            )
        }
    }
}

struct BodyMeasurementGuideSheet: View {
    let measurement: BodyMeasurement
    let locale: Locale
    let onApply: (Bool) -> Void
    @Binding private var value: Double
    @State private var input: String
    @State private var confirmedMeasurement: Bool
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        measurement: BodyMeasurement,
        value: Binding<Double>,
        locale: Locale,
        isMeasured: Bool,
        onApply: @escaping (Bool) -> Void
    ) {
        self.measurement = measurement
        self.locale = locale
        self.onApply = onApply
        self._value = value
        self._input = State(initialValue: measurement.formatted(value.wrappedValue, locale: locale))
        self._confirmedMeasurement = State(initialValue: isMeasured)
    }

    private var validValue: Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        formatter.usesGroupingSeparator = false
        let separator = formatter.decimalSeparator ?? "."
        guard !text.isEmpty,
              text.components(separatedBy: separator).count <= 2,
              text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) || String($0) == separator }),
              let number = formatter.number(from: text)?.doubleValue,
              number.isFinite,
              measurement.range.contains(number) else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BodyMeasurementDiagram(measurement: measurement)
                        .frame(maxWidth: .infinity)
                }
                Section("\(measurement.unit) 입력") {
                    HStack(alignment: .firstTextBaseline) {
                        TextField(measurement.title, text: $input)
                            .keyboardType(.decimalPad)
                            .focused($inputFocused)
                            .font(.title2.monospacedDigit())
                            .accessibilityLabel(measurement.title)
                        Text(measurement.unit)
                            .foregroundStyle(.secondary)
                    }
                    Text("입력 범위: \(measurement.formatted(measurement.range.lowerBound, locale: locale)) ~ \(measurement.formatted(measurement.range.upperBound, locale: locale)) \(measurement.unit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if validValue == nil && !input.isEmpty {
                        Label("범위 안의 숫자를 입력해 주세요.", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if measurement.isPhysical {
                        Toggle("직접 측정한 값", isOn: $confirmedMeasurement)
                    }
                }
                Section(measurement.isPhysical ? "측정 위치" : "조절 기준") {
                    Text(measurement.guidance.location)
                }
                Section("자세") {
                    Text(measurement.guidance.posture)
                }
                Section("주의점") {
                    Text(measurement.guidance.caution)
                }
                Section("옷 치수와의 관계") {
                    Text(measurement.guidance.clothing)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(measurement.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        guard let validValue else { return }
                        value = (validValue / measurement.step).rounded() * measurement.step
                        onApply(confirmedMeasurement)
                        dismiss()
                    }
                    .disabled(validValue == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        inputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("키보드 닫기")
                }
            }
        }
    }
}

private struct BodyMeasurementDiagram: View {
    let measurement: BodyMeasurement

    private var circumference: (height: CGFloat, halfWidth: CGFloat)? {
        switch measurement {
        case .chest: return (0.30, 0.16)
        case .waist: return (0.405, 0.115)
        case .hip: return (0.51, 0.17)
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if measurement == .weight {
                Image(systemName: "scalemass")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                    .frame(height: 120)
                Text("평평한 바닥 · 가벼운 옷차림")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    panel(sideView: false)
                    if circumference != nil {
                        panel(sideView: true)
                    }
                }
                Text(measurement.isPhysical ? "표시선: 측정 위치" : "표시 부위: 굵기 조절")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measurement.title) 위치 그림. \(measurement.guidance.location)")
    }

    private func panel(sideView: Bool) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let transform = CGAffineTransform(scaleX: size.width, y: size.height)
                let outline = silhouette(sideView: sideView).applying(transform)
                context.fill(outline, with: .color(.secondary.opacity(0.13)))
                context.stroke(outline, with: .color(.secondary.opacity(0.65)), lineWidth: 1.5)
                let head = Path(ellipseIn: CGRect(x: sideView ? 0.44 : 0.42, y: 0.02, width: 0.16, height: 0.13))
                    .applying(transform)
                context.fill(head, with: .color(.secondary.opacity(0.13)))
                context.stroke(head, with: .color(.secondary.opacity(0.65)), lineWidth: 1.5)

                var tape = Path()
                var hidden = Path()
                if let circumference {
                    let center: CGFloat = sideView ? 0.525 : 0.5
                    let halfWidth = sideView ? CGFloat(0.10) : circumference.halfWidth
                    let level = circumference.height
                    tape.move(to: CGPoint(x: center - halfWidth, y: level))
                    tape.addCurve(
                        to: CGPoint(x: center + halfWidth, y: level),
                        control1: CGPoint(x: center - halfWidth, y: level + 0.03),
                        control2: CGPoint(x: center + halfWidth, y: level + 0.03)
                    )
                    hidden.move(to: CGPoint(x: center - halfWidth, y: level))
                    hidden.addCurve(
                        to: CGPoint(x: center + halfWidth, y: level),
                        control1: CGPoint(x: center - halfWidth, y: level - 0.025),
                        control2: CGPoint(x: center + halfWidth, y: level - 0.025)
                    )
                } else {
                    switch measurement {
                    case .height:
                        tape = dimension(from: CGPoint(x: 0.19, y: 0.02), to: CGPoint(x: 0.19, y: 0.96))
                        hidden.move(to: CGPoint(x: 0.19, y: 0.02))
                        hidden.addLine(to: CGPoint(x: 0.5, y: 0.02))
                        hidden.move(to: CGPoint(x: 0.19, y: 0.96))
                        hidden.addLine(to: CGPoint(x: 0.66, y: 0.96))
                    case .shoulderWidth:
                        tape = dimension(from: CGPoint(x: 0.31, y: 0.205), to: CGPoint(x: 0.69, y: 0.205))
                    case .legLength:
                        tape = dimension(from: CGPoint(x: 0.5, y: 0.555), to: CGPoint(x: 0.5, y: 0.96))
                    case .armSize:
                        for side: CGFloat in [-1, 1] {
                            tape.move(to: CGPoint(x: 0.5 + side * 0.20, y: 0.23))
                            tape.addQuadCurve(
                                to: CGPoint(x: 0.5 + side * 0.295, y: 0.51),
                                control: CGPoint(x: 0.5 + side * 0.27, y: 0.38)
                            )
                        }
                    case .legSize:
                        for side: CGFloat in [-1, 1] {
                            tape.move(to: CGPoint(x: 0.5 + side * 0.10, y: 0.56))
                            tape.addLine(to: CGPoint(x: 0.5 + side * 0.10, y: 0.91))
                        }
                    default: break
                    }
                }
                context.stroke(hidden.applying(transform), with: .color(.accentColor.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                context.stroke(tape.applying(transform), with: .color(.accentColor), style: StrokeStyle(lineWidth: measurement.isPhysical ? 3 : 6, lineCap: .round))
            }
            .frame(width: 110, height: 210)
            Text(sideView ? "옆모습" : measurement == .shoulderWidth ? "뒷모습" : "앞모습")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dimension(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let vertical = start.x == end.x
        for point in [start, end] {
            path.move(to: CGPoint(x: point.x - (vertical ? 0.035 : 0), y: point.y - (vertical ? 0 : 0.015)))
            path.addLine(to: CGPoint(x: point.x + (vertical ? 0.035 : 0), y: point.y + (vertical ? 0 : 0.015)))
        }
        return path
    }

    private func silhouette(sideView: Bool) -> Path {
        var path = Path()
        if sideView {
            path.move(to: CGPoint(x: 0.46, y: 0.155))
            path.addCurve(to: CGPoint(x: 0.43, y: 0.40), control1: CGPoint(x: 0.38, y: 0.22), control2: CGPoint(x: 0.43, y: 0.34))
            path.addCurve(to: CGPoint(x: 0.42, y: 0.555), control1: CGPoint(x: 0.39, y: 0.46), control2: CGPoint(x: 0.38, y: 0.51))
            path.addCurve(to: CGPoint(x: 0.46, y: 0.91), control1: CGPoint(x: 0.48, y: 0.68), control2: CGPoint(x: 0.40, y: 0.78))
            path.addLine(to: CGPoint(x: 0.45, y: 0.96))
            path.addLine(to: CGPoint(x: 0.67, y: 0.96))
            path.addQuadCurve(to: CGPoint(x: 0.54, y: 0.91), control: CGPoint(x: 0.69, y: 0.93))
            path.addCurve(to: CGPoint(x: 0.60, y: 0.55), control1: CGPoint(x: 0.54, y: 0.78), control2: CGPoint(x: 0.60, y: 0.67))
            path.addCurve(to: CGPoint(x: 0.61, y: 0.39), control1: CGPoint(x: 0.64, y: 0.48), control2: CGPoint(x: 0.64, y: 0.44))
            path.addCurve(to: CGPoint(x: 0.59, y: 0.21), control1: CGPoint(x: 0.63, y: 0.34), control2: CGPoint(x: 0.68, y: 0.27))
            path.addLine(to: CGPoint(x: 0.57, y: 0.155))
        } else {
            path.move(to: CGPoint(x: 0.45, y: 0.155))
            path.addLine(to: CGPoint(x: 0.44, y: 0.18))
            path.addQuadCurve(to: CGPoint(x: 0.29, y: 0.22), control: CGPoint(x: 0.31, y: 0.19))
            path.addCurve(to: CGPoint(x: 0.17, y: 0.55), control1: CGPoint(x: 0.25, y: 0.29), control2: CGPoint(x: 0.20, y: 0.42))
            path.addQuadCurve(to: CGPoint(x: 0.22, y: 0.565), control: CGPoint(x: 0.16, y: 0.60))
            path.addLine(to: CGPoint(x: 0.34, y: 0.32))
            path.addCurve(to: CGPoint(x: 0.38, y: 0.43), control1: CGPoint(x: 0.36, y: 0.36), control2: CGPoint(x: 0.40, y: 0.39))
            path.addCurve(to: CGPoint(x: 0.34, y: 0.55), control1: CGPoint(x: 0.34, y: 0.48), control2: CGPoint(x: 0.32, y: 0.51))
            path.addCurve(to: CGPoint(x: 0.36, y: 0.92), control1: CGPoint(x: 0.35, y: 0.69), control2: CGPoint(x: 0.32, y: 0.77))
            path.addLine(to: CGPoint(x: 0.30, y: 0.96))
            path.addLine(to: CGPoint(x: 0.44, y: 0.96))
            path.addQuadCurve(to: CGPoint(x: 0.50, y: 0.555), control: CGPoint(x: 0.46, y: 0.70))
            path.addQuadCurve(to: CGPoint(x: 0.56, y: 0.96), control: CGPoint(x: 0.54, y: 0.70))
            path.addLine(to: CGPoint(x: 0.70, y: 0.96))
            path.addLine(to: CGPoint(x: 0.64, y: 0.92))
            path.addCurve(to: CGPoint(x: 0.66, y: 0.55), control1: CGPoint(x: 0.68, y: 0.77), control2: CGPoint(x: 0.65, y: 0.69))
            path.addCurve(to: CGPoint(x: 0.62, y: 0.43), control1: CGPoint(x: 0.68, y: 0.51), control2: CGPoint(x: 0.66, y: 0.48))
            path.addCurve(to: CGPoint(x: 0.66, y: 0.32), control1: CGPoint(x: 0.60, y: 0.39), control2: CGPoint(x: 0.64, y: 0.36))
            path.addLine(to: CGPoint(x: 0.78, y: 0.565))
            path.addQuadCurve(to: CGPoint(x: 0.83, y: 0.55), control: CGPoint(x: 0.84, y: 0.60))
            path.addCurve(to: CGPoint(x: 0.71, y: 0.22), control1: CGPoint(x: 0.80, y: 0.42), control2: CGPoint(x: 0.75, y: 0.29))
            path.addQuadCurve(to: CGPoint(x: 0.56, y: 0.18), control: CGPoint(x: 0.69, y: 0.19))
            path.addLine(to: CGPoint(x: 0.55, y: 0.155))
        }
        path.closeSubpath()
        return path
    }
}

struct ClothingMeasurementComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category = ClothingCategory.tops

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("의류 종류", selection: $category) {
                        ForEach(ClothingCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("옷 실측 / 신체 기준") {
                    ForEach(category.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 16) {
                                Text(row.garment)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(row.note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                    }
                }
                Section("비교할 때") {
                    Text("의류 단면은 펼쳐 놓은 옷의 너비이고, 신체 둘레는 몸을 한 바퀴 잰 길이입니다. 둘은 같은 값이 아닙니다.")
                    Text("단면의 두 배도 둘레의 대략적인 참고값입니다. 다트·주름·입체 패턴·착용 여유·소재의 신축성에 따라 달라집니다.")
                    Text("브랜드마다 측정 위치와 방법이 다릅니다. 상품의 실측 기준과 원하는 핏을 함께 확인하세요.")
                }
            }
            .navigationTitle("옷 치수와 비교")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

private enum ClothingCategory: String, CaseIterable, Identifiable {
    case tops = "상의"
    case bottoms = "하의"

    var id: String { rawValue }

    var rows: [ClothingMeasurementRow] {
        switch self {
        case .tops:
            return [
                .init(garment: "어깨너비", body: "어깨 폭·기울기", note: "봉제선 위치가 기준입니다. 드롭숄더·래글런은 신체 어깨너비와 일대일 대응하지 않습니다."),
                .init(garment: "가슴단면", body: "가슴둘레·몸통 두께", note: "신체 둘레 외에도 움직일 여유와 앞뒤 볼륨이 필요합니다."),
                .init(garment: "소매길이", body: "팔 길이·어깨선 위치", note: "옷의 소매 시작점과 신체의 어깨 기준점이 같은지 확인합니다."),
                .init(garment: "소매통·암홀", body: "위팔둘레·어깨·상체 두께", note: "소매단면, 암홀 깊이, 암홀 둘레는 서로 다른 치수입니다."),
                .init(garment: "상의 총장", body: "상체 길이·허리선 높이", note: "목 뒤 또는 어깨부터 재는 등 상품별 시작점이 다릅니다."),
                .init(garment: "목둘레·소매단", body: "목둘레·손목둘레", note: "셔츠 단추를 잠갔을 때 필요한 여유도 고려합니다.")
            ]
        case .bottoms:
            return [
                .init(garment: "허리단면", body: "착용 높이의 허리둘레", note: "자연 허리선과 실제 바지 허리선의 높이가 다를 수 있습니다. 밴딩 여부도 확인합니다."),
                .init(garment: "엉덩이단면", body: "엉덩이둘레·돌출 정도", note: "가장 넓은 높이와 상품의 측정 높이를 대조합니다."),
                .init(garment: "허벅지단면", body: "허벅지둘레", note: "가랑이 바로 아래인지 일정 거리 아래인지에 따라 값이 달라집니다."),
                .init(garment: "앞밑위·뒤밑위", body: "허리선 높이·복부·골반·엉덩이", note: "옷의 가랑이 봉제선을 따라 잰 길이입니다. 신체의 수직 길이 하나로 바꿀 수 없습니다."),
                .init(garment: "인심·총장", body: "안쪽 다리 길이·허리선 높이", note: "인심과 바깥쪽 총장은 시작점이 다릅니다. 원하는 밑단 위치와 신발 높이도 고려합니다."),
                .init(garment: "무릎·밑단", body: "무릎·종아리·발목 둘레", note: "바지통이 좁아지는 정도와 소재의 신축성이 움직임에 영향을 줍니다.")
            ]
        }
    }
}

private struct ClothingMeasurementRow: Identifiable {
    let garment: String
    let body: String
    let note: String
    var id: String { garment }
}