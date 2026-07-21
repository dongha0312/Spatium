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
    func testImgTo3DNameStepBindingsRemainInteractiveAfterViewExtraction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestImgTo3D", "-UITestImgTo3DName"]
        app.launch()

        let nameField = app.textFields["예) 침대 옆 협탁"]
        let nextButton = app.buttons["다음"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["객체 분리 설정"].exists)
        XCTAssertTrue(app.staticTexts["3D 생성 설정"].exists)
        XCTAssertTrue(nextButton.exists)
        XCTAssertFalse(nextButton.isEnabled)

        nameField.tap()
        nameField.typeText("회색 사무용 의자")
        XCTAssertTrue(nextButton.isEnabled)
    }

    @MainActor
    func testGuestModeExplainsImgTo3DRestrictionBeforeStarting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestGuestRestrictions"]
        app.launch()

        XCTAssertTrue(
            app.otherElements["guest-img-to-3d-restriction"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["가구 만들기는 로그인이 필요해요"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "게스트 모드에서는 AI 배경 제거")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons["로그인하고 사용하기"].isHittable)
    }

    @MainActor
    func testScanPreparationExplainsOneRoomPerScan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScanPreparation"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["scan-one-room-guidance"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["한 번에 방 하나만 스캔해 주세요"].exists)
        XCTAssertTrue(app.staticTexts["한 방 = 스캔 1회"].exists)
        XCTAssertTrue(app.staticTexts["현재 방 안에서만 이동하기"].exists)
        XCTAssertTrue(app.staticTexts["다른 방은 새 스캔으로 시작하기"].exists)
        XCTAssertTrue(app.buttons["scan-preparation-close-button"].isHittable)
        XCTAssertTrue(app.buttons["scan-preparation-start-button"].isHittable)
    }

    @MainActor
    func testScanPreparationKeepsStartActionVisibleAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestScanPreparation",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        let guidance = app.descendants(matching: .any)["scan-one-room-guidance"]
        let startButton = app.buttons["scan-preparation-start-button"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 8))
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.isHittable)
        XCTAssertLessThanOrEqual(startButton.frame.maxY, app.windows.firstMatch.frame.maxY)
    }

    @MainActor
    func testRoomCatalogShowsUserFurnitureAndOtherCategories() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestCatalog",
            "-UITestClearEditorDrafts"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["사용자 가구"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["기타"].exists)
    }

    @MainActor
    func testAddingFurnitureReturnsToFocusedPlacementCanvas() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestCatalog",
            "-UITestClearEditorDrafts"
        ]
        app.launch()

        let addBedButton = app.buttons["기본 침대 추가"]
        XCTAssertTrue(addBedButton.waitForExistence(timeout: 8))
        addBedButton.tap()

        let movingButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "이동")
        ).firstMatch
        XCTAssertTrue(movingButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["어떤 가구를 놓을까요?"].exists)
        XCTAssertFalse(app.buttons["Skyview 보기"].exists)

        movingButton.tap()
        XCTAssertTrue(app.buttons["Skyview 보기"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEditorUndoAndRedoRestoreFurnitureSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestSelectFurniture",
            "-UITestClearEditorDrafts"
        ]
        app.launch()

        let undoButton = app.buttons["editor-undo-button"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 8))
        XCTAssertTrue(undoButton.isEnabled)
        XCTAssertTrue(app.staticTexts["이 기기에 임시 저장됨"].waitForExistence(timeout: 3))

        undoButton.tap()
        let redoButton = app.buttons["editor-redo-button"]
        XCTAssertTrue(redoButton.waitForExistence(timeout: 3))
        XCTAssertTrue(redoButton.isEnabled)

        redoButton.tap()
        let movingButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "이동")
        ).firstMatch
        XCTAssertTrue(movingButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testEditorHelpSheetAndFooterRemainAvailableAfterViewExtraction() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestViewHelp",
            "-UITestClearEditorDrafts"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["사용법 안내"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["가구 편집 (모든 뷰 공통)"].exists)

        let closeButton = app.buttons["닫기"]
        XCTAssertTrue(closeButton.exists)
        closeButton.tap()

        XCTAssertTrue(app.buttons["취소하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["저장하기"].exists)
    }

    @MainActor
    func testDecorCatalogStaysCompactAndPromptsForDirectShelfPlacement() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestDecorQuickPlacement", "-UITestClearEditorDrafts"
        ]
        app.launch()

        let modeBanner = app.descendants(matching: .any)["decor-mode-banner"]
        let placementBanner = app.descendants(matching: .any)["decor-placement-banner"]
        let catalog = app.scrollViews["decor-catalog"]
        XCTAssertTrue(modeBanner.waitForExistence(timeout: 8))
        XCTAssertTrue(placementBanner.waitForExistence(timeout: 3))
        XCTAssertTrue(catalog.waitForExistence(timeout: 3))
        XCTAssertLessThan(catalog.frame.height, 100)
        XCTAssertTrue(app.staticTexts["‘모던 피규어’ 소품을 놓을 선반을 탭하세요"].exists)
        XCTAssertTrue(app.buttons["decor-shelf-menu"].exists)

        let beforePlacement = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        beforePlacement.name = "Frontend-style compact decor controls"
        beforePlacement.lifetime = .keepAlways
        add(beforePlacement)

        // 정면 카메라에서 보이는 선반의 "윗면"을 직접 탭한다. 별도 칸 버튼 없이
        // 프런트와 같은 카탈로그 선택 → 3D 선반 탭 흐름으로 배치되어야 한다.
        // 배치는 윗면(법선 Y ≥ 0.7)에서만 성립하므로, 카메라 프레이밍이 조금
        // 바뀌어도 견디도록 보이는 선반 상판 후보 지점을 순서대로 시도한다.
        let selectionControls = app.descendants(matching: .any)["decor-selection-controls"]
        let shelfTopCandidates: [CGVector] = [
            CGVector(dx: 0.47, dy: 0.484), // 가운데 선반 상판
            CGVector(dx: 0.47, dy: 0.326), // 위 선반 상판
            CGVector(dx: 0.52, dy: 0.49),
            CGVector(dx: 0.42, dy: 0.48),
        ]
        for candidate in shelfTopCandidates where !selectionControls.exists {
            app.windows.firstMatch
                .coordinate(withNormalizedOffset: candidate)
                .tap()
            _ = selectionControls.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(selectionControls.waitForExistence(timeout: 5))
        XCTAssertFalse(placementBanner.exists)
        XCTAssertTrue(app.buttons["decor-shelf-menu"].exists)
        XCTAssertTrue(app.buttons["decor-move-left"].exists)
        XCTAssertTrue(app.buttons["decor-move-right"].exists)
        XCTAssertTrue(app.buttons["decor-move-forward"].exists)
        XCTAssertTrue(app.buttons["decor-move-backward"].exists)

        let afterPlacement = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterPlacement.name = "Decor placed by direct shelf tap"
        afterPlacement.lifetime = .keepAlways
        add(afterPlacement)

        // 선택한 소품 위에서 시작한 팬은 소품 이동으로, 빈 곳 팬은 카메라 조작으로 동작한다.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.47, dy: 0.29))
            .press(
                forDuration: 0.2,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.59, dy: 0.29))
            )
        XCTAssertTrue(selectionControls.exists)
        Thread.sleep(forTimeInterval: 0.8)

        let afterDrag = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterDrag.name = "Decor moved by direct drag"
        afterDrag.lifetime = .keepAlways
        add(afterDrag)
    }

    @MainActor
    func testDecorControlsBecomeScrollableAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestDecorQuickPlacement", "-UITestClearEditorDrafts",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        let scrollableControls = app.scrollViews["decor-controls-scroll"]
        XCTAssertTrue(scrollableControls.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["decor-shelf-menu"].waitForExistence(timeout: 3))

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(scrollableControls.frame.height, 0)
        XCTAssertGreaterThanOrEqual(scrollableControls.frame.minY, windowFrame.minY)
        XCTAssertLessThanOrEqual(scrollableControls.frame.maxY, windowFrame.maxY)
    }

    @MainActor
    func testLandscapeFurnitureControlsAndFooterStayInsideWindow() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestSelectFurniture",
            "-UITestClearEditorDrafts"
        ]
        app.launch()

        let controls = app.scrollViews["furniture-selection-controls-scroll"]
        XCTAssertTrue(controls.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["취소하기"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["저장하기"].exists)
        XCTAssertTrue(app.buttons["가구 추가"].exists)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height)
        XCTAssertGreaterThanOrEqual(controls.frame.minY, windowFrame.minY)
        XCTAssertLessThanOrEqual(controls.frame.maxY, app.buttons["취소하기"].frame.minY)
    }

    @MainActor
    func testLandscapeDecorControlsScrollAtAccessibilityTextSize() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestDecorQuickPlacement", "-UITestClearEditorDrafts",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        let controls = app.scrollViews["decor-controls-scroll"]
        XCTAssertTrue(controls.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["decor-shelf-menu"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["취소하기"].exists)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height)
        XCTAssertLessThanOrEqual(controls.frame.height, 180.5)
        XCTAssertLessThanOrEqual(controls.frame.maxY, app.buttons["취소하기"].frame.minY)

        app.buttons["decor-shelf-menu"].tap()
        let middleShelf = app.buttons["decor-shelf-1"]
        XCTAssertTrue(middleShelf.waitForExistence(timeout: 3))
        middleShelf.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["decor-selection-controls"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["decor-move-left"].exists)
        // 소품이 선택된 상태에서는 카탈로그가 숨겨지고 위치 조절 컨트롤만 보인다.
        // "교체"를 눌러 교체 모드로 들어가면 카탈로그가 다시 나타나며,
        // 큰 글씨에서는 컨트롤 목록이 길어져 카탈로그의 "소품 만들기"까지
        // 세로 스크롤해야 도달한다 — 스크롤로 도달 가능함을 검증한다.
        app.buttons["교체"].tap()
        let createFigureButton = app.buttons["소품 만들기"]
        for _ in 0..<5 where !createFigureButton.exists {
            controls.swipeUp()
        }
        XCTAssertTrue(createFigureButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLandscapeCatalogAndHelpRemainUsable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestCatalog",
            "-UITestClearEditorDrafts"
        ]
        app.launch()

        XCTAssertTrue(app.textFields["가구 검색하기"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["기본 침대 추가"].exists)
        app.buttons["가구 목록 닫기"].tap()

        let helpButton = app.buttons["뷰 사용법 안내"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        helpButton.tap()

        XCTAssertTrue(app.navigationBars["사용법 안내"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["가구 편집 (모든 뷰 공통)"].exists)
        XCTAssertTrue(app.buttons["닫기"].exists)
    }

    @MainActor
    func testLandscapeAppShellUsesCompactHeaderAndFooter() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-UITestHome"]
        app.launch()

        let header = app.otherElements["app-header"]
        let footer = app.otherElements["app-footer"]
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertTrue(footer.waitForExistence(timeout: 5))

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height)
        XCTAssertLessThanOrEqual(header.frame.height, 50)
        // iPhone 가로모드의 홈 인디케이터 안전영역까지 포함한 전체 푸터 높이입니다.
        XCTAssertLessThanOrEqual(footer.frame.height, 60)
        // Liquid Glass 헤더 배경이 가로모드 안전영역 위로 1~2pt 번지는 것은 허용한다.
        XCTAssertGreaterThanOrEqual(header.frame.minY, windowFrame.minY - 2)
        XCTAssertLessThanOrEqual(footer.frame.maxY, windowFrame.maxY)
        XCTAssertLessThan(header.frame.maxY, footer.frame.minY)
        XCTAssertTrue(app.buttons["프로젝트"].isHittable)
    }

    @MainActor
    func testLandscapeOnboardingKeepsContentAndActionsVisible() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-UITestOnboarding", "-UITestOnboardingPage", "0"]
        app.launch()

        let screen = app.descendants(matching: .any)["onboarding-screen"]
        let nextButton = app.buttons["다음"]
        let skipButton = app.buttons["건너뛰기"]
        XCTAssertTrue(screen.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["내 방을 3D로 스캔"].waitForExistence(timeout: 5))
        XCTAssertTrue(nextButton.exists)
        XCTAssertTrue(skipButton.exists)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height)
        XCTAssertLessThanOrEqual(nextButton.frame.maxY, windowFrame.maxY)
        XCTAssertLessThanOrEqual(skipButton.frame.maxY, windowFrame.maxY)
        XCTAssertTrue(nextButton.isHittable)
        XCTAssertTrue(skipButton.isHittable)

        nextButton.tap()
        XCTAssertTrue(app.staticTexts["가구를 자유롭게 배치"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeNewProjectKeyboardKeepsCreateActionReachable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-UITestHome"]
        app.launch()

        let projectsTab = app.buttons["프로젝트"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 8))
        projectsTab.tap()

        let newProjectButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "새 프로젝트")
        ).firstMatch
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 8))
        newProjectButton.tap()

        let nameField = app.textFields["프로젝트 이름을 입력하세요"]
        let keyboard = app.keyboards.firstMatch
        let createButton = app.buttons["프로젝트 만들고 스캔 시작"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))

        nameField.typeText("가로모드 프로젝트")
        XCTAssertTrue(createButton.isEnabled)
        XCTAssertTrue(createButton.isHittable)
        XCTAssertLessThanOrEqual(createButton.frame.maxY, keyboard.frame.minY + 1)
    }

    @MainActor
    func testLandscapeImgTo3DCorrectionKeepsViewerAndControlsVisible() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-UITestImgTo3D", "-UITestImgTo3DGLB", "modern_chair.glb"]
        app.launch()

        let canvas = app.otherElements["img-to-3d-model-canvas"]
        let footer = app.otherElements["app-footer"]
        let nextButton = app.buttons["다음"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["자동 보정"].waitForExistence(timeout: 5))
        XCTAssertTrue(nextButton.exists)
        XCTAssertTrue(footer.exists)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height)
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height)
        XCTAssertLessThanOrEqual(canvas.frame.maxY, footer.frame.minY)
        XCTAssertLessThanOrEqual(nextButton.frame.maxY, footer.frame.minY)
        XCTAssertTrue(app.buttons["자동 보정"].isHittable)
        XCTAssertTrue(nextButton.isHittable)
    }

    @MainActor
    func testPersonViewHidesFurnitureAddition() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestClearEditorDrafts"
        ]
        app.launch()

        let addFurniture = app.buttons["가구 추가"]
        let personView = app.buttons["1인칭으로 방 안 둘러보기"]
        XCTAssertTrue(addFurniture.waitForExistence(timeout: 8))
        XCTAssertTrue(personView.waitForExistence(timeout: 3))

        personView.tap()

        XCTAssertTrue(app.staticTexts["1인칭 · 드래그로 둘러보기 · 탭해서 이동"].waitForExistence(timeout: 5))
        XCTAssertFalse(addFurniture.exists)
    }

    @MainActor
    func testEditorCameraModesRemainInteractiveAfterSceneControllerExtraction() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestEditor", "-UITestScan", "other-room-2", "-UITestClearEditorDrafts"
        ]
        app.launch()

        let skyView = app.buttons["Skyview 보기"]
        let personView = app.buttons["1인칭으로 방 안 둘러보기"]
        let addFurniture = app.buttons["가구 추가"]
        XCTAssertTrue(skyView.waitForExistence(timeout: 8))
        XCTAssertTrue(personView.waitForExistence(timeout: 3))
        XCTAssertTrue(addFurniture.exists)

        skyView.tap()
        XCTAssertTrue(app.staticTexts["Skyview 모드"].waitForExistence(timeout: 5))
        XCTAssertTrue(addFurniture.exists)

        skyView.tap()
        XCTAssertTrue(app.staticTexts["Skyview 모드"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["측정 옵션 표시"].exists)

        personView.tap()
        XCTAssertTrue(
            app.staticTexts["1인칭 · 드래그로 둘러보기 · 탭해서 이동"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(addFurniture.exists)
        XCTAssertFalse(app.buttons["측정 옵션 표시"].exists)

        personView.tap()
        XCTAssertTrue(addFurniture.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["측정 옵션 표시"].exists)
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
