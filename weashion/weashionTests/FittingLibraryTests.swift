import Foundation
import Testing
@testable import weashion

@MainActor
struct FittingLibraryTests {
    @Test func hoodieLabelsKeepApprovedGeometryAndCustomStorageWhileRefreshingSamples() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let catalog = GarmentCatalog.samples
        let medium = try #require(catalog.first { $0.id == "meshy-hoodie-m" })
        let input = try #require(medium.measurements?.shortSleeve)
        #expect(input.length == 65 && input.shoulderWidth == 58 && input.chestWidth == 56 && input.sleeveLength == 50)
        #expect(input.sleeveWidthPercent == 80)
        let displayed = GarmentSizeLabelCalibration(templateID: medium.pattern.id).displayed(input)
        #expect(abs(displayed.length - 70) < 0.00001)
        #expect(abs(displayed.shoulderWidth - 52) < 0.00001)
        #expect(abs(displayed.chestWidth - 58) < 0.00001)
        #expect(abs(displayed.sleeveLength - 60) < 0.00001)
        #expect(displayed.sleeveWidthPercent == 100)
        #expect(GarmentSizeLabelCalibration(templateID: "meshy-bomber").displayed(input) == input)
        let labels = GarmentSizeLabelCalibration(templateID: medium.pattern.id)
        #expect(abs(100 / labels.sleeveWidth - 80) < 0.00001)
        #expect(abs(70 / labels.length - 65) < 0.00001)
        #expect(abs(52 / labels.shoulder - 58) < 0.00001)
        #expect(abs(58 / labels.chest - 56) < 0.00001)
        #expect(abs(60 / labels.sleeve - 50) < 0.00001)
        var legacy = input
        legacy.sleeveWidthPercent = nil
        #expect(labels.displayed(legacy).sleeveWidthPercent == 125)
        legacy.sleeveWidthPercent = 150
        #expect(legacy.isValid)
        #expect(labels.displayed(legacy).sleeveWidthPercent == 187.5)
        let room = fixture.room()
        try room.addSample(templateID: medium.pattern.id)
        let product = try #require(room.product)
        var oldLibrary = room.library
        let productIndex = try #require(oldLibrary.products.firstIndex { $0.id == product.id })
        let sampleIndex = try #require(oldLibrary.products[productIndex].sizes.firstIndex { $0.label == "M" })
        var oldInput = GarmentSizeInput(length: 70, shoulderWidth: 52, chestWidth: 58, sleeveLength: 60)
        oldInput.sleeveOpeningWidth = 10
        oldLibrary.products[productIndex].sizes[sampleIndex].measurements = .shortSleeve(oldInput)
        let custom = ProductSize(label: "My fit", measurements: .shortSleeve(input), isSample: false)
        oldLibrary.products[productIndex].sizes.append(custom)
        try JSONEncoder().encode(oldLibrary).write(to: fixture.file, options: .atomic)
        let reopened = fixture.room()
        #expect(reopened.isLoaded)
        let restored = try #require(reopened.library.products.first { $0.id == product.id })
        #expect(restored.sizes[sampleIndex].measurements == medium.measurements)
        #expect(restored.sizes.first { $0.id == custom.id } == custom)
        #expect(fixture.room().library.products == reopened.library.products)
    }

    @Test func outfitMigratesReplacesOnlyItsSlotAndSurvivesEditsDeletionAndReload() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let original = try #require(room.product)
        for id in ["meshy-jeans", "meshy-sneakers", "meshy-bomber"] { try room.addSample(templateID: id) }
        #expect(room.outfitDefinitions.count == 4)
        try room.addSample(templateID: "meshy-hoodie")
        #expect(room.outfitDefinitions.count == 4)
        #expect(room.outfitDefinitions.first { $0.kind.slot == .top }?.pattern.fittingMode == .shapePreserving)
        #expect(!room.library.effectiveOutfit.contains { $0.productID == original.id })
        let reopened = fixture.room()
        #expect(reopened.library.effectiveOutfit == room.library.effectiveOutfit)
        #expect(reopened.outfitDefinitions.first { $0.kind.slot == .top }?.pattern.fittingMode == .shapePreserving)
        try reopened.focus(slot: .bottom)
        let pants = try #require(reopened.product)
        var size = try #require(reopened.selectedSize)
        guard case .trousers(var input) = size.measurements else { Issue.record("Expected pants"); return }
        input.totalLength = 96
        size.measurements = .trousers(input)
        try reopened.saveSize(size, productID: pants.id, select: true)
        #expect(reopened.outfitDefinitions.count == 4)
        #expect(abs(try #require(reopened.definition?.pattern.trouserDimensions).totalLength - 0.96) < 0.00001)
        try reopened.undress(slot: .outer)
        #expect(reopened.outfitDefinitions.count == 3)
        try reopened.deleteSize(size.id, productID: pants.id)
        #expect(reopened.outfitDefinitions.count == 2)
        let shoes = try #require(reopened.selection(in: .shoes))
        try reopened.deleteProduct(shoes.productID)
        #expect(reopened.outfitDefinitions.count == 1)
        #expect(fixture.room().outfitDefinitions.count == 1)
        var legacy = reopened.library
        legacy.outfit = nil
        legacy.selectedProductID = original.id
        legacy.selectedSizeID = original.sizes[0].id
        try JSONEncoder().encode(legacy).write(to: fixture.file)
        let migrated = fixture.room()
        #expect(migrated.outfitDefinitions.count == 1)
        #expect(migrated.selection(in: .top)?.productID == original.id)
        try migrated.undress()
        #expect(fixture.room().outfitDefinitions.isEmpty)
    }

    @MainActor private struct Fixture {
        let suite = "Weashion.LibraryTests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: "WeashionLibrary-\(UUID().uuidString)")
        let defaults: UserDefaults
        var file: URL { directory.appending(path: "library.json") }

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        func room(catalog: [GarmentDefinition] = GarmentCatalog.samples) -> FittingRoom {
            FittingRoom(defaults: defaults, fileURL: file, catalog: catalog)
        }

        func clean() {
            defaults.removePersistentDomain(forName: suite)
            do {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            } catch { Issue.record(error) }
        }
    }

    @Test func firstRunRequiresAnExplicitBaseAndRestoresAnUnfinishedDraft() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        #expect(room.isLoaded)
        #expect(room.needsSetup)
        #expect(room.profile == nil)
        let sample = try #require(room.catalog.first { $0.selectionLabel == "M" })
        #expect(room.definition?.pattern == sample.pattern)
        #expect(room.definition?.material == sample.material)
        var draft = BodySetupDraft()
        #expect(draft.base == nil)
        #expect(throws: FittingLibraryError.self) { try draft.makeProfile() }
        draft.selectBase(.female)
        draft.height = 168
        draft.weight = 58
        draft.step = 2
        try room.saveSetupDraft(draft)
        let resumed = fixture.room()
        #expect(resumed.needsSetup)
        #expect(resumed.library.setupDraft?.base == .female)
        #expect(resumed.library.setupDraft?.height == 168)
        #expect(resumed.library.setupDraft?.step == 2)
        let profile = try draft.makeProfile()
        try resumed.addProfile(profile, activate: true)
        let reopened = fixture.room()
        #expect(!reopened.needsSetup)
        #expect(reopened.library.setupDraft == nil)
        #expect(reopened.profile?.id == profile.id)
        #expect(reopened.profile?.body.height == 168)
        #expect(reopened.profile?.body.measuredFields?.contains(.height) == true)
    }

    @Test func switchingProfilesPreservesGarmentMeasurementsAndInactiveProfiles() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let first = BodyProfile(name: "현재 체형", body: UserBody(), base: .male)
        var otherBody = UserBody.defaults(for: .female)
        otherBody.height = 168
        otherBody.measuredFields = [.height]
        let second = BodyProfile(name: "다른 체형", body: otherBody, base: .female)
        try room.addProfile(first, activate: true)
        let products = room.library.products
        try room.addProfile(second, activate: false)
        #expect(room.profile?.id == first.id)
        try room.activateProfile(second.id)
        #expect(room.profile?.body.height == 168)
        #expect(room.library.products == products)
        #expect(room.library.profiles.first(where: { $0.id == first.id })?.body.height == 175)
        #expect(throws: FittingLibraryError.self) { try room.deleteProfile(second.id) }
        #expect(room.library.profiles.count == 2)
        try room.deleteProfile(first.id)
        #expect(room.library.profiles.count == 1)
        let restored = fixture.room()
        #expect(restored.profile?.id == second.id)
        #expect(restored.library.products == products)
    }

    @Test func expandedFemaleLimitsSurviveSetupStorageAndProfileReload() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        var draft = BodySetupDraft()
        draft.selectBase(.female)
        draft.height = 140
        draft.weight = 35
        for measurement in BodyMeasurement.allCases {
            draft.body.setMeasurement(measurement.range(for: .female).lowerBound, for: measurement)
        }
        draft.body.measuredFields = Set(BodyMeasurement.allCases.filter(\.isPhysical))
        draft.step = 2
        try room.saveSetupDraft(draft)
        let resumed = fixture.room()
        let restoredDraft = try #require(resumed.library.setupDraft)
        #expect(restoredDraft.hasValidBasics)
        let profile = try restoredDraft.makeProfile()
        try resumed.addProfile(profile, activate: true)
        let reopened = fixture.room()
        let saved = try #require(reopened.profile)
        #expect(saved.base == .female)
        #expect(saved.validationMessage == nil)
        for measurement in BodyMeasurement.allCases {
            #expect(saved.body[keyPath: measurement.keyPath] == measurement.range(for: .female).lowerBound)
        }
        #expect(saved.body.measuredFields == draft.body.measuredFields)
        var male = saved
        male.base = .male
        male.body.applyDefaults(from: .female, to: .male)
        #expect(male.body.weight == 35)
        #expect(male.body.chest == 30)
        #expect(throws: FittingLibraryError.self) { try reopened.updateProfile(male) }
        #expect(reopened.profile?.base == .female)
        #expect(reopened.profile?.body.weight == 35)
    }

    @Test func explicitMeasurementsSurviveBaseChangesWithoutChangingClothes() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        var body = UserBody()
        body.height = 182
        body.chest = 102
        body.measuredFields = [.height, .chest]
        body.partScales = ["leftUpperArm": 1.03, "rightUpperArm": 1.03]
        var profile = BodyProfile(name: "나", body: body, base: .male)
        try room.addProfile(profile, activate: true)
        let selection = room.library.selectedSizeID
        profile.body.applyDefaults(from: .male, to: .female)
        profile.base = .female
        try room.updateProfile(profile)
        #expect(room.profile?.body.height == 182)
        #expect(room.profile?.body.chest == 102)
        #expect(room.profile?.body.partScales == body.partScales)
        #expect(room.library.selectedSizeID == selection)
    }

    @Test func productsOwnIndependentSizesAndUseTheExistingTShirtAdapter() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let template = try #require(room.catalog.first)
        let profile = BodyProfile(name: "내 기준", body: UserBody(), base: .male)
        try room.addProfile(profile, activate: true)
        var first = GarmentProduct(name: "A 반팔", source: "https://example.com/a", templateID: template.pattern.id)
        let second = GarmentProduct(name: "B 반팔", templateID: template.pattern.id)
        try room.saveProduct(first)
        try room.saveProduct(second)
        let mediumA = ProductSize(label: "M", measurements: .shortSleeve(.small))
        let mediumB = ProductSize(label: "M", measurements: .shortSleeve(.large))
        try room.saveSize(mediumA, productID: first.id)
        try room.saveSize(mediumB, productID: second.id)
        try room.select(productID: first.id, sizeID: mediumA.id)
        #expect(room.definition?.pattern.dimensions == GarmentSizeInput.small.specification)
        let firstDefinitionID = room.definition?.id
        try room.select(productID: second.id, sizeID: mediumB.id)
        #expect(room.definition?.pattern.dimensions == GarmentSizeInput.large.specification)
        #expect(room.definition?.id != firstDefinitionID)
        #expect(room.profile?.id == profile.id)
        #expect(room.profile?.body.height == profile.body.height)

        first.name = "A 상품 이름 수정"
        try room.saveProduct(first)
        let savedA = try #require(room.library.products.first { $0.id == first.id })
        #expect(savedA.sizes.first?.input == .small)
        #expect(room.library.products.first { $0.id == second.id }?.sizes.first?.input == .large)
        let restored = fixture.room()
        #expect(restored.library.products == room.library.products)
        #expect(restored.definition?.pattern.dimensions == GarmentSizeInput.large.specification)
        #expect(restored.library.selectedProductID == second.id)
    }

    @Test func duplicateLabelsAndInvalidInputsDoNotOverwriteCurrentData() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let product = try #require(room.product)
        let before = room.library.products
        #expect(throws: FittingLibraryError.self) {
            try room.saveSize(ProductSize(label: " m ", measurements: .shortSleeve(.large)), productID: product.id)
        }
        var invalid = GarmentSizeInput.medium
        invalid.chestWidth = 0
        #expect(throws: FittingLibraryError.self) {
            try room.saveSize(ProductSize(label: "100", measurements: .shortSleeve(invalid)), productID: product.id)
        }
        var invalidProduct = product
        invalidProduct.source = "file:///private"
        #expect(throws: FittingLibraryError.self) { try room.saveProduct(invalidProduct) }
        #expect(room.library.products == before)
        let extra = ProductSize(label: "100 / Regular", measurements: .shortSleeve(.medium))
        try room.saveSize(extra, productID: product.id)
        #expect(room.product?.sizes.last?.label == "100 / Regular")
    }

    @Test func deletionClearsOnlyMatchingSelectionsAndDoesNotReseedOnRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let product = try #require(room.product)
        let selected = try #require(room.selectedSize)
        try room.deleteSize(selected.id, productID: product.id)
        #expect(room.selectedSize == nil)
        #expect(room.library.selectedProductID == product.id)
        #expect(room.product?.sizes.count == product.sizes.count - 1)
        try room.deleteProduct(product.id)
        #expect(room.library.selectedProductID == nil)
        #expect(room.definition == nil)
        #expect(fixture.room().library.products.isEmpty)
    }

    @Test func newProductsValidateTheirInitialSizesBeforeWriting() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let template = try #require(room.catalog.first)
        var product = GarmentProduct(name: "새 상품", templateID: template.pattern.id, sizes: [
            ProductSize(label: "M", measurements: .shortSleeve(.medium)),
            ProductSize(label: " m ", measurements: .shortSleeve(.large))
        ])
        let before = room.library.products
        #expect(throws: FittingLibraryError.self) { try room.saveProduct(product) }
        product.sizes = [ProductSize(label: "95")]
        #expect(throws: FittingLibraryError.self) { try room.saveProduct(product) }
        #expect(room.library.products == before)
        product.sizes = [ProductSize(label: " 95 ", measurements: .shortSleeve(.medium))]
        try room.saveProduct(product)
        #expect(room.library.products.last?.sizes.first?.label == "95")
    }

    @Test func missingSelectedLegacyModelStaysRecordedButCannotBeFitted() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        var legacy = FittingSession()
        legacy.garmentID = "removed-model"
        fixture.defaults.set(try JSONEncoder().encode(legacy), forKey: "editorialFittingSession")
        let room = fixture.room()
        let product = try #require(room.product)
        var size = try #require(room.selectedSize)
        #expect(product.templateID == "unavailable-removed-model")
        #expect(size.input == nil)
        #expect(room.definition == nil)
        #expect(room.fittingUnavailableReason != nil)
        let before = room.library.products
        size.measurements = .shortSleeve(.medium)
        #expect(throws: FittingLibraryError.self) {
            try room.saveSize(size, productID: product.id, select: true)
        }
        #expect(room.library.products == before)
        try room.saveSize(size, productID: product.id)
        #expect(room.selectedSize?.input == .medium)
        #expect(fixture.room().definition == nil)
    }

    @Test func legacySlotsArePreservedIndependentlyWithoutGuessingProductGroups() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let definitions = GarmentCatalog.samples.filter { $0.kind == .shortSleeveTShirt }
        let first = try #require(definitions.first)
        let last = try #require(definitions.last)
        var legacy = FittingSession()
        legacy.body.height = 182
        legacy.body.measuredFields = [.height]
        legacy.base = .female
        legacy.garmentID = last.id
        var custom = GarmentSizeInput.large
        custom.hemWidth = 59
        custom.sleeveOpeningWidth = 19
        custom.armhole = 24
        custom.fabric = GarmentFabricSettings()
        legacy.sizes = [first.id: .small, last.id: custom, "removed-model": .medium]
        let info = GarmentProductInfo(name: "같은 이름", source: "https://example.com/shirt", sizeLabel: "100")
        legacy.products = [first.id: info, last.id: info]
        let data = try JSONEncoder().encode(legacy)
        fixture.defaults.set(data, forKey: "editorialFittingSession")

        let room = fixture.room()
        #expect(room.isLoaded)
        #expect(room.profile?.base == .female)
        #expect(room.profile?.body.height == 182)
        #expect(room.profile?.body.measuredFields == [.height])
        #expect(room.library.products.filter { $0.name == info.name }.count == 2)
        #expect(room.selectedSize?.input == custom)
        #expect(room.product?.source == info.source)
        #expect(room.definition?.pattern.dimensions == custom.specification)
        let unavailable = try #require(room.library.products.first { $0.id == "migrated-removed-model" })
        #expect(unavailable.sizes.first?.input == .medium)
        #expect(unavailable.template(in: room.catalog) == nil)
        #expect(fixture.defaults.data(forKey: "editorialFittingSession") == data)
        #expect(fixture.room().library.products == room.library.products)
    }

    @Test func oldestMeasurementStoreMigratesWithoutInventingAPersonalBody() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let definition = try #require(GarmentCatalog.samples.first)
        let data = try JSONEncoder().encode([definition.id: GarmentSizeInput.large])
        fixture.defaults.set(data, forKey: "primaryGarmentSizes")
        let room = fixture.room()
        #expect(room.isLoaded)
        #expect(room.needsSetup)
        #expect(room.library.products.first { $0.id == "migrated-\(definition.id)" }?.sizes.first?.input == .large)
        #expect(fixture.defaults.data(forKey: "primaryGarmentSizes") == data)
    }

    @Test func corruptLegacyAndCurrentFilesAreNotReplacedByDefaults() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let badData = Data("not-json".utf8)
        fixture.defaults.set(badData, forKey: "editorialFittingSession")
        let failedMigration = fixture.room()
        #expect(!failedMigration.isLoaded)
        #expect(failedMigration.loadError != nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.file.path))
        #expect(fixture.defaults.data(forKey: "editorialFittingSession") == badData)
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        try badData.write(to: fixture.file)
        let failedRead = fixture.room()
        #expect(!failedRead.isLoaded)
        #expect(throws: FittingLibraryError.self) {
            try failedRead.addProfile(BodyProfile(name: "새 체형", body: UserBody(), base: .male), activate: true)
        }
        #expect(try Data(contentsOf: fixture.file) == badData)
    }

    @Test func failedAtomicWriteDoesNotPublishASuccessOrMutateTheLibrary() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let room = fixture.room()
        let profile = BodyProfile(name: "기존 체형", body: UserBody(), base: .male)
        try room.addProfile(profile, activate: true)
        let revision = room.saveRevision
        try FileManager.default.removeItem(at: fixture.file)
        try FileManager.default.createDirectory(at: fixture.file, withIntermediateDirectories: false)
        var edited = profile
        edited.name = "저장되지 않는 이름"
        #expect(throws: (any Error).self) { try room.updateProfile(edited) }
        #expect(room.profile?.name == profile.name)
        #expect(room.saveRevision == revision)
        #expect(room.statusMessage == nil)
    }

    @Test func unsupportedVersionAndBrokenReferencesAreExplicitErrors() throws {
        var library = FittingLibrary()
        library.version = 99
        #expect(throws: FittingLibraryError.self) { try library.validateReferences() }
        library.version = 1
        library.activeProfileID = "missing"
        #expect(throws: FittingLibraryError.self) { try library.validateReferences() }
        library.activeProfileID = nil
        library.selectedSizeID = "missing"
        #expect(throws: FittingLibraryError.self) { try library.validateReferences() }
    }
}
