import Foundation
import Testing
import RealityKit
import SwiftUI
import UIKit
@testable import weashion

struct EditorialDesignTests {
    @MainActor
    @Test func measurementFocusUsesTheSupportedFlatDimensionsWithoutChangingSizes() {
        let size = GarmentSizeInput.medium
        #expect(GarmentPlateMeasurement.allCases.map(\.number) == ["1", "2", "3", "4"])
        #expect(GarmentPlateMeasurement.length.value(in: size) == size.length)
        #expect(GarmentPlateMeasurement.shoulder.value(in: size) == size.shoulderWidth)
        #expect(GarmentPlateMeasurement.chest.value(in: size) == size.chestWidth)
        #expect(GarmentPlateMeasurement.sleeve.value(in: size) == size.sleeveLength)
        #expect(Set(GarmentPlateMeasurement.allCases.map(\.title)).count == 4)
        #expect(size == .medium)
    }

    @Test func editorialEntrancesHaveVisibleTravelAndBoundedBackgroundParallax() {
        #expect(EditorialMotion.revealOffset == 48)
        #expect((0.15...0.25).contains(EditorialMotion.revealThreshold))
        #expect(EditorialMotion.offset(from: .leading, distance: 64, revealed: false) == CGSize(width: -64, height: 0))
        #expect(EditorialMotion.offset(from: .trailing, distance: 48, revealed: false) == CGSize(width: 48, height: 0))
        #expect(EditorialMotion.offset(from: .top, distance: 110, revealed: false) == CGSize(width: 0, height: -110))
        #expect(EditorialMotion.offset(from: .bottom, distance: 110, revealed: false) == CGSize(width: 0, height: 110))
        for edge in [Edge.top, .bottom, .leading, .trailing] {
            #expect(EditorialMotion.offset(from: edge, distance: 110, revealed: true) == .zero)
        }
        #expect(EditorialMotion.parallaxOffset(minY: -10_000, limit: 16) == 16)
        #expect(EditorialMotion.parallaxOffset(minY: 10_000, limit: 16) == -16)
        #expect(EditorialMotion.parallaxOffset(minY: 100, limit: 16) == -8)
        #expect(EditorialMotion.parallaxOffset(minY: .infinity, limit: 16) == 0)
    }

    @MainActor
    @Test func editorialSceneContinuityRetainsOneRenderSurfaceAndTheUserViewpoint() {
        let link = EditorialSceneLink()
        #expect(link.pose == EditorialScenePose())
        link.pose.rotation = 0.75
        link.pose.zoom = 2
        link.pose.focus = SIMD3<Float>(0.1, 0.2, 0)
        #expect(link.pose.rotation == 0.75)
        #expect(link.pose.zoom == 2)
        #expect(link.pose.focus == SIMD3<Float>(0.1, 0.2, 0))
        link.pose = EditorialScenePose()
        #expect(link.pose.zoom == 1)
        let surface = link.renderSurface()
        #expect(link.renderSurface() === surface)
        #expect(link.surfaceCreationCount == 1)
        #expect(link.fitting !== link.body)
    }

    @MainActor
    @Test func warmPagePreparationReusesBodyGarmentAndNativeGeometry() async throws {
        let link = EditorialSceneLink()
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        let heartbeat = Task { @MainActor in ContinuousClock.now }
        let started = ContinuousClock.now
        try await link.fitting.prepare(request, bodyOnly: false)
        let heartbeatDelay = started.duration(to: await heartbeat.value)
        print("TRANSITION_MAIN_ACTOR_HEARTBEAT \(heartbeatDelay)")
        #expect(heartbeatDelay < .milliseconds(100))
        let revision = link.fitting.mannequin.surfaceRevision
        let definition = try #require(GarmentCatalog.samples.first)
        let garment = link.fitting.garment
        garment.update(definition: definition, mannequin: link.fitting.mannequin)
        for _ in 0..<500 where garment.isSettling {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!garment.isSettling)
        let model = try #require(garment.root.children.first)
        let surface = link.renderSurface()
        surface.activate(link.fitting.native)
        let root = Entity()
        root.addChild(link.fitting.mannequin.root)
        root.addChild(garment.root)
        surface.sourceRoot = root
        surface.synchronize()
        let geometryCount = link.fitting.native.geometryBuildCount
        #expect(geometryCount > 0)
        let warmStarted = ContinuousClock.now
        for _ in 0..<20 {
            try await link.fitting.prepare(request, bodyOnly: false)
            garment.update(definition: definition, mannequin: link.fitting.mannequin)
            #expect(link.renderSurface() === surface)
            surface.synchronize()
        }
        print("TRANSITION_WARM_20 \(warmStarted.duration(to: .now))")
        #expect(link.fitting.mannequin.surfaceRevision == revision)
        #expect(garment.settlementRequestCount == 1)
        #expect(garment.root.children.first === model)
        #expect(link.fitting.native.geometryBuildCount == geometryCount)
        #expect(link.surfaceCreationCount == 1)
        link.cancelPreparation()
    }

