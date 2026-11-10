import Foundation
import Combine

struct GarmentProductInfo: Codable, Equatable {
    var name = ""
    var source = ""
    var sizeLabel = ""

    var sourceURL: URL? {
        guard let url = URL(string: source.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var hasValidSource: Bool {
        source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceURL != nil
    }
}

// Retained only for lossless migration from the single-body, per-catalog-slot store.
struct FittingSession: Codable {
    var body = UserBody()
    var base = MannequinBase.male
    var garmentID: String? = GarmentCatalog.samples.first(where: { $0.selectionLabel == "M" })?.id
    var sizes: [String: GarmentSizeInput] = [:]
    var products: [String: GarmentProductInfo] = [:]
}

@MainActor
final class FittingRoom: ObservableObject {
    @Published private(set) var library = FittingLibrary()
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?
    @Published var statusMessage: String?
    @Published private(set) var saveRevision = 0
    let catalog: [GarmentDefinition]
    private let defaults: UserDefaults
    private let fileURL: URL
    private let migratesLegacy: Bool

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil,
         catalog: [GarmentDefinition] = GarmentCatalog.samples, migratesLegacy: Bool = true) {
        self.defaults = defaults
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "WEASHION/fitting-library.json")
        self.catalog = catalog
        self.migratesLegacy = migratesLegacy
        reload()
    }

    static func application() -> FittingRoom {
        #if DEBUG
        if let testID = ProcessInfo.processInfo.environment["WEASHION_UI_TEST_LIBRARY"] {
            precondition(UUID(uuidString: testID) != nil, "UI test library ID must be a UUID.")
            return FittingRoom(fileURL: URL.cachesDirectory.appending(path: "UIFixtures/\(testID)/library.json"),
                               migratesLegacy: false)
        }
        #endif
        return FittingRoom()
    }

    var profile: BodyProfile? { library.activeProfile }
    var product: GarmentProduct? { library.selectedProduct }
    var selectedSize: ProductSize? { library.selectedSize }
    var needsSetup: Bool { library.activeProfile == nil }
    var definition: GarmentDefinition? {
        guard let product, let selectedSize else { return nil }
        return product.definition(for: selectedSize, in: catalog)
    }
    var garmentTitle: String { selectedSize == nil ? L("의류 미착용") : product?.name ?? L("상품을 선택해 주세요") }
    var sizeTitle: String { selectedSize?.label ?? L("미착용") }
    var outfitDefinitions: [GarmentDefinition] {
        OutfitSlot.fittingOrder.compactMap { slot in
            guard let selection = selection(in: slot),
                  let product = library.products.first(where: { $0.id == selection.productID }),
                  let size = product.sizes.first(where: { $0.id == selection.sizeID }) else { return nil }
            return product.definition(for: size, in: catalog)
        }
    }

    func selection(in slot: OutfitSlot) -> OutfitSelection? {
        library.effectiveOutfit.first { selection in
            library.products.first { $0.id == selection.productID }?.kind.slot == slot
        }
    }

    func focus(slot: OutfitSlot) throws {
        var next = library
        let selection = selection(in: slot)
        next.selectedProductID = selection?.productID ?? library.products.first { $0.kind.slot == slot }?.id
        next.selectedSizeID = selection?.sizeID
        try commit(next)
    }

    private func equip(_ productID: String, sizeID: String, in next: inout FittingLibrary) {
        guard let product = next.products.first(where: { $0.id == productID }) else { return }
        next.outfit = next.effectiveOutfit.filter { selection in
            next.products.first { $0.id == selection.productID }?.kind.slot != product.kind.slot
        } + [.init(productID: productID, sizeID: sizeID)]
    }

    var fittingUnavailableReason: String? {
        guard let product, let selectedSize else { return nil }
        if !product.kind.supportsFitting { return L("\(product.kind.title)은(는) 아직 3D 착장을 지원하지 않습니다. 날씨 추천과 기록에는 사용됩니다.") }
        if product.template(in: catalog) == nil { return L("이 상품의 기준 모델을 사용할 수 없습니다. 치수 기록은 보존됩니다.") }
        if !selectedSize.hasValidMeasurements || selectedSize.measurements?.supports(product.kind) != true {
            return L("사이즈의 치수를 확인해 주세요. 유효한 치수 입력 후 피팅할 수 있습니다.")
        }
        return nil
    }

