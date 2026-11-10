import Foundation

struct BodyProfile: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var body: UserBody
    var base: MannequinBase
    var updatedAt = Date()

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("체형 이름을 입력해 주세요.")
        }
        for measurement in BodyMeasurement.allCases {
            if !measurement.range(for: base).contains(body[keyPath: measurement.keyPath]) {
                return L("\(measurement.title) 입력 범위를 확인해 주세요.")
            }
        }
        if let foot = body.footLength, !foot.isFinite || foot <= 0 {
            return L("발 길이를 확인해 주세요.")
        }
        if body.partScales?.values.contains(where: { !$0.isFinite || $0 <= 0 }) == true {
            return L("세부 체형 조절값을 확인해 주세요.")
        }
        return nil
    }
}

struct BodySetupDraft: Codable {
    var name = L("나의 체형")
    var base: MannequinBase?
    var height: Double?
    var weight: Double?
    var body = UserBody()
    var step = 0

    var hasValidBasics: Bool {
        guard let base, let height, let weight else { return false }
        return BodyMeasurement.height.range(for: base).contains(height)
            && BodyMeasurement.weight.range(for: base).contains(weight)
    }

    var previewBody: UserBody {
        var value = body
        for (measurement, number) in [(BodyMeasurement.height, height), (.weight, weight)] {
            if let number, measurement.range(for: base ?? .male).contains(number) {
                value.setMeasurement(number, for: measurement)
                value.measuredFields = (value.measuredFields ?? []).union([measurement])
            }
        }
        return value
    }

    mutating func selectBase(_ next: MannequinBase) {
        if let previous = base {
            body.applyDefaults(from: previous, to: next)
        } else {
            body = .defaults(for: next)
        }
        base = next
    }

    func makeProfile() throws -> BodyProfile {
        guard let base, hasValidBasics else {
            throw FittingLibraryError.invalid(L("기준 체형과 키·몸무게를 확인해 주세요."))
        }
        let profile = BodyProfile(name: name, body: previewBody, base: base)
        if let message = profile.validationMessage { throw FittingLibraryError.invalid(message) }
        return profile
    }
}

nonisolated enum GarmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortSleeveTShirt, longSleeveTop, knitwear, outerwear, pants, shorts, shoes

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .shortSleeveTShirt: L("반팔 티셔츠")
        case .longSleeveTop: L("긴팔 상의")
        case .knitwear: L("니트")
        case .outerwear: L("아우터")
        case .pants: L("긴바지")
        case .shorts: L("반바지")
        case .shoes: L("신발")
        }
    }

    var slot: OutfitSlot {
        switch self {
        case .shortSleeveTShirt, .longSleeveTop, .knitwear: .top
        case .outerwear: .outer
        case .pants, .shorts: .bottom
        case .shoes: .shoes
        }
    }

    var supportsFitting: Bool { self != .shorts }

    var warmthAdjustment: Int {
        switch self {
        case .shortSleeveTShirt, .shorts: -1
        case .outerwear: 1
        default: 0
        }
    }
}

nonisolated enum GarmentMeasurements: Codable, Equatable, Sendable {
    case shortSleeve(GarmentSizeInput)
    case trousers(TrouserSizeInput)
    case footwear(FootwearSizeInput)

    var shortSleeve: GarmentSizeInput? {
        switch self {
        case .shortSleeve(let size): size
        case .trousers, .footwear: nil
        }
    }

    func displayed(for templateID: String) -> Self {
        guard case .shortSleeve(let input) = self else { return self }
        return .shortSleeve(GarmentSizeLabelCalibration(templateID: templateID).displayed(input))
    }

    var isValid: Bool {
        switch self {
        case .shortSleeve(let size): size.isValid && size.specification.isValid
        case .trousers(let size): size.isValid
        case .footwear(let size): size.isValid
        }
    }

    func supports(_ kind: GarmentKind) -> Bool {
        switch self {
        case .shortSleeve: [.shortSleeveTShirt, .longSleeveTop, .knitwear, .outerwear].contains(kind)
        case .trousers: kind == .pants
        case .footwear: kind == .shoes
        }
    }

    func applying(to definition: GarmentDefinition) -> GarmentDefinition? {
        guard isValid, supports(definition.kind) else { return nil }
        switch self {
        case .shortSleeve(let input): return input.applying(to: definition)
        case .trousers(let input):
            var pattern = definition.pattern
            pattern.trouserDimensions = input.specification
            let material = GarmentMaterial(maximumStrain: definition.material.maximumStrain,
                                           fabric: input.fabric ?? definition.material.fabric)
            return .init(id: definition.id, name: definition.name, selectionLabel: definition.selectionLabel,
                         pattern: pattern, material: material, appearance: definition.appearance)
        case .footwear(let input):
            var pattern = definition.pattern
            pattern.footwearDimensions = input.specification
            return .init(id: definition.id, name: definition.name, selectionLabel: definition.selectionLabel,
                         pattern: pattern, material: definition.material, appearance: definition.appearance)
        }
    }
}

