import XCTest

final class weashionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(setup: Bool = true, previewWeather: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WEASHION_UI_TEST_LIBRARY"] = UUID().uuidString
        app.launchEnvironment["WEASHION_UI_TEST_RESET_LANGUAGE"] = "1"
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if let previewWeather { app.launchArguments += ["-previewWeatherMood", previewWeather] }
        app.launch()
        if setup { finishSetup(app) }
        return app
    }

    @MainActor
    private func finishSetup(_ app: XCUIApplication, base: String = "male", height: String = "175", weight: String = "70") {
        let choice = app.buttons["setup-base-\(base)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        reveal(choice, in: app)
        choice.tap()
        app.buttons["setupNext"].tap()
        replaceText(of: app.textFields["setup-height"], with: height, in: app)
        app.buttons["입력 완료"].tap()
        replaceText(of: app.textFields["setup-weight"], with: weight, in: app)
        app.buttons["입력 완료"].tap()
        app.buttons["setupNext"].tap()
        app.buttons["setupNext"].tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let navigation = app.buttons["tab-today"]
        let page = app.scrollViews["editorialPageScroll"]
        func visibleTop() -> CGFloat {
            let feedback = app.otherElements["savedFeedback"]
            return feedback.exists && feedback.isHittable
                ? max(page.frame.minY, feedback.frame.maxY)
                : page.frame.minY
        }
        func fullyReachable() -> Bool {
            guard element.exists, element.isHittable else { return false }
            guard navigation.exists, navigation.isHittable, page.exists else { return true }
            return element.frame.minY >= visibleTop() + 8
                && element.frame.maxY <= min(page.frame.maxY, navigation.frame.minY - 12)
        }
        if navigation.exists, navigation.isHittable, page.exists {
            for _ in 0..<16 {
                if fullyReachable() { return }
                let upwards = !element.exists
                    || element.frame.maxY > min(page.frame.maxY, navigation.frame.minY - 12)
                page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.65 : 0.35))
                    .press(forDuration: 0.05, thenDragTo:
                        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.35 : 0.65)))
            }
            XCTAssertTrue(fullyReachable(), "The whole control must be inside the scroll viewport before tapping.")
            return
        }
        for _ in 0..<8 {
            if fullyReachable() { return }
            app.swipeUp()
        }
        for _ in 0..<8 {
            if fullyReachable() { return }
            app.swipeDown()
        }
        XCTAssertTrue(fullyReachable(), "The whole control must be inside the scroll viewport before tapping.")
    }

    /// Taps the trailing end of a field so the caret lands after existing text (fields are right-aligned),
    /// then gives the sheet and keyboard a moment to settle before typing.
    @MainActor
    private func focus(_ field: XCUIElement, in app: XCUIApplication) {
        reveal(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let editor = app.scrollViews["garmentEditorScroll"]
        if editor.exists {
            for _ in 0..<12 {
                let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
                let save = app.buttons["applyGarmentMeasurements"]
                let bottom = min(keyboardTop, save.frame.minY) - 24
                let top = editor.frame.minY + 40
                if field.frame.minY >= top && field.frame.maxY <= bottom { break }
                let upwards = field.frame.maxY > bottom
                editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.6 : 0.3))
                    .press(forDuration: 0.05, thenDragTo:
                        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.3 : 0.6)))
            }
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    @MainActor
    private func replaceText(of field: XCUIElement, with text: String, in app: XCUIApplication) {
        focus(field, in: app)
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    @MainActor
    private func openBodyEditor(_ app: XCUIApplication) {
        app.buttons["tab-body"].tap()
        let edit = app.buttons["editActiveProfile"]
        reveal(edit, in: app)
        XCTAssertTrue(edit.isHittable)
        edit.tap()
    }

    @MainActor
    private func finishBodyEditing(_ app: XCUIApplication) {
        app.buttons["saveBodyProfile"].tap()
        XCTAssertTrue(app.buttons["tab-fitting"].waitForExistence(timeout: 10))
        app.buttons["tab-fitting"].tap()
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        // Let page entrances and title reveals finish so captures show the settled layout.
        RunLoop.current.run(until: Date().addingTimeInterval(1.4))
        XCTAssertEqual(app.state, .runningForeground)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testFirstRunCreatesABodyBeforeMainNavigationAndRestoresIt() {
        let app = launch(setup: false)
        XCTAssertTrue(app.buttons["setupNext"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["setupNext"].isEnabled)
        XCTAssertFalse(app.buttons["setup-base-male"].isSelected)
        XCTAssertFalse(app.buttons["setup-base-female"].isSelected)
        capture("Editorial-BodySetup", app: app)
        finishSetup(app, base: "female", height: "168", weight: "58")
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["connectWeather"].waitForExistence(timeout: 10))
        capture("Editorial-Today", app: app)
        app.swipeUp()
        capture("Editorial-Today-Weather", app: app)
        let quickFitting = app.buttons["quickFittingRoom"]
        reveal(quickFitting, in: app)
        XCTAssertTrue(quickFitting.isHittable)
        capture("Editorial-Today-Scrolled", app: app)
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["M 사이즈"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, "168.0 cm / 58.0 kg")
        XCTAssertFalse(app.buttons["마네킹 추가"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Rotate right").count, 1)
        capture("Editorial-Fitting", app: app)
        app.swipeUp()
        capture("Editorial-Fitting-Scrolled", app: app)
        app.buttons["tab-body"].tap()
        capture("Editorial-Body-Top", app: app)
        let editProfile = app.buttons["editActiveProfile"]
        reveal(editProfile, in: app)
        XCTAssertTrue(editProfile.isHittable)
        // The stage bleeds to the trailing edge, but its caption row must stay inside the page margin.
        XCTAssertLessThanOrEqual(editProfile.frame.maxX, app.frame.maxX - 16)
        capture("Editorial-Body-Stage", app: app)
        reveal(app.buttons["내 체형과 치수 수정"], in: app)
        XCTAssertTrue(app.buttons["내 체형과 치수 수정"].isHittable)
        capture("Editorial-Body", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["setupNext"].exists)
        app.buttons["tab-fitting"].tap()
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, "168.0 cm / 58.0 kg")
    }

    @MainActor
    func testViewerControlsAndStatusStayOutsideTheRenderSurface() throws {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        let scene = app.otherElements["mannequinScene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        let originalSize = scene.frame.size
        let bodyReference = app.staticTexts["personalBodyReference"]
        let originalBody = try XCTUnwrap(bodyReference.value as? String)
        let controls = app.otherElements["sceneControls"]
        reveal(app.buttons["Reset view"], in: app)
        XCTAssertTrue(controls.exists)
        for identifier in ["Rotate left", "Rotate right", "Zoom out", "Zoom in", "Reset view"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minY, scene.frame.maxY)
        }
        let large = app.buttons["L 사이즈"]
        reveal(large, in: app)
        large.tap()
        XCTAssertTrue(large.isSelected)
        let updating = app.descendants(matching: .any).matching(identifier: "garmentUpdating").firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: updating)
        wait(for: [settled], timeout: 60)
        let status = app.otherElements["sceneStatus"]
        reveal(status, in: app)
        XCTAssertTrue(status.exists)
        XCTAssertGreaterThanOrEqual(status.frame.minY, controls.frame.maxY)
        XCTAssertEqual(scene.frame.width, originalSize.width, accuracy: 0.5)
        XCTAssertEqual(scene.frame.height, originalSize.height, accuracy: 0.5)
        XCTAssertEqual(bodyReference.value as? String, originalBody)
        XCTAssertEqual(app.buttons.matching(identifier: "Rotate right").count, 1)
    }

    @MainActor
    func testCoverEditionsFollowTheWeather() {
        for mood in ["clear", "rain", "snow"] {
            let app = launch(previewWeather: mood)
            XCTAssertTrue(app.buttons["connectWeather"].waitForExistence(timeout: 10))
            capture("Cover-\(mood)", app: app)
            app.swipeUp()
            capture("Weather-\(mood)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testInAppLanguageSwitchRelocalizesEverySurface() {
        let app = launch()
        app.buttons["openSettings"].tap()
        let picker = app.segmentedControls["appLanguage"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["시스템"].isSelected)

        picker.buttons["English"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Language used in the app"].exists)
        capture("Language-Settings-en", app: app)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["connectWeather"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["connectWeather"].label, "Connect local weather")
        capture("Language-Today-en", app: app)
        app.swipeUp()
        capture("Language-Weather-en", app: app)
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["Size M"].waitForExistence(timeout: 10))
        capture("Language-Fitting-en", app: app)
        app.buttons["tab-body"].tap()
        XCTAssertTrue(app.buttons["editActiveProfile"].waitForExistence(timeout: 10))
        capture("Language-Body-en", app: app)

        app.buttons["openSettings"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["日本語"].tap()
        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 10))
        capture("Language-Settings-ja", app: app)
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["editActiveProfile"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["editActiveProfile"].label, "体型を編集")
        capture("Language-Body-ja", app: app)
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["サイズ M"].waitForExistence(timeout: 10))
        capture("Language-Fitting-ja", app: app)
        app.buttons["tab-today"].tap()
        XCTAssertTrue(app.buttons["connectWeather"].waitForExistence(timeout: 10))
        capture("Language-Today-ja", app: app)
        app.swipeUp()
        capture("Language-Weather-ja", app: app)

        // The pinned language survives a relaunch, and Korean comes back on request.
        app.terminate()
        app.launchEnvironment["WEASHION_UI_TEST_RESET_LANGUAGE"] = nil
        app.launch()
        XCTAssertTrue(app.buttons["connectWeather"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["connectWeather"].label, "現在地の天気に接続")
        app.buttons["openSettings"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["한국어"].tap()
        XCTAssertTrue(app.buttons["닫기"].waitForExistence(timeout: 10))
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["connectWeather"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["connectWeather"].label, "현재 위치 날씨 연결")
    }

    @MainActor
    func testSavedFeedbackIsVisibleWithoutScrollingBackToTheTop() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        let edit = app.buttons["editGarmentMeasurements"]
        reveal(edit, in: app)
        edit.tap()
        let save = app.buttons["applyGarmentMeasurements"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let feedback = app.otherElements["savedFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertTrue(feedback.isHittable)
        let close = app.buttons["저장 안내 닫기"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertFalse(feedback.exists)
    }

    @MainActor
    func testInteractiveCoverKeepsProductSizeAndFittingActionAboveTheFold() throws {
        let app = launch()
        let closeFeedback = app.buttons["저장 안내 닫기"]
        if closeFeedback.exists { closeFeedback.tap() }
        let scene = app.otherElements["mannequinScene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        let body = app.staticTexts["coverBodyReference"]
        let originalBody = try XCTUnwrap(body.value as? String)
        let navigationTop = app.buttons["tab-fitting"].frame.minY
        for identifier in ["openProductLibrary", "fitting-size-meshy-cotton-s",
                           "fitting-size-meshy-cotton-m", "fitting-size-meshy-cotton-l",
                           "editGarmentMeasurements", "quickFittingRoom"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.isHittable, "\(identifier) should be reachable without scrolling")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertLessThanOrEqual(control.frame.maxY, navigationTop)
        }
        let initiallyPrepared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "선택한 사이즈 M"), object: scene)
        XCTAssertEqual(XCTWaiter.wait(for: [initiallyPrepared], timeout: 20), .completed)
        capture("Redesign-Interactive-Cover", app: app)
        app.buttons["S 사이즈"].tap()
        app.buttons["L 사이즈"].tap()
        XCTAssertTrue(app.buttons["tab-today"].isSelected)
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
        XCTAssertEqual(body.value as? String, originalBody)
        let prepared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "선택한 사이즈 L"), object: scene)
        XCTAssertEqual(XCTWaiter.wait(for: [prepared], timeout: 20), .completed)
        capture("Redesign-Cover-Size-L", app: app)
        app.buttons["editGarmentMeasurements"].tap()
        XCTAssertTrue(app.buttons["applyGarmentMeasurements"].waitForExistence(timeout: 10))
        capture("Redesign-Measurement-Editor", app: app)
        app.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["tab-today"].isSelected)
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
        app.buttons["quickFittingRoom"].tap()
        XCTAssertTrue(app.buttons["tab-fitting"].isSelected)
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
        let mannequinY = scene.frame.minY
        app.buttons["S 사이즈"].tap()
        app.buttons["L 사이즈"].tap()
        XCTAssertTrue(app.staticTexts["S → L"].exists)
        XCTAssertEqual(scene.frame.minY, mannequinY, accuracy: 0.5)
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, originalBody)
        capture("Redesign-Fitting-Comparison", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["L 사이즈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
        XCTAssertEqual(app.staticTexts["coverBodyReference"].value as? String, originalBody)
    }

    @MainActor
    func testInteractiveCoverSupportsAccessibilityTextSize() {
        let app = launch()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.otherElements["page-today"].waitForExistence(timeout: 15))
        let metadata = app.otherElements["coverMetadata"]
        XCTAssertTrue(metadata.exists)
        XCTAssertGreaterThanOrEqual(metadata.frame.minY, app.otherElements["mannequinScene"].frame.maxY)
        capture("Redesign-Large-Type-Cover", app: app)
        let small = app.buttons["S 사이즈"]
        let medium = app.buttons["M 사이즈"]
        let large = app.buttons["L 사이즈"]
        reveal(small, in: app)
        XCTAssertGreaterThanOrEqual(medium.frame.minY, small.frame.maxY)
        XCTAssertGreaterThanOrEqual(large.frame.minY, medium.frame.maxY)
        capture("Redesign-Large-Type-Metadata", app: app)
        reveal(large, in: app)
        large.tap()
        XCTAssertTrue(large.isSelected)
        let fitting = app.buttons["quickFittingRoom"]
        reveal(fitting, in: app)
        capture("Redesign-Large-Type-Controls", app: app)
        fitting.tap()
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        let edit = app.buttons["editGarmentMeasurements"]
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.buttons["applyGarmentMeasurements"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["applyGarmentMeasurements"].isEnabled)
        capture("Redesign-Large-Type-Editor", app: app)
        app.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
    }

    @MainActor
    func testEditorialJourneyKeepsTheViewpointAndComparesSizes() {
        let app = launch()
        let scene = app.otherElements["mannequinScene"]
        let prepared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "선택한 사이즈"), object: scene)
        XCTAssertEqual(XCTWaiter.wait(for: [prepared], timeout: 15), .completed)
        capture("Editorial-Linked-Cover", app: app)
        app.swipeUp()
        capture("Editorial-Weather-Rhythm", app: app)
        app.swipeUp()
        capture("Editorial-Weather-Local-Reveals", app: app)
        app.buttons["tab-body"].tap()
        XCTAssertTrue(app.buttons["tab-body"].isSelected)
        XCTAssertTrue(app.otherElements["page-body"].waitForExistence(timeout: 15))
        capture("Editorial-Body-Entrance", app: app)
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["tab-fitting"].isSelected)
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        let zoom = app.buttons["Zoom in"]
        reveal(zoom, in: app)
        XCTAssertTrue(zoom.waitForExistence(timeout: 10))
        for _ in 0..<8 where zoom.isEnabled { zoom.tap() }
        XCTAssertFalse(zoom.isEnabled)
        app.buttons["tab-today"].tap()
        XCTAssertTrue(app.otherElements["page-today"].waitForExistence(timeout: 15))
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        reveal(zoom, in: app)
        XCTAssertFalse(zoom.isEnabled)
        XCTAssertEqual(app.otherElements.matching(identifier: "mannequinScene").count, 1)
        app.buttons["Reset view"].tap()
        XCTAssertTrue(zoom.isEnabled)

        let small = app.buttons["S 사이즈"]
        let large = app.buttons["L 사이즈"]
        reveal(small, in: app)
        small.tap()
        reveal(large, in: app)
        large.tap()
        let comparison = app.staticTexts["입력 치수 차이"]
        reveal(comparison, in: app)
        XCTAssertTrue(app.staticTexts["입력 치수 차이"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["S → L"].exists)
        capture("Editorial-Size-Comparison", app: app)
        let chest = app.buttons["garment-note-3"]
        reveal(chest, in: app)
        let originalChest = chest.value as? String
        chest.tap()
        XCTAssertTrue(chest.isSelected)
        let chestMarker = app.buttons["garment-marker-3"]
        reveal(chestMarker, in: app)
        XCTAssertTrue(chestMarker.isSelected)
        let shoulderMarker = app.buttons["garment-marker-2"]
        reveal(shoulderMarker, in: app)
        for number in 1...4 {
            let marker = app.buttons["garment-marker-\(number)"]
            XCTAssertEqual(marker.frame.width, 44, accuracy: 0.000001)
            XCTAssertEqual(marker.frame.height, 44, accuracy: 0.000001)
        }
        shoulderMarker.tap()
        XCTAssertTrue(shoulderMarker.isSelected)
        XCTAssertFalse(chestMarker.isSelected)
        capture("Editorial-Measurement-Focus", app: app)
        let shoulder = app.buttons["garment-note-2"]
        reveal(shoulder, in: app)
        XCTAssertTrue(shoulder.isSelected)
        XCTAssertFalse(chest.isSelected)
        XCTAssertEqual(chest.value as? String, originalChest)
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
    }

    @MainActor
    func testGarmentWeatherStepsRevealSuggestions() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        let archive = app.buttons["openProductLibrary"]
        reveal(archive, in: app)
        archive.tap()
        let add = app.buttons["addProduct"]
        reveal(add, in: app)
        add.tap()
        let fabric = app.buttons["showGarmentFabric"]
        XCTAssertTrue(fabric.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["garmentClimateSummary"].exists)
        fabric.tap()
        let climate = app.buttons["showGarmentClimate"]
        reveal(climate, in: app)
        XCTAssertTrue(climate.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["garmentClimateSummary"].exists)
        for _ in 0..<4 where climate.frame.maxY > app.buttons["saveProduct"].frame.minY - 44 {
            app.swipeUp()
        }
        XCTAssertLessThanOrEqual(climate.frame.maxY, app.buttons["saveProduct"].frame.minY - 44)
        climate.tap()
        let summary = app.staticTexts["garmentClimateSummary"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("코튼"))
        let heavy = app.segmentedControls["garmentWeight"].buttons["두꺼움"]
        reveal(heavy, in: app)
        heavy.tap()
        XCTAssertTrue(summary.label.contains("두꺼움"))
        XCTAssertFalse(app.buttons["saveProduct"].isEnabled)
        capture("Editorial-Progressive-Garment-Weather", app: app)
    }

    @MainActor
    func testEditorialCoverConnectsToTheStudioAndBothArchives() {
        let app = launch()
        let fitting = app.buttons["quickFittingRoom"]
        reveal(fitting, in: app)
        XCTAssertTrue(fitting.isHittable)
        capture("Journal-Cover", app: app)
        fitting.tap()
        XCTAssertTrue(app.buttons["tab-fitting"].isSelected)
        XCTAssertTrue(app.buttons["M 사이즈"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "Rotate right").count, 1)
        capture("Journal-Fitting-Studio", app: app)

        app.buttons["openProductLibrary"].tap()
        let productCount = app.staticTexts["savedProductCount"]
        XCTAssertTrue(productCount.waitForExistence(timeout: 10))
        XCTAssertEqual(productCount.value as? String, "1")
        let sample = app.buttons["product-sample-cotton"]
        reveal(sample, in: app)
        XCTAssertTrue(sample.isHittable)
        capture("Journal-Garment-Archive", app: app)
        app.buttons["닫기"].tap()

        app.buttons["tab-body"].tap()
        let profiles = app.buttons["openBodyLibrary"]
        reveal(profiles, in: app)
        profiles.tap()
        let profileCount = app.staticTexts["savedProfileCount"]
        XCTAssertTrue(profileCount.waitForExistence(timeout: 10))
        XCTAssertEqual(profileCount.value as? String, "1")
        XCTAssertTrue(app.buttons["addBodyProfile"].exists)
        capture("Journal-Body-Archive", app: app)
        app.buttons["닫기"].tap()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["M 사이즈"].isSelected)
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, "175.0 cm / 70.0 kg")
    }

    @MainActor
    func testMagazineSizeNoteSelectsAGarmentWithoutChangingTheBody() throws {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        let bodyReference = app.staticTexts["personalBodyReference"]
        XCTAssertTrue(bodyReference.waitForExistence(timeout: 10))
        let original = try XCTUnwrap(bodyReference.value as? String)
        app.buttons["tab-today"].tap()
        let sizeNote = app.buttons["size-note-meshy-cotton-l"]
        reveal(sizeNote, in: app)
        XCTAssertTrue(sizeNote.isHittable)
        capture("Magazine-SizeSpread", app: app)
        sizeNote.tap()
        XCTAssertTrue(app.buttons["L 사이즈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab-fitting"].isSelected)
        XCTAssertTrue(app.buttons["L 사이즈"].isSelected)
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, original)
        XCTAssertEqual(app.buttons.matching(identifier: "Rotate right").count, 1)
        capture("Magazine-FittingSpread", app: app)
    }

    @MainActor
    func testGarmentInputValidationAndPersistence() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        app.buttons["M 사이즈"].tap()
        let edit = app.buttons["editGarmentMeasurements"]
        reveal(edit, in: app)
        edit.tap()
        let name = app.textFields["상품명"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        replaceText(of: name, with: "My cotton shirt", in: app)
        XCTAssertEqual(name.value as? String, "My cotton shirt")
        app.buttons["입력 완료"].tap()
        let source = app.textFields["상품 URL · 선택"]
        replaceText(of: source, with: "file:///invalid", in: app)
        app.buttons["입력 완료"].tap()
        XCTAssertFalse(app.buttons["applyGarmentMeasurements"].isEnabled)
        XCTAssertTrue(app.buttons["reviewInvalidMeasurement"].exists)
        app.buttons["reviewInvalidMeasurement"].tap()
        XCTAssertTrue(source.isHittable)
        replaceText(of: source, with: "https://example.com/shirt", in: app)
        app.buttons["입력 완료"].tap()
        let chest = app.textFields["measurement-가슴단면"]
        replaceText(of: chest, with: "57", in: app)
        XCTAssertEqual(chest.value as? String, "57")
        app.buttons["입력 완료"].tap()
        capture("Editorial-GarmentNotes", app: app)
        XCTAssertTrue(app.buttons["applyGarmentMeasurements"].isEnabled)
        app.buttons["applyGarmentMeasurements"].tap()
        XCTAssertTrue(app.staticTexts["My cotton shirt"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        let restoredProduct = app.buttons["openProductLibrary"]
        reveal(restoredProduct, in: app)
        XCTAssertTrue(restoredProduct.label.contains("My cotton shirt"))
        let chestNote = app.descendants(matching: .any)["garment-note-3"]
        reveal(chestNote, in: app)
        XCTAssertTrue(chestNote.exists)
        XCTAssertEqual(chestNote.value as? String, "57.0 cm")
    }

    @MainActor
    func testCancellingGarmentAndBodyEditsPreservesSavedValues() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        let edit = app.buttons["editGarmentMeasurements"]
        reveal(edit, in: app)
        edit.tap()
        let name = app.textFields["상품명"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let originalName = name.value as? String
        replaceText(of: name, with: "Unsaved garment", in: app)
        app.buttons["입력 완료"].tap()
        app.buttons["취소"].tap()
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, originalName)
        app.buttons["취소"].tap()
        openBodyEditor(app)
        let profileName = app.textFields["profileName"]
        XCTAssertTrue(profileName.waitForExistence(timeout: 10))
        let originalProfile = profileName.value as? String
        replaceText(of: profileName, with: "Unsaved body", in: app)
        app.buttons["취소"].tap()
        openBodyEditor(app)
        XCTAssertTrue(profileName.waitForExistence(timeout: 10))
        XCTAssertEqual(profileName.value as? String, originalProfile)
        app.buttons["취소"].tap()
        app.terminate()
        app.launch()
        app.buttons["tab-fitting"].tap()
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, originalName)
    }

    @MainActor
    func testMannequinReferenceViews() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        app.buttons["미착용"].tap()
        for base in ["남성", "여성"] {
            openBodyEditor(app)
            XCTAssertTrue(app.buttons[base].waitForExistence(timeout: 10))
            app.buttons[base].tap()
            finishBodyEditing(app)
            XCTAssertTrue(app.buttons["Reset view"].waitForExistence(timeout: 10))
            app.buttons["Reset view"].tap()
            for name in ["Front", "Side", "Back"] {
                capture("Mannequin-\(base)-\(name)", app: app)
                app.buttons["Rotate right"].tap()
                app.buttons["Rotate right"].tap()
            }
        }
    }

    @MainActor
    func testMannequinAtSupportedHeights() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        app.buttons["미착용"].tap()
        for (base, height) in [("여성", CGFloat(1)), ("여성", CGFloat(0)),
                               ("남성", CGFloat(1)), ("남성", CGFloat(0))] {
            openBodyEditor(app)
            XCTAssertTrue(app.buttons[base].waitForExistence(timeout: 10))
            app.buttons[base].tap()
            app.sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: height)
            finishBodyEditing(app)
            XCTAssertTrue(app.buttons["Reset view"].waitForExistence(timeout: 10))
            app.buttons["Reset view"].tap()
            capture("Mannequin-\(base)-Height-\(height)-Front", app: app)
            app.buttons["Rotate right"].tap()
            app.buttons["Rotate right"].tap()
            capture("Mannequin-\(base)-Height-\(height)-Side", app: app)
        }
    }

    @MainActor
    func testGarmentSizesOnUpdatedBody() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        for base in ["남성", "여성"] {
            openBodyEditor(app)
            XCTAssertTrue(app.buttons[base].waitForExistence(timeout: 10))
            app.buttons[base].tap()
            finishBodyEditing(app)
            for size in ["S", "M", "L"] {
                let button = app.buttons["\(size) 사이즈"]
                XCTAssertTrue(button.waitForExistence(timeout: 10))
                button.tap()
                let settled = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"),
                    object: app.descendants(matching: .any).matching(identifier: "garmentUpdating").firstMatch
                )
                wait(for: [settled], timeout: 60)
                XCTAssertTrue(button.isSelected)
                for error in ["옷 모델을 표시하지 못했습니다", "의류 데이터를 불러올 수 없습니다",
                              "착장 표면을 준비하지 못했습니다", "신체 겹침 보정에 실패했습니다", "옷을 표시하지 못했습니다"] {
                    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", error)).firstMatch.exists)
                }
                capture("Garment-\(base)-\(size)", app: app)
            }
        }
    }

    @MainActor
    func testLandscapeLayout() {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["tab-fitting"].waitForExistence(timeout: 10))
        capture("Editorial-Landscape-Today", app: app)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.otherElements["page-fitting"].waitForExistence(timeout: 15))
        capture("Editorial-Landscape-Fitting", app: app)
        let edit = app.buttons["editGarmentMeasurements"]
        XCTAssertLessThanOrEqual(app.otherElements["mannequinScene"].frame.maxX, edit.frame.minX)
        reveal(edit, in: app)
        XCTAssertTrue(edit.isHittable)
    }

    @MainActor
    func testProductAndCustomSizeReachTheSameBodyAndPersist() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        let original = app.staticTexts["personalBodyReference"].value as? String
        XCTAssertNotNil(original)
        app.buttons["openProductLibrary"].tap()
        let addProduct = app.buttons["addProduct"]
        reveal(addProduct, in: app)
        addProduct.tap()
        let name = app.textFields["상품명"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        replaceText(of: name, with: "My saved tee", in: app)
        app.buttons["saveProduct"].tap()
        let addSize = app.buttons["addProductSize"]
        XCTAssertTrue(addSize.waitForExistence(timeout: 10))
        reveal(addSize, in: app)
        addSize.tap()
        let label = app.textFields["사이즈명"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        replaceText(of: label, with: "95", in: app)
        app.buttons["입력 완료"].tap()
        let chest = app.textFields["measurement-가슴단면"]
        replaceText(of: chest, with: "56.5", in: app)
        XCTAssertEqual(chest.value as? String, "56.5")
        app.buttons["입력 완료"].tap()
        app.buttons["applyGarmentMeasurements"].tap()
        let fit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fit-size-")).firstMatch
        XCTAssertTrue(fit.waitForExistence(timeout: 10))
        reveal(fit, in: app)
        fit.tap()
        XCTAssertTrue(app.buttons["95 사이즈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["95 사이즈"].isSelected)
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, original)
        XCTAssertEqual(app.buttons.matching(identifier: "Rotate right").count, 1)
        app.terminate()
        app.launch()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["95 사이즈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["95 사이즈"].isSelected)
        let note = app.descendants(matching: .any)["garment-note-3"]
        reveal(note, in: app)
        XCTAssertEqual(note.value as? String, "56.5 cm")
    }

    @MainActor
    func testSixSampleModelsRenderAndLowerMeasurementsPersist() {
        let app = launch()
        func waitForFit(_ stage: String) {
            let scene = app.descendants(matching: .any).matching(identifier: "mannequinScene").firstMatch
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "선택한 사이즈 M"), object: scene)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 180), .completed, "\(stage) must finish a real rendered fit")
            XCTAssertFalse(app.otherElements["fittingLoadingOverlay"].exists)
        }
        app.buttons["tab-fitting"].tap()
        let bodyReference = app.staticTexts["personalBodyReference"]
        XCTAssertTrue(bodyReference.waitForExistence(timeout: 15))
        let originalBody = bodyReference.value as? String
        let models = ["long-sleeve", "hoodie", "dress-pants", "jeans", "bomber", "sneakers"]
        for model in models {
            let library = app.buttons["openProductLibrary"]
            reveal(library, in: app)
            library.tap()
            let sample = app.buttons["sample-model-meshy-\(model)"]
            XCTAssertTrue(sample.waitForExistence(timeout: 10))
            reveal(sample, in: app)
            sample.tap()
            let fit = app.buttons["fit-size-meshy-\(model)-m"]
            XCTAssertTrue(fit.waitForExistence(timeout: 10))
            reveal(fit, in: app)
            fit.tap()
            XCTAssertTrue(app.buttons["M 사이즈"].waitForExistence(timeout: 10))
            if model == "sneakers" {
                let cancel = app.buttons["cancelFitting"]
                XCTAssertTrue(cancel.waitForExistence(timeout: 10))
                reveal(cancel, in: app)
                XCTAssertTrue(app.staticTexts["fittingLoadingStage"].exists)
                capture("Garment-Outfit-Loading", app: app)
                cancel.tap()
                let retry = app.buttons["retryFitting"]
                XCTAssertTrue(retry.waitForExistence(timeout: 10))
                let scene = app.descendants(matching: .any).matching(identifier: "mannequinScene").firstMatch
                XCTAssertEqual(scene.value as? String, "착장 계산을 취소했어요")
                XCTAssertEqual(app.staticTexts["outfitItemCount"].label, "4 / 4")
                capture("Garment-Outfit-Cancelled", app: app)
                retry.tap()
                XCTAssertTrue(cancel.waitForExistence(timeout: 10))
                XCTAssertFalse(retry.exists)
            }
            waitForFit(model)
            XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, originalBody)
            if ["dress-pants", "jeans", "sneakers"].contains(model) {
                reveal(app.buttons["Reset view"], in: app)
            }
            capture("Garment-\(model)-M", app: app)
            if model == "dress-pants" || model == "sneakers" {
                let edit = app.buttons["editGarmentMeasurements"]
                reveal(edit, in: app)
                edit.tap()
                let field = app.textFields[model == "dress-pants" ? "measurement-허리단면" : "measurement-신발 외부 길이"]
                XCTAssertTrue(field.waitForExistence(timeout: 10))
                replaceText(of: field, with: model == "dress-pants" ? "44.5" : "285", in: app)
                if model == "dress-pants" {
                    let total = app.textFields["measurement-총장"]
                    reveal(total, in: app)
                    replaceText(of: total, with: "96", in: app)
                }
                app.buttons["입력 완료"].tap()
                capture("Garment-\(model)-Dimensions", app: app)
                app.buttons["applyGarmentMeasurements"].tap()
                XCTAssertTrue(app.buttons["M 사이즈"].waitForExistence(timeout: 10))
                waitForFit("\(model) edited measurements")
            }
        }
        let itemCount = app.staticTexts["outfitItemCount"]
        reveal(itemCount, in: app)
        XCTAssertEqual(itemCount.label, "4 / 4")
        app.terminate()
        app.launch()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.buttons["M 사이즈"].waitForExistence(timeout: 10))
        waitForFit("restored four-slot outfit")
        capture("Garment-Outfit-Restored-Four-Slots", app: app)
        let edit = app.buttons["editGarmentMeasurements"]
        reveal(edit, in: app)
        edit.tap()
        let length = app.textFields["measurement-신발 외부 길이"]
        XCTAssertTrue(length.waitForExistence(timeout: 10))
        XCTAssertEqual(length.value as? String, "285.0")
        app.buttons["취소"].tap()
        let library = app.buttons["openProductLibrary"]
        reveal(library, in: app)
        library.tap()
        let savedPants = app.buttons["sample-model-meshy-dress-pants"]
        XCTAssertTrue(savedPants.waitForExistence(timeout: 10))
        reveal(savedPants, in: app)
        savedPants.tap()
        let pants = app.buttons["fit-size-meshy-dress-pants-m"]
        XCTAssertTrue(pants.waitForExistence(timeout: 10))
        reveal(pants, in: app)
        pants.tap()
        XCTAssertTrue(app.buttons["M 사이즈"].waitForExistence(timeout: 10))
        waitForFit("restored dress-pants measurements")
        let pantsEdit = app.buttons["editGarmentMeasurements"]
        reveal(pantsEdit, in: app)
        pantsEdit.tap()
        let waist = app.textFields["measurement-허리단면"]
        XCTAssertTrue(waist.waitForExistence(timeout: 10))
        XCTAssertEqual(waist.value as? String, "44.5")
        let total = app.textFields["measurement-총장"]
        reveal(total, in: app)
        XCTAssertEqual(total.value as? String, "96.0")
        app.buttons["취소"].tap()
        let removeOuter = app.buttons["outfit-remove-outer"]
        reveal(removeOuter, in: app)
        removeOuter.tap()
        XCTAssertEqual(app.staticTexts["outfitItemCount"].label, "3 / 4")
        waitForFit("removed outer layer")
        app.terminate()
        app.launch()
        app.buttons["tab-fitting"].tap()
        XCTAssertTrue(app.staticTexts["outfitItemCount"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["outfitItemCount"].label, "3 / 4")
        waitForFit("restored three-slot outfit")
        capture("Garment-Outfit-Restored-Three-Slots", app: app)
    }

    @MainActor
    func testTrouserTotalLengthSynchronizesDecimalDrafts() {
        let app = launch()
        app.buttons["tab-fitting"].tap()
        let library = app.buttons["openProductLibrary"]
        reveal(library, in: app)
        library.tap()
        let sample = app.buttons["sample-model-meshy-dress-pants"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        reveal(sample, in: app)
        sample.tap()
        let fit = app.buttons["fit-size-meshy-dress-pants-m"]
        XCTAssertTrue(fit.waitForExistence(timeout: 10))
        reveal(fit, in: app)
        fit.tap()
        let edit = app.buttons["editGarmentMeasurements"]
        reveal(edit, in: app)
        edit.tap()
        let total = app.textFields["measurement-총장"]
        let rise = app.textFields["measurement-밑위"]
        let inseam = app.textFields["measurement-인심"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        replaceText(of: total, with: "96", in: app)
        app.buttons["입력 완료"].tap()
        XCTAssertEqual(inseam.value as? String, "68")
        XCTAssertEqual(rise.value as? String, "28.0")
        replaceText(of: total, with: "81.8", in: app)
        app.buttons["입력 완료"].tap()
        XCTAssertEqual(inseam.value as? String, "53.8")
        replaceText(of: rise, with: "31.4", in: app)
        app.buttons["입력 완료"].tap()
        XCTAssertEqual(total.value as? String, "85.2")
        replaceText(of: total, with: "81.8", in: app)
        app.buttons["입력 완료"].tap()
        XCTAssertEqual(inseam.value as? String, "50.4")
        replaceText(of: rise, with: "28", in: app)
        app.buttons["입력 완료"].tap()
        replaceText(of: total, with: "96", in: app)
        app.buttons["입력 완료"].tap()
        XCTAssertEqual(inseam.value as? String, "68")
        capture("Garment-Trouser-Decimal-Total-Length", app: app)
        app.buttons["applyGarmentMeasurements"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertEqual(total.value as? String, "96.0")
        XCTAssertEqual(rise.value as? String, "28.0")
        XCTAssertEqual(inseam.value as? String, "68.0")
        app.buttons["취소"].tap()
    }

    @MainActor
    func testAdditionalBodyProfileCanBeCreatedWithoutReplacingTheFirst() {
        let app = launch()
        app.buttons["tab-body"].tap()
        let library = app.buttons["openBodyLibrary"]
        reveal(library, in: app)
        library.tap()
        let add = app.buttons["addBodyProfile"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add, in: app)
        add.tap()
        finishSetup(app, base: "female", height: "168", weight: "58")
        XCTAssertTrue(app.buttons["addBodyProfile"].waitForExistence(timeout: 10))
        let activateButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activate-profile-"))
        XCTAssertEqual(activateButtons.count, 2)
        app.buttons["닫기"].tap()
        app.buttons["tab-fitting"].tap()
        XCTAssertEqual(app.staticTexts["personalBodyReference"].value as? String, "168.0 cm / 58.0 kg")
    }
}