    func reload() {
        do {
            let restored: FittingLibrary
            if FileManager.default.fileExists(atPath: fileURL.path) {
                restored = try JSONDecoder().decode(FittingLibrary.self, from: Data(contentsOf: fileURL))
                try restored.validateReferences()
            } else {
                restored = try migratedLibrary()
                try write(restored)
            }
            var migrated = restored
            migrated.outfit = restored.effectiveOutfit
            var refreshedSamples = false
            for productIndex in migrated.products.indices where migrated.products[productIndex].templateID == "meshy-hoodie" {
                for sizeIndex in migrated.products[productIndex].sizes.indices {
                    let size = migrated.products[productIndex].sizes[sizeIndex]
                    guard size.isSample, let sample = catalog.first(where: {
                        $0.pattern.id == "meshy-hoodie" && $0.id == (size.templateVariantID ?? size.id)
                    }), size.measurements != sample.measurements else { continue }
                    migrated.products[productIndex].sizes[sizeIndex].measurements = sample.measurements
                    refreshedSamples = true
                }
            }
            if refreshedSamples { try write(migrated) }
            library = migrated
            isLoaded = true
            loadError = nil
        } catch {
            isLoaded = false
            loadError = L("저장 정보를 불러오지 못했습니다. 기존 데이터는 덮어쓰지 않았습니다.\n\(error.localizedDescription)")
        }
    }

    func saveSetupDraft(_ draft: BodySetupDraft) throws {
        var next = library
        next.setupDraft = draft
        try commit(next)
    }

    func addProfile(_ profile: BodyProfile, activate: Bool) throws {
        if let message = profile.validationMessage { throw FittingLibraryError.invalid(message) }
        guard !library.profiles.contains(where: { $0.id == profile.id }) else {
            throw FittingLibraryError.invalid(L("이미 저장된 체형입니다."))
        }
        var next = library
        next.profiles.append(profile)
        if activate || next.activeProfileID == nil { next.activeProfileID = profile.id }
        next.setupDraft = nil
        try commit(next, message: L("체형을 저장했어요."))
    }