struct ProductSize: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var label: String
    var measurements: GarmentMeasurements?
    var isSample = false
    var templateVariantID: String?

    var input: GarmentSizeInput? { measurements?.shortSleeve }
    var hasValidMeasurements: Bool { measurements?.isValid == true }
}

struct GarmentProduct: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var source = ""
    var notes = ""
    var kind = GarmentKind.shortSleeveTShirt
    var templateID: String
    var sizes: [ProductSize] = []
    var updatedAt = Date()
    /// Optional so libraries written before weather attributes existed keep decoding.
    var climate: GarmentClimate?

    var sourceURL: URL? { GarmentProductInfo(source: source).sourceURL }

    var effectiveClimate: GarmentClimate {
        climate ?? .suggested(kind: kind, material: .cotton, weight: .medium)
    }

    /// One-line reading of the weather attributes, e.g. "긴팔 상의 · 코튼 · 보통 · 시원함 · 봄 여름 가을".
    var climateSummary: String {
        let climate = effectiveClimate
        let seasons = Season.allCases.filter { climate.seasons.contains($0) }.map(\.title).joined(separator: " ")
        var parts = [kind.title, climate.material.title, climate.weight.title, climate.warmthTitle]
        if climate.rain.handlesRain { parts.append(climate.rain.title) }
        if !seasons.isEmpty { parts.append(seasons) }
        return parts.joined(separator: " · ")
    }

    /// Sizes of kinds without a 3D pattern only need a label.
    func sizeIsComplete(_ size: ProductSize) -> Bool {
        kind.supportsFitting ? size.hasValidMeasurements && size.measurements?.supports(kind) == true
            : !size.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func template(in catalog: [GarmentDefinition]) -> GarmentDefinition? {
        catalog.first { $0.pattern.id == templateID && $0.kind == kind }
    }

    func definition(for size: ProductSize, in catalog: [GarmentDefinition]) -> GarmentDefinition? {
        guard kind.supportsFitting, let measurements = size.measurements, measurements.isValid,
              measurements.supports(kind),
              let template = template(in: catalog) else {
            return nil
        }
        let originalSample = size.isSample ? catalog.first {
            $0.id == (size.templateVariantID ?? size.id) && $0.pattern.id == templateID
        } : nil
        guard let resized = originalSample ?? measurements.applying(to: template) else { return nil }
        return GarmentDefinition(
            id: "\(id)/\(size.id)", name: name, selectionLabel: size.label,
            pattern: resized.pattern, material: resized.material, appearance: resized.appearance
        )
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L("상품명을 입력해 주세요.") }
        if !GarmentProductInfo(source: source).hasValidSource { return L("올바른 http 또는 https 상품 URL을 입력해 주세요.") }
        return nil
    }

    func sizeValidationMessage(_ size: ProductSize) -> String? {
        let label = size.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty || (kind.supportsFitting && (!size.hasValidMeasurements || size.measurements?.supports(kind) != true)) {
            return kind.supportsFitting ? L("사이즈명과 입력 치수 범위를 확인해 주세요.") : L("사이즈명을 입력해 주세요.")
        }
        if sizes.contains(where: {
            $0.id != size.id && $0.label.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(label) == .orderedSame
        }) {
            return L("이 상품에 같은 사이즈명이 있습니다. 다른 이름을 사용하거나 기존 사이즈를 수정해 주세요.")
        }
        return nil
    }

    static func sample(catalog: [GarmentDefinition]) -> GarmentProduct? {
        guard let template = catalog.first else { return nil }
        return sample(templateID: template.pattern.id, catalog: catalog)
    }

    static func sample(templateID: String, catalog: [GarmentDefinition]) -> GarmentProduct? {
        guard let template = catalog.first(where: { $0.pattern.id == templateID }) else { return nil }
        return GarmentProduct(
            id: template.kind == .shortSleeveTShirt ? "sample-cotton" : "sample-\(templateID)",
            name: template.kind == .shortSleeveTShirt ? L("그레이 코튼 반팔 · 샘플") : L("\(template.name) · 샘플"),
            kind: template.kind, templateID: template.pattern.id,
            sizes: catalog.filter { $0.pattern.id == template.pattern.id }.map { definition in
                ProductSize(
                    id: definition.id, label: definition.selectionLabel,
                    measurements: definition.measurements,
                    isSample: true, templateVariantID: definition.id
                )
            }
        )
    }
}

