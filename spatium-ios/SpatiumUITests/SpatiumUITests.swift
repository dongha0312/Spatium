//
//  SpatiumUITests.swift
//  SpatiumUITests
//
//  Created by Dongha Ryu on 6/26/26.
//

import XCTest

final class SpatiumUITests: XCTestCase {

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
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testSavingGeneratedFurnitureOpensProjectLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestImgTo3D", "-UITestImgTo3DGLB", "modern_chair.glb"]
        app.launch()

        let nextButton = app.buttons["다음"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 8))
        nextButton.tap()

        let nameField = app.textFields["가구 이름"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UI 테스트 의자")

        let saveButton = app.buttons["가구 목록에 추가"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["내 가구"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["3D 에디터에서 사용 가능"].exists)
    }

    @MainActor
    func testRoomCatalogShowsUserFurnitureAndOtherCategories() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestCatalog"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["사용자 가구"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["기타"].exists)
    }

    @MainActor
    func testNewProjectKeyboardUsesFullScreenCover() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestHome"]
        app.launch()

        let projectsTab = app.buttons["프로젝트"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 8))
        projectsTab.tap()

        let createButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "새 프로젝트")
        ).firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 8))

        createButton.tap()

        XCTAssertTrue(app.textFields["프로젝트 이름을 입력하세요"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        let cover = app.otherElements["new-project-full-screen"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.frame.minY, app.frame.minY, accuracy: 1)
        XCTAssertEqual(cover.frame.maxY, app.frame.maxY, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "New project full-screen cover with keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testProfileKeyboardUsesFullScreenCover() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSettings", "-UITestProfileSheet"]
        app.launch()

        let nicknameField = app.textFields["닉네임을 입력하세요"]
        XCTAssertTrue(nicknameField.waitForExistence(timeout: 8))

        nicknameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        let cover = app.otherElements["profile-edit-full-screen"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.frame.minY, app.frame.minY, accuracy: 1)
        XCTAssertEqual(cover.frame.maxY, app.frame.maxY, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Profile full-screen cover with keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRepeatedPullToRefreshDoesNotPresentBlockingError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestHome"]
        app.launch()

        let projectsTab = app.buttons["프로젝트"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 8))
        projectsTab.tap()
        XCTAssertTrue(app.staticTexts["프로젝트"].firstMatch.waitForExistence(timeout: 8))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        for _ in 0..<4 {
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        XCTAssertFalse(app.alerts["요청을 완료하지 못했습니다"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["프로젝트"].firstMatch.exists)
    }
}