    func updateProfile(_ profile: BodyProfile) throws {
        if let message = profile.validationMessage { throw FittingLibraryError.invalid(message) }
        guard let index = library.profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw FittingLibraryError.invalid(L("수정할 체형을 찾을 수 없습니다."))
        }
        var next = library
        var edited = profile
        edited.updatedAt = Date()
        next.profiles[index] = edited
        try commit(next, message: L("체형을 저장했어요."))
    }

    func activateProfile(_ id: String) throws {
        guard library.profiles.contains(where: { $0.id == id }) else {
            throw FittingLibraryError.invalid(L("사용할 체형을 찾을 수 없습니다."))
        }
        var next = library
        next.activeProfileID = id
        try commit(next)
    }

    func deleteProfile(_ id: String) throws {
        guard id != library.activeProfileID else {
            throw FittingLibraryError.invalid(L("사용 중인 체형은 삭제할 수 없습니다. 다른 체형을 먼저 선택해 주세요."))
        }
        guard library.profiles.contains(where: { $0.id == id }) else {
            throw FittingLibraryError.invalid(L("삭제할 체형을 찾을 수 없습니다."))
        }
        var next = library
        next.profiles.removeAll { $0.id == id }
        try commit(next, message: L("체형을 삭제했어요."))
    }

    func saveProduct(_ product: GarmentProduct) throws {
        if let message = product.validationMessage { throw FittingLibraryError.invalid(message) }
        var next = library
        var edited = product
        edited.updatedAt = Date()
        if let index = next.products.firstIndex(where: { $0.id == product.id }) {
            // Metadata editing must not overwrite sizes changed elsewhere.
            edited.sizes = next.products[index].sizes
            if edited.kind != next.products[index].kind {
                next.outfit?.removeAll { $0.productID == product.id }
                if next.selectedProductID == product.id { next.selectedSizeID = nil }
            }
            next.products[index] = edited
        } else {
            guard !product.kind.supportsFitting || product.template(in: catalog) != nil else {
                throw FittingLibraryError.invalid(L("상품 종류에 맞는 기준 모델이 없습니다."))
            }
            for index in edited.sizes.indices {
                if let message = product.sizeValidationMessage(edited.sizes[index]) {
                    throw FittingLibraryError.invalid(message)
                }
                edited.sizes[index].label = edited.sizes[index].label.trimmingCharacters(in: .whitespacesAndNewlines)
                edited.sizes[index].isSample = false
            }
            next.products.append(edited)
        }
        try commit(next, message: L("상품을 저장했어요. 사이즈를 추가해 입혀보세요."))
    }

    func addSample(templateID: String) throws {
        guard let sample = GarmentProduct.sample(templateID: templateID, catalog: catalog),
              !sample.sizes.isEmpty, sample.sizes.allSatisfy({ sample.definition(for: $0, in: catalog) != nil }) else {
            throw FittingLibraryError.invalid(L("추가할 샘플 모델의 치수를 불러올 수 없습니다."))
        }
        guard !library.products.contains(where: { $0.id == sample.id }) else {
            throw FittingLibraryError.invalid(L("이미 추가한 샘플 모델입니다."))
        }
        var next = library
        next.products.append(sample)
        next.selectedProductID = sample.id
        next.selectedSizeID = sample.sizes.first(where: { $0.label == "M" })?.id ?? sample.sizes[0].id
        equip(sample.id, sizeID: next.selectedSizeID!, in: &next)
        try commit(next, message: L("예시 치수의 샘플을 추가했어요. 실제 상품 치수와 다를 수 있습니다."))
    }

    func deleteProduct(_ id: String) throws {
        guard library.products.contains(where: { $0.id == id }) else {
            throw FittingLibraryError.invalid(L("삭제할 상품을 찾을 수 없습니다."))
        }
        var next = library
        next.outfit?.removeAll { $0.productID == id }
        next.products.removeAll { $0.id == id }
        if next.selectedProductID == id {
            next.selectedProductID = nil
            next.selectedSizeID = nil
        }
        try commit(next, message: L("상품과 해당 사이즈를 삭제했어요."))
    }

    func saveSize(_ size: ProductSize, productID: String, info: GarmentProductInfo? = nil,
                  select: Bool = false) throws {
        guard let index = library.products.firstIndex(where: { $0.id == productID }) else {
            throw FittingLibraryError.invalid(L("사이즈를 저장할 상품을 찾을 수 없습니다."))
        }
        if let message = library.products[index].sizeValidationMessage(size) {
            throw FittingLibraryError.invalid(message)
        }
        var next = library
        var edited = size
        edited.label = size.label.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.isSample = false
        if let info {
            next.products[index].name = info.name
            next.products[index].source = info.source
            if let message = next.products[index].validationMessage { throw FittingLibraryError.invalid(message) }
        }
        if let sizeIndex = next.products[index].sizes.firstIndex(where: { $0.id == size.id }) {
            next.products[index].sizes[sizeIndex] = edited
        } else {
            next.products[index].sizes.append(edited)
        }
        next.products[index].updatedAt = Date()
        if select {
            guard next.products[index].definition(for: edited, in: catalog) != nil else {
                throw FittingLibraryError.invalid(L("저장은 가능하지만 이 모델은 아직 피팅할 수 없습니다. 사이즈 기록으로 저장해 주세요."))
            }
            next.selectedProductID = productID
            next.selectedSizeID = size.id
            equip(productID, sizeID: size.id, in: &next)
        }
        try commit(next, message: L("치수를 저장했어요. 착장 계산 상태는 별도로 확인해 주세요."))
    }

    func deleteSize(_ id: String, productID: String) throws {
        guard let index = library.products.firstIndex(where: { $0.id == productID }),
              library.products[index].sizes.contains(where: { $0.id == id }) else {
            throw FittingLibraryError.invalid(L("삭제할 사이즈를 찾을 수 없습니다."))
        }
        var next = library
        next.outfit?.removeAll { $0.productID == productID && $0.sizeID == id }
        next.products[index].sizes.removeAll { $0.id == id }
        next.products[index].updatedAt = Date()
        if next.selectedProductID == productID && next.selectedSizeID == id { next.selectedSizeID = nil }
        try commit(next, message: L("사이즈를 삭제했어요."))
    }

    func select(productID: String, sizeID: String) throws {
        guard let product = library.products.first(where: { $0.id == productID }),
              let size = product.sizes.first(where: { $0.id == sizeID }),
              product.definition(for: size, in: catalog) != nil else {
            throw FittingLibraryError.invalid(L("지원하는 모델과 유효한 사이즈 치수가 필요합니다."))
        }
        var next = library
        next.selectedProductID = productID
        next.selectedSizeID = sizeID
        equip(productID, sizeID: sizeID, in: &next)
        try commit(next)
    }

    func undress(slot: OutfitSlot? = nil) throws {
        var next = library
        if let removing = slot ?? product?.kind.slot {
            next.outfit = next.effectiveOutfit.filter { selection in
                next.products.first { $0.id == selection.productID }?.kind.slot != removing
            }
            if product?.kind.slot == removing { next.selectedSizeID = nil }
        }
        try commit(next)
    }

    private func commit(_ next: FittingLibrary, message: String? = nil) throws {
        guard isLoaded else { throw FittingLibraryError.notLoaded }
        if message != nil { statusMessage = nil }
        try write(next)
        library = next
        if let message {
            statusMessage = message
            saveRevision += 1
        }
    }

    private func write(_ next: FittingLibrary) throws {
        try next.validateReferences()
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func migratedLibrary() throws -> FittingLibrary {
        var next = FittingLibrary()
        if let sample = GarmentProduct.sample(catalog: catalog) {
            next.products = [sample]
            next.selectedProductID = sample.id
            next.selectedSizeID = sample.sizes.first(where: { $0.label == "M" })?.id ?? sample.sizes.first?.id
        }
        guard migratesLegacy else { return next }
        let legacy: FittingSession
        if let data = defaults.data(forKey: "editorialFittingSession") {
            legacy = try JSONDecoder().decode(FittingSession.self, from: data)
            let profile = BodyProfile(name: L("나의 체형"), body: legacy.body, base: legacy.base)
            next.profiles = [profile]
            next.activeProfileID = profile.id
        } else if let data = defaults.data(forKey: "primaryGarmentSizes"), !data.isEmpty {
            var session = FittingSession()
            session.sizes = try JSONDecoder().decode([String: GarmentSizeInput].self, from: data)
            legacy = session
        } else {
            return next
        }

        // Old slots could contain unrelated products, even with the same name or URL.
        // Preserve each custom slot independently rather than guessing a grouping.
        var customIDs = Set(legacy.sizes.keys).union(legacy.products.keys)
        if let selectedID = legacy.garmentID, !catalog.contains(where: { $0.id == selectedID }) {
            customIDs.insert(selectedID)
        }
        var migratedSelection: (String, String)?
        for oldID in customIDs.sorted() {
            let template = catalog.first { $0.id == oldID }
            let info = legacy.products[oldID] ?? GarmentProductInfo()
            let input = legacy.sizes[oldID] ?? template?.pattern.dimensions.map { GarmentSizeInput(dimensions: $0) }
            let label = info.sizeLabel.isEmpty ? template?.selectionLabel ?? oldID : info.sizeLabel
            let size = ProductSize(id: "migrated-\(oldID)", label: label,
                                   measurements: input.map { .shortSleeve($0) },
                                   isSample: legacy.sizes[oldID] == nil && template != nil,
                                   templateVariantID: template?.id)
            let product = GarmentProduct(
                id: "migrated-\(oldID)",
                name: info.name.isEmpty ? L("\(template?.name ?? L("이전 상품")) · 가져온 치수") : info.name,
                source: info.source, templateID: template?.pattern.id ?? "unavailable-\(oldID)", sizes: [size]
            )
            next.products.append(product)
            if oldID == legacy.garmentID { migratedSelection = (product.id, size.id) }
        }
        if let migratedSelection {
            next.selectedProductID = migratedSelection.0
            next.selectedSizeID = migratedSelection.1
        } else if let oldID = legacy.garmentID,
                  let product = next.products.first(where: { $0.sizes.contains(where: { $0.id == oldID }) }) {
            next.selectedProductID = product.id
            next.selectedSizeID = oldID
        } else {
            next.selectedSizeID = nil
        }
        return next
    }
}