struct GarmentSizeComparison {
    let length: Double
    let shoulderWidth: Double
    let chestWidth: Double

    init?(previous: ProductSize, current: ProductSize) {
        guard previous.id != current.id, let before = previous.input, let after = current.input,
              before.isValid, after.isValid else { return nil }
        length = after.length - before.length
        shoulderWidth = after.shoulderWidth - before.shoulderWidth
        chestWidth = after.chestWidth - before.chestWidth
    }
}

struct OutfitSelection: Codable, Equatable {
    let productID: String
    let sizeID: String
}

struct FittingLibrary: Codable {
    var version = 1
    var profiles: [BodyProfile] = []
    var activeProfileID: String?
    var products: [GarmentProduct] = []
    var selectedProductID: String?
    var selectedSizeID: String?
    var setupDraft: BodySetupDraft?
    var outfit: [OutfitSelection]?

    var activeProfile: BodyProfile? { profiles.first { $0.id == activeProfileID } }
    var selectedProduct: GarmentProduct? { products.first { $0.id == selectedProductID } }
    var selectedSize: ProductSize? { selectedProduct?.sizes.first { $0.id == selectedSizeID } }

    var effectiveOutfit: [OutfitSelection] {
        if let outfit { return outfit }
        guard let selectedProductID, let selectedSizeID else { return [] }
        return [.init(productID: selectedProductID, sizeID: selectedSizeID)]
    }

    func validateReferences() throws {
        guard version == 1 else { throw FittingLibraryError.unsupportedVersion }
        if let message = profiles.compactMap(\.validationMessage).first {
            throw FittingLibraryError.invalid(message)
        }
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(products.map(\.id)).count == products.count,
              products.allSatisfy({ Set($0.sizes.map(\.id)).count == $0.sizes.count }),
              profiles.isEmpty ? activeProfileID == nil : activeProfile != nil,
              selectedProductID == nil || selectedProduct != nil,
              selectedSizeID == nil || selectedSize != nil,
              setupDraft.map({ (0...2).contains($0.step) }) ?? true else {
            throw FittingLibraryError.invalid(L("저장된 체형·상품의 연결 정보를 확인할 수 없습니다."))
        }
        var slots = Set<OutfitSlot>()
        for selection in effectiveOutfit {
            guard let product = products.first(where: { $0.id == selection.productID }),
                  product.sizes.contains(where: { $0.id == selection.sizeID }),
                  slots.insert(product.kind.slot).inserted else {
                throw FittingLibraryError.invalid(L("저장된 체형·상품의 연결 정보를 확인할 수 없습니다."))
            }
        }
    }
}

enum FittingLibraryError: LocalizedError {
    case invalid(String)
    case notLoaded
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .notLoaded: L("저장 정보를 먼저 불러와 주세요. 기존 데이터는 변경하지 않았습니다.")
        case .unsupportedVersion: L("이 앱에서 읽을 수 없는 저장 형식입니다. 앱 버전을 확인해 주세요.")
        }
    }
}