    @MainActor
    @Test func memoryPressureReleasesOnlyTheInactiveSceneAndAllowsRepreparation() async throws {
        let link = EditorialSceneLink()
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        try await link.fitting.prepare(request, bodyOnly: false)
        let active = link.fitting
        let revision = active.mannequin.surfaceRevision
        let surface = link.renderSurface()
        weak var previousBody = link.body
        weak var previousNative = link.body.native
        surface.activate(link.body.native)
        link.releaseInactiveResources(keepingBody: false)
        #expect(previousBody == nil)
        #expect(previousNative == nil)
        #expect(link.fitting === active)
        #expect(link.fitting.mannequin.surfaceRevision == revision)
        #expect(link.fitting.preparedRequest == request)
        try await link.body.prepare(request, bodyOnly: true)
        #expect(link.body.preparedRequest == request)
        #expect(link.renderSurface() === surface)
        link.cancelPreparation()
    }

    @MainActor
    @Test func bodyPreparationCanRebuildAfterCacheRelease() async throws {
        let worker = BodyPreviewRenderer()
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        _ = try await worker.prepareFitting(request)
        await worker.releaseCachedResources()
        _ = try await worker.prepareFitting(request)
        #expect(await worker.fittingPreparationCount == 2)
    }

    @MainActor
    @Test func preparedBodyCacheInvalidatesForChangedMeasurements() async throws {
        let worker = BodyPreviewRenderer()
        let first = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        _ = try await worker.prepareFitting(first)
        _ = try await worker.prepareFitting(first)
        #expect(await worker.fittingPreparationCount == 1)
        var body = UserBody()
        body.height += 1
        _ = try await worker.prepareFitting(.init(body: body, base: .male))
        #expect(await worker.fittingPreparationCount == 2)
    }

    @MainActor
    @Test func fastPageTransitionsDoNotWaitForPreviewAnimation() async throws {
        let transition = EditorialPageTransition()
        transition.show(.fitting, reduceMotion: false) {}
        try await Task.sleep(for: .milliseconds(40))
        #expect(transition.displayed == .fitting)
        #expect(transition.requested == nil)
        #expect(!transition.showsPreview)
        transition.cancel()
    }

    @MainActor
    @Test func slowPageTransitionsPreviewOnlyTheLatestRequest() async throws {
        let transition = EditorialPageTransition()
        transition.show(.fitting, reduceMotion: false) {
            try await Task.sleep(for: .milliseconds(400))
        }
        #expect(transition.requested == .fitting)
        #expect(transition.displayed == .today)
        #expect(!transition.showsPreview)
        try await Task.sleep(for: .milliseconds(180))
        #expect(transition.showsPreview)
        transition.show(.body, reduceMotion: false) {}
        try await Task.sleep(for: .milliseconds(40))
        #expect(transition.displayed == .body)
        #expect(!transition.showsPreview)
        try await Task.sleep(for: .milliseconds(300))
        #expect(transition.displayed == .body)
        transition.cancel()
    }

    @MainActor
    @Test func pagePreparationCanReturnToCurrentPageOrReportFailure() async throws {
        let transition = EditorialPageTransition()
        transition.show(.fitting, reduceMotion: true) {
            try await Task.sleep(for: .milliseconds(400))
        }
        transition.show(.today, reduceMotion: true) {}
        try await Task.sleep(for: .milliseconds(150))
        #expect(transition.displayed == .today)
        #expect(transition.requested == nil)
        #expect(!transition.showsPreview)
        transition.show(.body, reduceMotion: true) {
            throw BodyPreviewRenderer.PreparationError.invalidBody
        }
        try await Task.sleep(for: .milliseconds(40))
        #expect(transition.displayed == .today)
        #expect(transition.errorMessage != nil)
        #expect(transition.requested == nil)
        #expect(!transition.showsPreview)
        transition.cancel()
    }

