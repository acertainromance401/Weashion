//
//  weashionUITests.swift
//  weashionUITests
//
//  Created by 임재현 on 9/30/26.
//

import XCTest

final class weashionUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testMannequinReferenceViews() throws {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()

        let undressed = app.buttons["미착용"]
        XCTAssertTrue(undressed.waitForExistence(timeout: 20))
        undressed.tap()
        app.swipeUp()

        let rotate = app.buttons["Rotate right"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 10))
        for base in ["Male", "Female"] {
            if base == "Female" {
                let customizeButton = app.buttons["Customize My Avatar"]
                customizeButton.tap()
                let baseButton = app.buttons[base]
                XCTAssertTrue(baseButton.waitForExistence(timeout: 5))
                baseButton.tap()
                app.buttons["완료"].tap()
                let editorDismissed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hittable == true"),
                    object: customizeButton
                )
                wait(for: [editorDismissed], timeout: 5)
            }
            app.buttons["Reset view"].tap()
            for name in ["Front", "Side", "Back", "OtherSide"] {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "Mannequin-\(base)-175cm-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
                rotate.tap()
                rotate.tap()
            }
        }
    }

    @MainActor
    func testMannequinAtSupportedHeights() throws {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()

        let undressed = app.buttons["미착용"]
        XCTAssertTrue(undressed.waitForExistence(timeout: 20))
        undressed.tap()
        app.swipeUp()
        app.buttons["Reset view"].tap()
        let customizeButton = app.buttons["Customize My Avatar"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 10))

        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        capture("Mannequin-Male-175cm")

        for (base, height, name) in [
            ("Female", CGFloat(1), "Mannequin-Female-200cm"),
            ("Female", CGFloat(0), "Mannequin-Female-150cm"),
            ("Male", CGFloat(1), "Mannequin-Male-200cm"),
            ("Male", CGFloat(0), "Mannequin-Male-150cm")
        ] {
            customizeButton.tap()
            let baseButton = app.buttons[base]
            XCTAssertTrue(baseButton.waitForExistence(timeout: 5))
            baseButton.tap()
            app.sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: height)

            app.buttons["완료"].tap()
            let editorDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"),
                object: customizeButton
            )
            wait(for: [editorDismissed], timeout: 5)
            capture("\(name)-Front")
            app.buttons["Rotate right"].tap()
            app.buttons["Rotate right"].tap()
            capture("\(name)-Side")
            app.buttons["Reset view"].tap()
        }
    }

    @MainActor
    func testGarmentSizesOnUpdatedBody() throws {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()

        let undressed = app.buttons["미착용"]
        XCTAssertTrue(undressed.waitForExistence(timeout: 20))
        undressed.tap()
        app.swipeUp()
        app.buttons["Reset view"].tap()

        for base in ["Male", "Female"] {
            if base == "Female" {
                undressed.tap()
                let customizeButton = app.buttons["Customize My Avatar"]
                customizeButton.tap()
                let baseButton = app.buttons[base]
                XCTAssertTrue(baseButton.waitForExistence(timeout: 5))
                baseButton.tap()
                app.buttons["완료"].tap()
                let editorDismissed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hittable == true"), object: customizeButton)
                wait(for: [editorDismissed], timeout: 5)
            }
            for size in ["95", "110"] {
                app.buttons[size].tap()
                let settled = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"),
                    object: app.staticTexts["착장 계산 중"]
                )
                wait(for: [settled], timeout: 60)
                XCTAssertTrue(app.buttons[size].isSelected)
                for message in ["옷 모델을 표시하지 못했습니다", "의류 데이터를 불러올 수 없습니다",
                                "착장 표면을 준비하지 못했습니다", "신체 겹침 보정에 실패했습니다", "옷을 표시하지 못했습니다",
                                "일부 영역에 겹침이 남아 있습니다"] {
                    XCTAssertFalse(app.staticTexts[message].exists)
                }
                for view in ["Front", "Side", "Back"] {
                    let attachment = XCTAttachment(screenshot: app.screenshot())
                    attachment.name = "Garment-\(base)-\(size)-\(view)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    app.buttons["Rotate right"].tap()
                    app.buttons["Rotate right"].tap()
                }
                app.buttons["Reset view"].tap()
            }
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
