import SwiftUI

struct ProductLibraryView: View {
    @ObservedObject var room: FittingRoom
    let onFit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var path: [String] = []
    @State private var newProduct: GarmentProduct?
    @State private var errorMessage: String?

    private var sampleTemplates: [GarmentDefinition] {
        var ids = Set<String>()
        return room.catalog.filter { ids.insert($0.pattern.id).inserted }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    EditorialPageTitle(number: "02", section: "THE GARMENT ARCHIVE",
                                       title: L("내 상품"),
                                       subtitle: L("상품별로 사이즈를 모으고, 같은 내 몸에서 비교하세요."), animated: true, style: .statement)
                    HStack(alignment: .lastTextBaseline, spacing: 18) {
                        Text(room.library.products.count, format: .number)
                            .font(Editorial.serif(64)).monospacedDigit()
                            .foregroundStyle(Editorial.accent)
                            .accessibilityLabel("보관 중인 상품")
                            .accessibilityValue("\(room.library.products.count)")
                            .accessibilityIdentifier("savedProductCount")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("보관 중인 상품").editorialSans(.subheadline)
                            Text("상품마다 사이즈를 따로 기록합니다.").editorialSans(.caption).foregroundStyle(Editorial.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
                    addProductButton
                    sampleGallery
                    if room.library.products.isEmpty {
                        ContentUnavailableView("첫 상품을 기록해 보세요", systemImage: "tshirt",
                                               description: Text("상품의 이름과 사이즈표를 직접 입력하거나 설명용 샘플을 추가하세요."))
                    }
                    LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                              ? [GridItem(.flexible(), alignment: .leading)]
                              : [GridItem(.adaptive(minimum: 230, maximum: 460), spacing: 28, alignment: .leading)],
                              alignment: .leading, spacing: 36) {
                        ForEach(Array(room.library.products.enumerated()), id: \.element.id) { index, product in
                            productTile(product, index: index)
                        }
                    }
                    Text("상의·하의·신발·아우터를 각각 한 개씩 착장합니다. 안쪽 표면을 고려한 정적 보정이며 실제 원단 거동·완전한 무관통은 보장하지 않습니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
                .padding(24)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }
            .background(Editorial.paper)
            .editorialSaveFeedback($room.statusMessage)
            .editorialError($errorMessage)
            .editorialNavigationTitle(L("내 상품"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { EditorialToolbarButton("닫기") { dismiss() } }
            }
            .navigationDestination(for: String.self) { productID in
                ProductDetailView(room: room, productID: productID, onFit: onFit)
            }
            .sheet(item: $newProduct) { product in
                ProductMetadataEditor(product: product, catalog: room.catalog, isNewProduct: true) { product in
                    try room.saveProduct(product)
                    path.append(product.id)
                }
            }
        }
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .tint(Editorial.accent)
        .buttonStyle(EditorialPressStyle())
    }

    private func productTile(_ product: GarmentProduct, index: Int) -> some View {
        NavigationLink(value: product.id) {
            VStack(alignment: .leading, spacing: 16) {
                EditorialGarmentArtwork(number: String(format: "%02d", index + 1),
                                        selected: room.selection(in: product.kind.slot)?.productID == product.id,
                                        kind: product.kind)
                    .frame(height: 200)
                    .editorialReveal(from: .trailing, distance: 64)
                HStack(alignment: .firstTextBaseline) {
                    EditorialEyebrow(text: product.kind.title)
                    Spacer()
                    Text("\(product.sizes.count) SIZES").editorialSans(.caption).monospacedDigit()
                        .foregroundStyle(Editorial.accent)
                }
                .foregroundStyle(Editorial.muted)
                Text(product.name)
                    .editorialSans(.title3, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .editorialReveal(from: .leading)
                HStack(alignment: .top, spacing: 16) {
                    Text(product.sizes.isEmpty ? L("첫 사이즈를 기록하세요.") :
                            product.sizes.map(\.label).joined(separator: " / "))
                        .editorialSans(.subheadline).foregroundStyle(Editorial.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right").font(.title3)
                }
                Text(product.climateSummary)
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
                if !product.kind.supportsFitting {
                    Text("3D 착장 준비 중 · 날씨 추천과 기록에 사용")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                } else if product.template(in: room.catalog) == nil {
                    Label("기준 모델 없음 · 기록 보관 중", systemImage: "exclamationmark.circle")
                        .editorialSans(.caption).foregroundStyle(Editorial.warning)
                }
                Rectangle().fill(Editorial.ink).frame(height: 1)
            }
            .foregroundStyle(Editorial.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("product-\(product.id)")
    }

    private var sampleGallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialHeading(number: "01", title: L("The model study."), subtitle: L("설명용 모델 · S / M / L"))
            Text("샘플 치수는 크기와 체형 차이를 비교하기 위한 예시이며 실측 상품 데이터가 아닙니다. 필요한 모델만 추가하며 삭제한 샘플은 자동으로 복원하지 않습니다.")
                .editorialSans(.caption).foregroundStyle(Editorial.muted)
            ForEach(sampleTemplates) { template in
                if let sample = GarmentProduct.sample(templateID: template.pattern.id, catalog: room.catalog) {
                    let existing = room.library.products.first { $0.id == sample.id }
                    Button {
                        do {
                            if existing == nil { try room.addSample(templateID: template.pattern.id) }
                            path.append(sample.id)
                        } catch { errorMessage = error.localizedDescription }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(sample.name).editorialSans(.subheadline, weight: .semibold)
                                Text("\(template.kind.title) · \(sample.sizes.map(\.label).joined(separator: " / "))")
                                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
                            }
                            Spacer(minLength: 0)
                            Label(existing == nil ? L("샘플 추가") : L("추가됨 · 열기"),
                                  systemImage: existing == nil ? "plus" : "arrow.up.right")
                                .editorialSans(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("sample-model-\(template.pattern.id)")
                    .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
                }
            }
        }
    }

    private var addProductButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if let template = room.catalog.first {
                    newProduct = GarmentProduct(name: "", kind: template.kind, templateID: template.pattern.id)
                }
            } label: {
                Label("상품 추가", systemImage: "plus")
            }
            .buttonStyle(EditorialButtonStyle(filled: true, accented: true))
            .disabled(room.catalog.isEmpty)
            .accessibilityIdentifier("addProduct")
            if room.catalog.isEmpty {
                Text("지원하는 의류 모델을 불러올 수 없어 상품을 추가할 수 없습니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.error)
            }
        }
    }
}

private struct ProductDetailView: View {
    @ObservedObject var room: FittingRoom
    let productID: String
    let onFit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingMetadata = false
    @State private var editingSize: ProductSize?
    @State private var deletingSize: ProductSize?
    @State private var deletingProduct = false
    @State private var showingComparison = false
    @State private var errorMessage: String?
    @State private var addingLabelOnlySize = false
    @State private var newSizeLabel = ""

    private var product: GarmentProduct? { room.library.products.first { $0.id == productID } }

    var body: some View {
        ScrollView {
            if let product {
                VStack(alignment: .leading, spacing: 28) {
                    EditorialPageTitle(number: "02", section: product.kind.title,
                                       title: product.name, subtitle: L("상품은 하나, 사이즈는 각각의 기록입니다."),
                                       compact: true, style: .hangul)
                    EditorialGarmentArtwork(number: "01",
                                            selected: room.selection(in: product.kind.slot)?.productID == product.id,
                                            kind: product.kind)
                        .frame(height: 240)
                    Text(product.climateSummary)
                        .editorialSans(.subheadline)
                    Text(product.kind.supportsFitting
                         ? L("상의·하의·신발·아우터를 각각 한 개씩 착장합니다. 안쪽 표면을 고려한 정적 보정이며 실제 원단 거동·완전한 무관통은 보장하지 않습니다.")
                         : L("이 종류의 3D 착장은 준비 중입니다. 재질·보온 정보는 오늘의 옷차림 추천에 사용됩니다."))
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    if let url = product.sourceURL {
                        Link(destination: url) { Label("원본 상품 확인", systemImage: "arrow.up.right") }
                            .frame(minHeight: 44)
                    } else if !product.source.isEmpty {
                        Label("저장된 URL을 확인해 주세요.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Editorial.warning)
                    }
                    if !product.notes.isEmpty { Text(product.notes).editorialSans(.subheadline) }
                    EditorialHeading(number: "02", title: "Every size, a note.", subtitle: L("치수를 읽고 같은 내 몸에 입혀보세요."))
                    if product.sizes.isEmpty {
                        Text("아직 등록한 사이즈가 없습니다. 첫 사이즈의 실측 치수를 추가해 주세요.")
                            .editorialSans(.body)
                    }
                    ForEach(product.sizes) { size in
                        sizeRow(size, product: product)
                    }
                    Button {
                        if product.kind.supportsFitting {
                            if let measurements = initialMeasurements(for: product) {
                                editingSize = ProductSize(label: "", measurements: measurements)
                            }
                        } else {
                            newSizeLabel = ""
                            addingLabelOnlySize = true
                        }
                    } label: {
                        Label("사이즈 추가", systemImage: "plus")
                    }
                    .buttonStyle(EditorialButtonStyle(filled: true))
                    .disabled(product.kind.supportsFitting && product.template(in: room.catalog) == nil)
                    .accessibilityIdentifier("addProductSize")
                    if product.kind.supportsFitting && product.template(in: room.catalog) == nil {
                        Text("기준 모델이 없습니다. 상품 수정에서 이 종류에 맞는 기준 모델을 선택해 주세요.")
                            .editorialSans(.caption).foregroundStyle(Editorial.warning)
                    }
                    if !product.sizes.isEmpty {
                        DisclosureGroup(isExpanded: $showingComparison) {
                            sizeTable(product).padding(.top, 16)
                        } label: {
                            Text("사이즈 치수 비교").frame(minHeight: 44)
                        }
                        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: showingComparison)
                    }
                    if let measurements = initialMeasurements(for: product) {
                        Text(measurements.editorialMeasurementNote)
                            .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    }
                }
                .padding(24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("상품이 없습니다", systemImage: "tshirt",
                                       description: Text("목록으로 돌아가 다른 상품을 선택해 주세요."))
            }
        }
        .background(Editorial.paper)
        .editorialSaveFeedback($room.statusMessage)
        .editorialNavigationTitle(L("상품과 사이즈"))
        .toolbar {
            if product != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("상품 수정") { editingMetadata = true }
                        Button("상품 삭제", role: .destructive) { deletingProduct = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("상품 관리")
                }
            }
        }
        .sheet(isPresented: $editingMetadata) {
            if let product {
                ProductMetadataEditor(product: product, catalog: room.catalog) { try room.saveProduct($0) }
            }
        }
        .sheet(item: $editingSize) { size in
            sizeEditor(size)
        }
        .alert("사이즈 추가", isPresented: $addingLabelOnlySize) {
            TextField("사이즈명", text: $newSizeLabel)
            Button("저장") {
                do { try room.saveSize(ProductSize(label: newSizeLabel), productID: productID) }
                catch { errorMessage = error.localizedDescription }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 종류는 아직 치수 입력과 3D 착장을 지원하지 않아 사이즈명만 기록합니다.")
        }
        .confirmationDialog("상품과 모든 사이즈를 삭제할까요?", isPresented: $deletingProduct) {
            Button("상품 삭제", role: .destructive) {
                do {
                    try room.deleteProduct(productID)
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("현재 피팅 중인 상품이면 의류 선택도 해제됩니다. 체형은 유지됩니다.")
        }
        .confirmationDialog("이 사이즈를 삭제할까요?", isPresented: Binding(
            get: { deletingSize != nil }, set: { if !$0 { deletingSize = nil } }
        ), presenting: deletingSize) { size in
            Button("\(size.label) 삭제", role: .destructive) {
                do { try room.deleteSize(size.id, productID: productID) }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { _ in
            Text("현재 입고 있는 사이즈이면 미착용으로 전환합니다. 다른 사이즈는 보존됩니다.")
        }
        .editorialError($errorMessage)
    }

    @ViewBuilder
    private func sizeEditor(_ size: ProductSize) -> some View {
        if let product, let template = product.template(in: room.catalog), let profile = room.profile {
            let compatible = size.measurements?.supports(product.kind) == true
            if let measurements = compatible ? size.measurements : initialMeasurements(for: product) {
                switch measurements {
                case .shortSleeve(let input):
                    GarmentEditorView(
                        size: input,
                        product: GarmentProductInfo(name: product.name, source: product.source, sizeLabel: size.label),
                        definition: template, bodyData: profile.body, mannequinBase: profile.base, weather: .sample,
                        sampleDefinitions: room.catalog,
                        showsPreview: false, showsProductFields: false, requiresSizeLabel: true,
                        saveTitle: L("사이즈 저장"),
                        isNewSize: !compatible || !product.sizes.contains(where: { $0.id == size.id })
                    ) { input, info in
                        var next = size
                        next.label = info.sizeLabel
                        next.measurements = .shortSleeve(input)
                        try room.saveSize(next, productID: product.id)
                    }
                case .trousers, .footwear:
                    WearableMeasurementsEditor(
                        measurements: measurements, sizeLabel: size.label,
                        definition: template, bodyData: profile.body, mannequinBase: profile.base, weather: .sample,
                        sampleDefinitions: room.catalog,
                        isNewSize: !compatible || !product.sizes.contains(where: { $0.id == size.id })
                    ) { measurements, label in
                        var next = size
                        next.label = label
                        next.measurements = measurements
                        try room.saveSize(next, productID: product.id)
                    }
                }
            }
        }
    }

    private func sizeRow(_ size: ProductSize, product: GarmentProduct) -> some View {
        let selection = room.selection(in: product.kind.slot)
        let selected = selection?.productID == product.id && selection?.sizeID == size.id
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(selected ? L("선택한 사이즈") : size.isSample ? L("샘플 치수") : L("직접 기록"),
                          systemImage: selected ? "checkmark.circle" : "ruler")
                        .editorialSans(.caption)
                        .foregroundStyle(selected ? Editorial.accent : Editorial.muted)
                    Text(size.label)
                        .font(size.label.unicodeScalars.allSatisfy(\.isASCII) ? Editorial.serif(56) : Editorial.hangul(30, relativeTo: .largeTitle))
                }
                Spacer()
                Menu {
                    Button("치수 수정") { editingSize = size }
                        .disabled(product.template(in: room.catalog) == nil)
                    Button("사이즈 삭제", role: .destructive) { deletingSize = size }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(size.label) 사이즈 관리")
            }
            if let measurements = size.measurements, measurements.supports(product.kind) {
                WearableMeasurementSummary(measurements: measurements.displayed(for: product.templateID), primaryOnly: true)
            }
            if let measurements = size.measurements, !measurements.supports(product.kind) {
                Label("이전 종류의 치수 기록입니다. 자동 변환하지 않습니다. 치수 수정에서 새 종류의 값을 확인해 저장해 주세요.",
                      systemImage: "exclamationmark.circle")
                    .editorialSans(.caption).foregroundStyle(Editorial.warning)
                DisclosureGroup("이전 종류 치수 · 보존된 기록") {
                    WearableMeasurementSummary(measurements: measurements).padding(.top, 12)
                }
            }
            if !product.kind.supportsFitting {
                Text("3D 착장 준비 중 · 사이즈명만 기록")
                    .editorialSans(.caption).foregroundStyle(Editorial.muted)
            } else if !size.hasValidMeasurements || size.measurements?.supports(product.kind) != true {
                Label("치수를 입력하거나 확인해 주세요.", systemImage: "exclamationmark.circle")
                    .editorialSans(.caption).foregroundStyle(Editorial.error)
            }
            Button {
                do {
                    try room.select(productID: product.id, sizeID: size.id)
                    onFit()
                } catch { errorMessage = error.localizedDescription }
            } label: {
                Label(selected ? L("피팅룸에서 보기") : L("이 사이즈 입혀보기"), systemImage: "arrow.up.right")
            }
            .buttonStyle(EditorialButtonStyle())
            .disabled(product.definition(for: size, in: room.catalog) == nil)
            .accessibilityIdentifier("fit-size-\(size.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(20)
        .background(selected ? Editorial.accent.opacity(0.05) : Editorial.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(selected ? Editorial.accent : Editorial.rule).frame(height: selected ? 2 : 0.5)
        }
    }

    private func initialMeasurements(for product: GarmentProduct) -> GarmentMeasurements? {
        let variants = room.catalog.filter { $0.pattern.id == product.templateID && $0.kind == product.kind }
        return (variants.first { $0.selectionLabel == "M" } ?? variants.first)?.measurements
    }

    private func sizeTable(_ product: GarmentProduct) -> some View {
        let fields = (initialMeasurements(for: product) ?? product.sizes.compactMap(\.measurements)
            .first { $0.supports(product.kind) })?.displayed(for: product.templateID).editorialFields ?? []
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                    GridRow {
                        Text("사이즈")
                        ForEach(fields) { field in Text("\(field.title) · \(field.unit)") }
                    }
                    .editorialSans(.caption, weight: .medium)
                    ForEach(product.sizes) { size in
                        GridRow {
                            Text(size.label)
                            ForEach(fields) { field in
                                if let measurements = size.measurements, measurements.supports(product.kind),
                                   let value = measurements.displayed(for: product.templateID).editorialFields.first(where: { $0.id == field.id }) {
                                    Text(value.formatted)
                                } else {
                                    Text("미입력 · 종류 확인")
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .editorialSans(.subheadline).monospacedDigit()
                .padding(.bottom, 8)
            }
            if product.sizes.contains(where: \.isSample) {
                Text("샘플 치수는 설명용이며 실측 상품 데이터가 아닙니다.")
                    .editorialSans(.caption).foregroundStyle(Editorial.warning)
            }
        }
    }
}

private struct ProductMetadataEditor: View {
    @State var product: GarmentProduct
    let catalog: [GarmentDefinition]
    let onSave: (GarmentProduct) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var errorMessage: String?
    @State private var showsFabric: Bool
    @State private var showsClimate: Bool
    @State private var adjustsClimate = false
    @State private var showsAdditionalInfo: Bool
    @State private var entryScrollPosition = ScrollPosition(edge: .top)

    init(product: GarmentProduct, catalog: [GarmentDefinition], isNewProduct: Bool = false,
         onSave: @escaping (GarmentProduct) throws -> Void) {
        _product = State(initialValue: product)
        self.catalog = catalog
        self.onSave = onSave
        _showsFabric = State(initialValue: !isNewProduct)
        _showsClimate = State(initialValue: !isNewProduct)
        _showsAdditionalInfo = State(initialValue: !isNewProduct)
    }

    private var templates: [GarmentDefinition] {
        var ids = Set<String>()
        return catalog.filter { $0.kind == product.kind && ids.insert($0.pattern.id).inserted }
    }

    private var climate: Binding<GarmentClimate> {
        Binding(get: { product.effectiveClimate }, set: { product.climate = $0 })
    }

    /// Material and weight re-suggest warmth, rain response and seasons; the user can then adjust them.
    private func resuggestClimate(material: GarmentFabricKind? = nil, weight: GarmentWeight? = nil,
                                  revealsClimate: Bool = true) {
        let current = product.effectiveClimate
        withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) {
            product.climate = .suggested(kind: product.kind, material: material ?? current.material,
                                        weight: weight ?? current.weight)
            showsFabric = true
            if revealsClimate { showsClimate = true }
        }
    }

    private var fabricFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditorialHeading(number: "02", title: "Material & weight.", subtitle: L("재질과 두께"))
            Picker("재질", selection: Binding(get: { climate.wrappedValue.material },
                                            set: { resuggestClimate(material: $0) })) {
                ForEach(GarmentFabricKind.allCases) { material in Text(material.title).tag(material) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("garmentMaterial")
            Picker("두께", selection: Binding(get: { climate.wrappedValue.weight },
                                            set: { resuggestClimate(weight: $0) })) {
                ForEach(GarmentWeight.allCases) { weight in Text(weight.title).tag(weight) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("garmentWeight")
            if !showsClimate {
                Button {
                    resuggestClimate()
                } label: {
                    HStack {
                        Text("날씨 정보 보기")
                        Spacer()
                        Image(systemName: "arrow.down")
                    }
                }
                .buttonStyle(EditorialButtonStyle(accented: true))
                .accessibilityIdentifier("showGarmentClimate")
            }
        }
    }

    private var climateFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditorialHeading(number: "03", title: "Weather notes.",
                             subtitle: product.climate == nil ? L("재질 미선택 · 코튼 / 보통 기준") :
                                L("선택한 재질과 두께를 바탕으로 제안했어요."))
            Text(product.climateSummary)
                .font(Editorial.hangul(20, relativeTo: .title3))
                .foregroundStyle(Editorial.accent)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityIdentifier("garmentClimateSummary")
            DisclosureGroup(isExpanded: $adjustsClimate) {
                climateAdjustments.padding(.top, 16)
            } label: {
                Text("날씨 정보 조정").frame(minHeight: 44, alignment: .leading)
            }
            .editorialSans(.subheadline)
            .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: adjustsClimate)
            .accessibilityIdentifier("adjustGarmentClimate")
        }
    }

    private var climateAdjustments: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("보온")
                    Spacer()
                    Text(climate.wrappedValue.warmthTitle).foregroundStyle(Editorial.muted)
                }
                .editorialSans(.subheadline)
                Picker("보온", selection: climate.warmth) {
                    ForEach(Array(GarmentClimate.warmthRange), id: \.self) { level in
                        Text(String(repeating: "●", count: level) + String(repeating: "○", count: 5 - level)).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("보온 등급")
            }
            Picker("비 대응", selection: climate.rain) {
                ForEach(RainResponse.allCases) { response in Text(response.title).tag(response) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                Text("계절").editorialSans(.subheadline)
                HStack(spacing: 8) {
                    ForEach(Season.allCases) { season in
                        let selected = climate.wrappedValue.seasons.contains(season)
                        Button(season.title) {
                            var next = climate.wrappedValue
                            if selected { next.seasons.remove(season) } else { next.seasons.insert(season) }
                            climate.wrappedValue = next
                        }
                        .buttonStyle(EditorialChoiceStyle(selected: selected))
                    }
                }
            }
            Text("제안값은 재질·두께에서 계산한 출발점입니다. 실제 옷의 안감·충전재에 맞게 조정해 주세요.")
                .editorialSans(.caption).foregroundStyle(Editorial.muted)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    metadataFields
                        .padding(24)
                }
                .scrollPosition($entryScrollPosition)
                .onChange(of: showsFabric) { _, expanded in
                    if expanded { revealLatestStep() }
                }
                .onChange(of: showsClimate) { _, expanded in
                    if expanded { revealLatestStep() }
                }
                .onChange(of: product.kind) { _, _ in
                    if product.template(in: catalog) == nil, let template = templates.first {
                        product.templateID = template.pattern.id
                    }
                    resuggestClimate(revealsClimate: false)
                }
                .scrollDismissesKeyboard(.interactively)
                saveProductFooter
            }
            .background(Editorial.paper)
            .editorialNavigationTitle(L("상품 기록"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditorialToolbarButton("취소") { dismiss() } }
            }
        }
        .interactiveDismissDisabled()
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .tint(Editorial.accent)
        .editorialError($errorMessage)
    }

    private func revealLatestStep() {
        withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) {
            entryScrollPosition.scrollTo(edge: .bottom)
        }
    }

    private var metadataFields: some View {
        VStack(alignment: .leading, spacing: 24) {
            EditorialPageTitle(number: "01", section: "THE GARMENT",
                               title: L("상품 기록"), subtitle: L("상품을 기록한 다음 사이즈를 추가하세요."),
                               compact: true, style: .hangul)
            Picker("종류", selection: $product.kind) {
                ForEach(GarmentKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("garmentKind")
            if product.kind.supportsFitting {
                Picker("기준 모델", selection: $product.templateID) {
                    if product.template(in: catalog) == nil {
                        Text("사용할 수 없는 기존 모델").tag(product.templateID)
                    }
                    ForEach(templates) { template in
                        Text(template.name).tag(template.pattern.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("garmentTemplate")
                if product.template(in: catalog) == nil {
                    Text("이 종류에 맞는 기준 모델을 사용할 수 없습니다. 기존 치수는 보존됩니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.warning)
                }
            }
            if product.sizes.contains(where: { $0.measurements.map { !$0.supports(product.kind) } == true }) {
                Text("종류를 바꿔도 기존 사이즈는 보존됩니다. 다른 종류의 치수는 자동 변환하지 않으므로 새 종류에 맞게 직접 수정하거나 새 사이즈를 추가하세요.")
                    .editorialSans(.caption).foregroundStyle(Editorial.warning)
            }
            EditorialTextField(title: L("상품명"), text: $product.name,
                               invalid: product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            DisclosureGroup(isExpanded: $showsAdditionalInfo) {
                additionalFields.padding(.top, 12)
            } label: {
                Text("추가 정보 · 선택").frame(minHeight: 44, alignment: .leading)
            }
            .editorialSans(.subheadline)
            .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: showsAdditionalInfo)
            if showsFabric {
                fabricFields.transition(.opacity.combined(with: .offset(y: 8)))
            } else {
                Button {
                    withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) { showsFabric = true }
                } label: {
                    HStack {
                        Text("재질과 두께 선택")
                        Spacer()
                        Image(systemName: "arrow.down")
                    }
                }
                .buttonStyle(EditorialButtonStyle(accented: true))
                .accessibilityIdentifier("showGarmentFabric")
            }
            if showsClimate {
                climateFields.transition(.opacity.combined(with: .offset(y: 8)))
            }
            if let message = product.validationMessage {
                EditorialNotice(title: L("상품 정보를 확인해 주세요"), detail: message, tone: .error)
            }
        }
    }

    private var saveProductFooter: some View {
        VStack(spacing: 10) {
            if product.climate == nil {
                Text("재질 미선택 · 코튼 / 보통 기준")
                    .editorialSans(.caption2).foregroundStyle(Editorial.muted)
            }
            Button {
                do {
                    try onSave(product)
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            } label: {
                Label("상품 저장", systemImage: "checkmark")
            }
            .buttonStyle(EditorialButtonStyle(filled: true, accented: true))
            .disabled(product.validationMessage != nil)
            .accessibilityIdentifier("saveProduct")
        }
        .padding(20)
        .background(Editorial.paper)
    }

    private var additionalFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            EditorialTextField(title: L("상품 URL · 선택"), text: $product.source,
                               invalid: !product.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                   && product.sourceURL == nil)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            EditorialTextField(title: L("상품 메모 · 선택"), text: $product.notes)
            Text(product.kind.supportsFitting
                 ? L("선택한 기준 모델에 치수를 적용합니다. URL에서 디자인·사진·치수를 자동으로 가져오지 않습니다.")
                 : L("이 종류의 3D 착장은 준비 중입니다. 사이즈명과 아래 날씨 정보만 기록되며 오늘의 옷차림 추천에 사용됩니다."))
                .editorialSans(.subheadline).foregroundStyle(Editorial.muted)
        }
    }
}