    @Test func sizeComparisonsUseSignedFlatMeasurementsAndRejectUnmeasuredSizes() throws {
        let medium = ProductSize(label: "M", measurements: .shortSleeve(.medium))
        let large = ProductSize(label: "L", measurements: .shortSleeve(.large))
        let increase = try #require(GarmentSizeComparison(previous: medium, current: large))
        #expect(increase.length == GarmentSizeInput.large.length - GarmentSizeInput.medium.length)
        #expect(increase.shoulderWidth == GarmentSizeInput.large.shoulderWidth - GarmentSizeInput.medium.shoulderWidth)
        #expect(increase.chestWidth == GarmentSizeInput.large.chestWidth - GarmentSizeInput.medium.chestWidth)
        let decrease = try #require(GarmentSizeComparison(previous: large, current: medium))
        #expect(decrease.length == -increase.length)
        #expect(decrease.chestWidth == -increase.chestWidth)
        #expect(GarmentSizeComparison(previous: medium, current: medium) == nil)
        #expect(GarmentSizeComparison(previous: medium, current: ProductSize(label: "L")) == nil)
        var invalid = GarmentSizeInput.medium
        invalid.chestWidth = 0
        #expect(GarmentSizeComparison(previous: medium,
                                     current: ProductSize(label: "X", measurements: .shortSleeve(invalid))) == nil)
    }

    @MainActor
    @Test func editorialMotionRespectsReducedMotion() {
        #expect(EditorialMotion.transition(reduceMotion: true) == nil)
        #expect(EditorialMotion.transition(reduceMotion: false) != nil)
        #expect(EditorialMotion.feedback(reduceMotion: true) == nil)
        #expect(EditorialMotion.feedback(reduceMotion: false) != nil)
        #expect((0.08...0.12).contains(EditorialMotion.pressDuration))
        #expect((0.18...0.22).contains(EditorialMotion.transitionDuration))
        #expect((0.15...0.18).contains(EditorialMotion.feedbackDuration))
        #expect((0.6...0.8).contains(EditorialMotion.titleDuration))
        #expect((0.08...0.12).contains(EditorialMotion.titleStagger))
        #expect((0.4...0.6).contains(EditorialMotion.pageDuration))
        #expect((0.8...1.0).contains(EditorialMotion.entranceDuration))
        #expect((0.95...0.98).contains(EditorialMotion.pressScale))
        #expect((0.25...0.35).contains(EditorialMotion.glyphDuration))
        #expect(EditorialMotion.page(reduceMotion: true) == nil)
        #expect(EditorialLayout.minimumControlSize >= 44)
    }

    @MainActor
    @Test func bundledEditorialTypefacesRegisterWithOpticalSizing() {
        #expect(EditorialFonts.register())
        #expect(EditorialFonts.isAvailable)
        for name in [EditorialFonts.displayName, EditorialFonts.displayItalicName,
                     EditorialFonts.hangulName, EditorialFonts.hangulBoldName] {
            #expect(UIFont(name: name, size: 20) != nil, "\(name) should be registered from the bundle")
        }
        #expect(EditorialFonts.opticalSize(for: 2) == 6)
        #expect(EditorialFonts.opticalSize(for: 48) == 48)
        #expect(EditorialFonts.opticalSize(for: 150) == 96)
        let licenses = ["OFL-BodoniModa", "OFL-NanumMyeongjo", "OFL-Pretendard"].compactMap {
            Bundle.main.url(forResource: $0, withExtension: "txt")
        }
        #expect(licenses.count == 3)
    }

    @MainActor
    @Test func functionalSansPairsHelveticaNeueWithPretendardForHangul() throws {
        #expect(EditorialFonts.register())
        #expect(EditorialFonts.sansIsAvailable)
        #expect(UIFont(name: EditorialFonts.sansName, size: 15) != nil)
        let regular = EditorialFonts.sansUIFont(size: 15)
        #expect(regular.fontName == "HelveticaNeue")
        #expect(EditorialFonts.sansUIFont(size: 15, weight: .medium).fontName == "HelveticaNeue-Medium")
        let cascade = try #require(regular.fontDescriptor.fontAttributes[
            UIFontDescriptor.AttributeName(rawValue: kCTFontCascadeListAttribute as String)
        ] as? [UIFontDescriptor])
        #expect(cascade.first?.fontAttributes[.name] as? String == EditorialFonts.sansName)
        #expect(EditorialFonts.sansWeightValue(for: .medium) == 500)
        #expect(EditorialFonts.sansWeightValue(for: .semibold) == 600)
        let large = EditorialFonts.pointSize(for: .body, dynamicTypeSize: .large)
        #expect(large == 17)
        #expect(EditorialFonts.pointSize(for: .body, dynamicTypeSize: .accessibility3) > large)
        #expect(EditorialFonts.pointSize(for: .caption2, dynamicTypeSize: .large) == 11)
    }

    @MainActor
    @Test func interactiveCoverReservesRoomForProductSizeAndAction() {
        #expect(EditorialLayout.coverHeight(viewportHeight: 852, wide: false) == 500)
        #expect(EditorialLayout.coverHeight(viewportHeight: 500, wide: false) == 280)
        #expect(EditorialLayout.coverHeight(viewportHeight: 852, wide: false)
                > EditorialLayout.stageHeight(viewportHeight: 852, wide: false))
        #expect(EditorialLayout.coverHeight(viewportHeight: 1100, wide: true) == 660)
        let heights: [CGFloat] = [390, 500, 700, 852, 1100]
        for height in heights {
            #expect((280...500).contains(EditorialLayout.coverHeight(viewportHeight: height, wide: false)))
            #expect((440...660).contains(EditorialLayout.coverHeight(viewportHeight: height, wide: true)))
        }
        #expect(EditorialLayout.margin(wide: false) == 20)
        #expect(EditorialLayout.margin(wide: true) == 48)
    }

    @MainActor
    @Test func lightPaletteUsesTheApprovedColorsAndReadableTextPairs() throws {
        let tokens: [(Color, [Double])] = [
            (Editorial.paper, [250, 249, 246]), (Editorial.ink, [32, 43, 48]),
            (Editorial.accent, [159, 53, 72]), (Editorial.stock, [234, 231, 224]),
            (Editorial.studio, [236, 237, 234]), (Editorial.muted, [98, 107, 103])
        ]
        for (color, expected) in tokens {
            let rgba = try components(color)
            for (actual, byte) in zip(rgba.rgb, expected) {
                #expect(abs(actual - byte / 255) < 0.001)
            }
            #expect(rgba.alpha == 1)
        }
        for foreground in [Editorial.ink, Editorial.accent, Editorial.warning, Editorial.error] {
            for background in [Editorial.paper, Editorial.studio, Editorial.stock] {
                #expect(try contrast(foreground, on: background) >= 4.5)
            }
        }
        for background in [Editorial.paper, Editorial.studio, Editorial.stock.opacity(0.4),
                           Editorial.ink.opacity(0.04), Editorial.warning.opacity(0.04), Editorial.error.opacity(0.04)] {
            #expect(try contrast(Editorial.muted, on: background) >= 4.5)
        }
        #expect(try contrast(Editorial.accent, on: Editorial.accent.opacity(0.07)) >= 4.5)
        #expect(try contrast(Editorial.paper, on: Editorial.accent) >= 4.5)
    }

    @MainActor
    @Test func oneFeedbackEventSeparatesSelectionFromSuccessfulPersistence() {
        let previous = EditorialFeedbackTrigger(saveRevision: 3, selection: ["today", "body-a", "product-a", "size-m"])
        #expect(previous.kind(since: previous) == nil)
        let selected = EditorialFeedbackTrigger(saveRevision: 3, selection: ["fitting", "body-a", "product-a", "size-l"])
        #expect(selected.kind(since: previous) == .selection)
        let saved = EditorialFeedbackTrigger(saveRevision: 4, selection: selected.selection)
        #expect(saved.kind(since: previous) == .success)
        let activated = EditorialFeedbackTrigger(saveRevision: 3, selection: ["today", "body-b", "product-a", "size-m"])
        #expect(activated.kind(since: previous) == .selection)
        let anotherProduct = EditorialFeedbackTrigger(saveRevision: 3, selection: ["today", "body-a", "product-b", "size-m"])
        #expect(anotherProduct.kind(since: previous) == .selection)
    }

    @MainActor
    @Test func sceneFeedbackNamesTheRequestedSizeAndNeverInventsAFitVerdict() {
        let cancelled = EditorialSceneStatus.resolve(sizeLabel: "M", cancelled: true, hasVisibleGarment: true)
        #expect(cancelled == .cancelled)
        #expect(cancelled.title == L("착장 계산을 취소했어요"))
        #expect(cancelled.isProblem)
        #expect(cancelled.tone == .information)
        #expect(EditorialSceneStatus.resolve(bodyPreview: true, cancelled: true) == .bodyReference)
        let updating = EditorialSceneStatus.resolve(updating: true, sizeLabel: "L",
                                                   garmentMessage: "이전 계산의 안내", hasVisibleGarment: true)
        #expect(updating == .updating("L"))
        #expect(updating.title == L("\("L") 사이즈 착장 계산 중"))
        #expect(updating.title.contains("L"))
        #expect(updating.tone == .progress)
        #expect(EditorialSceneStatus.resolve(sizeLabel: "L").tone == .information)
        #expect(EditorialSceneStatus.resolve() == .undressed)
        #expect(EditorialSceneStatus.resolve(bodyPreview: true, updating: true, sizeLabel: "M") == .bodyReference)
        #expect(!EditorialSceneStatus.resolve(sizeLabel: "L").isProblem)
        #expect(!EditorialSceneStatus.resolve().isProblem)
        #expect(updating.isProblem)
        #expect(EditorialSceneStatus.resolve(sizeLabel: "M", garmentMessage: "주의", hasVisibleGarment: true).isProblem)
    }

    @MainActor
    @Test func warningsUseTheRenderedGarmentStateAndKeepTheOriginalReason() {
        let message = "일부 영역에 겹침이 남아 있습니다"
        let warning = EditorialSceneStatus.resolve(sizeLabel: "M", garmentMessage: message, hasVisibleGarment: true)
        let failure = EditorialSceneStatus.resolve(sizeLabel: "M", garmentMessage: message, hasVisibleGarment: false)
        #expect(warning == .warning(message))
        #expect(warning.tone == .warning)
        #expect(warning.detail == message)
        #expect(failure == .failure(message))
        #expect(failure.tone == .error)
        let bodyFailure = EditorialSceneStatus.resolve(bodyError: "체형 로딩 오류", updating: true, sizeLabel: "M")
        #expect(bodyFailure == .failure("체형 로딩 오류"))
        #expect(bodyFailure.detail == "체형 로딩 오류")
    }

    @MainActor
    @Test func editorialTitleMotionIsOptionalForAccessibility() {
        #expect(EditorialMotion.allowsTitleMotion(reduceMotion: false, voiceOver: false, accessibility: false))
        #expect(!EditorialMotion.allowsTitleMotion(reduceMotion: true, voiceOver: false, accessibility: false))
        #expect(!EditorialMotion.allowsTitleMotion(reduceMotion: false, voiceOver: true, accessibility: false))
        #expect(!EditorialMotion.allowsTitleMotion(reduceMotion: false, voiceOver: false, accessibility: true))
    }

    @MainActor
    @Test func editorialSpreadsReflowAtTheContentWidthBoundary() {
        #expect(!EditorialLayout.usesColumns(width: 699, accessibility: false))
        #expect(EditorialLayout.usesColumns(width: 700, accessibility: false))
        #expect(!EditorialLayout.usesColumns(width: 1200, accessibility: true))
    }

    @MainActor
    @Test func editorialStagesReserveSpaceForTheCoverAndControls() {
        #expect(EditorialLayout.stageHeight(viewportHeight: 760, wide: false) == 330)
        #expect(EditorialLayout.stageHeight(viewportHeight: 390, wide: false) == 280)
        #expect(EditorialLayout.stageHeight(viewportHeight: 1100, wide: false) == 440)
        #expect(EditorialLayout.stageHeight(viewportHeight: 760, wide: true) == 400)
        #expect(EditorialLayout.stageHeight(viewportHeight: 1100, wide: true) == 600)
    }

    @MainActor
    @Test func pendingGarmentsStayHiddenDuringRepeatedAndSupersedingUpdates() async throws {
        let definition = try #require(GarmentCatalog.samples.first)
        let nextDefinition = try #require(GarmentCatalog.samples.last)
        let mannequin = WEASHIONMannequin()
        let preparationStarted = ContinuousClock.now
        try await mannequin.prepareFitting(.init(body: UserBody(), base: .male))
        print("TRANSITION_BODY_ASYNC \(preparationStarted.duration(to: .now))")
        #expect(mannequin.loadError == nil)
        let bodyRequest = mannequin.garmentBodyRequest
        let controller = GarmentController()
        defer { controller.cancelSettling() }
        controller.root.addChild(Entity())
        controller.root.isEnabled = true

        controller.update(definition: definition, mannequin: mannequin)
        let revision = controller.surfaceRevision
        #expect(controller.isSettling)
        #expect(!controller.root.isEnabled)
        #expect(controller.fitSummary == nil)
        controller.update(definition: definition, mannequin: mannequin)
        #expect(controller.surfaceRevision == revision)
        #expect(!controller.root.isEnabled)
        controller.update(definition: nextDefinition, mannequin: mannequin)
        #expect(controller.surfaceRevision > revision)
        #expect(controller.isSettling)
        #expect(!controller.root.isEnabled)
        #expect(mannequin.garmentBodyRequest == bodyRequest)

        controller.update(definition: nil, mannequin: mannequin)
        #expect(!controller.isSettling)
        #expect(!controller.root.isEnabled)
        #expect(controller.root.children.isEmpty)
        #expect(controller.fitSummary == nil)
    }

    @Test func productLinksOnlyAcceptWebURLs() {
        for source in ["https://shop.example.com/product/123", "http://example.com", ""] {
            #expect(GarmentProductInfo(source: source).hasValidSource)
        }
        for source in ["example.com", "javascript:alert(1)", "file:///tmp/image.png", "https://"] {
            #expect(!GarmentProductInfo(source: source).hasValidSource)
        }
    }

    @Test func flatMeasurementsConvertToCircumferences() {
        let size = GarmentSizeInput(length: 70, shoulderWidth: 48, chestWidth: 55, sleeveLength: 22)
        #expect(size.isValid && size.specification.isValid)
        #expect(abs(size.specification.chestCircumference - 1.10) < 0.0001)
        #expect(abs(size.specification.length - 0.70) < 0.0001)
        var invalid = size
        invalid.chestWidth = 0
        #expect(!invalid.isValid)
        invalid = size
        invalid.armhole = 45
        invalid.length = 20
        #expect(!invalid.specification.isValid)
    }

    @Test func magazineSizeNotesUseTheSameCentimeterValuesAsTheFittingRoom() throws {
        let expected: [String: GarmentSizeInput] = ["S": .small, "M": .medium, "L": .large]
        let shirts = GarmentCatalog.samples.filter { $0.kind == .shortSleeveTShirt }
        #expect(shirts.count == expected.count)
        for definition in shirts {
            let dimensions = try #require(definition.pattern.dimensions)
            let input = GarmentSizeInput(dimensions: dimensions)
            #expect(input == (try #require(expected[definition.selectionLabel])))
            #expect(input.isValid)
            #expect(abs(input.length / 100 - Double(dimensions.length)) < 0.00001)
            #expect(abs(input.shoulderWidth / 100 - Double(dimensions.shoulderWidth)) < 0.00001)
            #expect(abs(input.chestWidth / 50 - Double(dimensions.chestCircumference)) < 0.00001)
            #expect(abs(input.sleeveLength / 100 - Double(dimensions.sleeveLength)) < 0.00001)
            #expect(input.hemWidth == nil)
            #expect(input.sleeveOpeningWidth == nil)
            #expect(input.armhole == nil)
            #expect(input.fabric == nil)
        }
    }

    @Test func weatherBackdropTracksConditions() {
        #expect(WeatherInfo(condition: "Clear").mood == .clear)
        #expect(WeatherInfo(condition: "Partly Cloudy").mood == .cloud)
        #expect(WeatherInfo(condition: "Rain").mood == .rain)
        #expect(WeatherInfo(condition: "Snow").mood == .snow)
        #expect(WeatherInfo(condition: "Thunderstorms").mood == .rain)
    }

    @Test func weatherEditionsChangeTheCoverAndTheSampleOutfit() {
        #expect(WeatherMood.rain.prefersInvertedCover)
        for mood in [WeatherMood.clear, .cloud, .snow] { #expect(!mood.prefersInvertedCover) }
        for mood in WeatherMood.allCases {
            #expect(WeatherInfo.sample(for: mood).mood == mood)
        }
        #expect(WeatherInfo.sample(for: .cloud).condition == WeatherInfo.sample.condition)
        #expect(OutfitRecommendation.recommend(weather: .sample(for: .snow)).outer == "Heavy Coat")
        #expect(OutfitRecommendation.recommend(weather: .sample(for: .clear)).outer == nil)
        #expect(OutfitRecommendation.recommend(weather: .sample(for: .rain)).outer == "Rain Jacket")
    }

    @Test func weatherMoodMatchesLocalizedConditionNames() {
        var info = WeatherInfo.sample
        for (condition, mood) in [("曇り", WeatherMood.cloud), ("雨", .rain), ("雪", .snow), ("흐림", .cloud), ("비", .rain), ("Snow", .snow)] {
            info.condition = condition
            #expect(info.mood == mood, "\(condition)")
        }
    }

    @Test func everyShippedLanguageCompilesTheSameStringTable() throws {
        var tables: [String: [String: String]] = [:]
        for code in ["ko", "en", "ja"] {
            let url = try #require(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(code).lproj"),
                                   "missing \(code) table")
            let data = try Data(contentsOf: url)
            let table = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            tables[code] = table
            #expect(table.count > 500, "\(code) has \(table.count) strings")
            #expect(table.values.allSatisfy { !$0.isEmpty }, "\(code) has empty translations")
        }
        #expect(Set(tables["en"]!.keys) == Set(tables["ko"]!.keys))
        #expect(Set(tables["ja"]!.keys) == Set(tables["ko"]!.keys))
        // Format specifiers must line up so interpolated strings cannot crash or garble in any language.
        let specifier = try Regex("%(?:\\d+\\$)?[-+ 0#]*\\d*(?:\\.\\d+)?(?:hh|h|ll|l|L|q|z|t|j)?[@diuxXofFeEgGcsSpaA]")
        for (key, korean) in tables["ko"]! {
            let source = korean.replacing("%%", with: "")
            let expected = source.matches(of: specifier).map { String(source[$0.range]) }
            for code in ["en", "ja"] {
                let translated = tables[code]![key]!.replacing("%%", with: "")
                let found = translated.matches(of: specifier).map { String(translated[$0.range]) }
                #expect(found == expected, "\(code): \(key)")
            }
        }
        let infoPlist = try #require(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: "ja.lproj"))
        #expect(FileManager.default.fileExists(atPath: infoPlist.path))
    }

    @MainActor @Test func pinnedLanguageDrivesModelStringsAndRestoresTheSystemDefault() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.key)
        defer {
            if let previous { defaults.set(previous, forKey: AppLanguage.key) } else { defaults.removeObject(forKey: AppLanguage.key) }
        }
        defaults.set(AppLanguage.en.rawValue, forKey: AppLanguage.key)
        #expect(L10n.locale.language.languageCode?.identifier == "en")
        #expect(WeatherMood.rain.title == "Rain")
        #expect(GarmentKind.knitwear.title == "Knitwear")
        #expect(L("\("M") 사이즈") == "Size M")
        defaults.set(AppLanguage.ja.rawValue, forKey: AppLanguage.key)
        #expect(WeatherMood.snow.title == "雪")
        #expect(L("\("M") 사이즈") == "サイズ M")
        defaults.set(AppLanguage.ko.rawValue, forKey: AppLanguage.key)
        #expect(WeatherMood.cloud.title == "흐림")
        defaults.removeObject(forKey: AppLanguage.key)
        #expect(L10n.override == nil)
        #expect(L10n.bundle == .main)
        #expect(AppLanguage.ko.title == "한국어" && AppLanguage.en.title == "English" && AppLanguage.ja.title == "日本語")
    }

    @MainActor
    private func components(_ color: Color) throws -> (rgb: [Double], alpha: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        try #require(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return ([Double(red), Double(green), Double(blue)], Double(alpha))
    }

    @MainActor
    private func contrast(_ foreground: Color, on background: Color) throws -> Double {
        let paper = try components(Editorial.paper)
        let bg = try components(background)
        let fg = try components(foreground)
        let surface = zip(bg.rgb, paper.rgb).map { $0 * bg.alpha + $1 * (1 - bg.alpha) }
        let text = zip(fg.rgb, surface).map { $0 * fg.alpha + $1 * (1 - fg.alpha) }
        func luminance(_ channels: [Double]) -> Double {
            let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let values = [luminance(surface), luminance(text)]
        return (max(values[0], values[1]) + 0.05) / (min(values[0], values[1]) + 0.05)
    }
}
