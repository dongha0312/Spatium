//
//  SpatiumTests.swift
//  SpatiumTests
//
//  Created by Dongha Ryu on 6/26/26.
//

import Testing
import Foundation
import ImageIO
import SceneKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@testable import Spatium

@MainActor
struct SpatiumTests {

    @Test func googleSignInWithoutActiveWindowReturnsRecoverableError() {
        let service = GoogleSignInService(presentationAnchorProvider: { nil })

        do {
            _ = try service.presentationAnchorForAuthentication()
            Issue.record("활성 윈도우가 없으면 로그인 오류를 반환해야 합니다.")
        } catch let error as GoogleSignInError {
            #expect(error == .presentationUnavailable)
            #expect(error.errorDescription?.isEmpty == false)
        } catch {
            Issue.record("예상하지 못한 오류가 반환되었습니다: \(error)")
        }
    }

    @Test func roomCaptureCannotStopBeforeFirstScanUpdate() {
        var lifecycle = RoomCaptureSessionLifecycle()

        let didRequestStart = lifecycle.requestStart()
        #expect(didRequestStart)
        #expect(lifecycle.phase == .starting)
        #expect(!lifecycle.canFinish)
        let didStopWhileStarting = lifecycle.requestStop()
        #expect(!didStopWhileStarting)

        lifecycle.sessionDidStart()
        #expect(lifecycle.phase == .running)
        let didStopBeforeUpdate = lifecycle.requestStop()
        #expect(!didStopBeforeUpdate)

        lifecycle.sessionDidUpdate()
        #expect(lifecycle.canFinish)
        let didStopAfterUpdate = lifecycle.requestStop()
        #expect(didStopAfterUpdate)
        #expect(lifecycle.phase == .stopping)
        #expect(!lifecycle.canFinish)
    }

    @Test func roomCaptureLifecycleResetsAfterSessionEnds() {
        var lifecycle = RoomCaptureSessionLifecycle()

        let didRequestStart = lifecycle.requestStart()
        #expect(didRequestStart)
        lifecycle.sessionDidStart()
        lifecycle.sessionDidUpdate()
        let didRequestStop = lifecycle.requestStop()
        #expect(didRequestStop)

        lifecycle.sessionDidEnd()
        #expect(lifecycle.phase == .idle)
        #expect(!lifecycle.canFinish)
        let didRestart = lifecycle.requestStart()
        #expect(didRestart)
    }

    @Test func scanEditorPreparationOnlyBecomesReadyAfterSuccessfulExport() async {
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-editor-test.usdz")

        let outcome = await ScanEditorPreparation.run {
            expectedURL
        }

        #expect(outcome == .ready(expectedURL))
    }

    @Test func scanEditorPreparationShowsRetryStateInsteadOfOpeningAfterFailure() async {
        let outcome = await ScanEditorPreparation.run {
            throw CocoaError(.fileWriteOutOfSpace)
        }

        #expect(outcome == .failed(message: ScanEditorPreparation.failureMessage))
    }

    @Test func cancelledScanEditorPreparationDoesNotShowAnError() async {
        let outcome = await ScanEditorPreparation.run {
            throw CancellationError()
        }

        #expect(outcome == .cancelled)
    }

    @Test func editorCatalogAlwaysIncludesUserFurnitureAndOtherFilters() {
        let groups = FurnitureCatalog.editorGroups(in: FurnitureCatalog.items)

        #expect(groups.last == "기타")
        #expect(groups.filter { $0 == "기타" }.count == 1)

        let builtIn = FurnitureCatalog.items[0]
        let userOther = FurnitureCatalogItem(
            id: "user-other",
            name: "사용자 기타 가구",
            group: "기타",
            category: "other",
            width: 1,
            height: 1,
            depth: 1,
            modelFileName: "user-other",
            source: .user
        )

        #expect(!FurnitureCatalog.matches(builtIn, groupFilter: FurnitureCatalog.userFurnitureFilterID))
        #expect(FurnitureCatalog.matches(userOther, groupFilter: FurnitureCatalog.userFurnitureFilterID))
        #expect(FurnitureCatalog.matches(userOther, groupFilter: FurnitureCatalog.otherGroup))
        #expect(RoomEditorViewModel.isDecorCatalogItem(userOther))

        let decoration = PlacedDecoration(
            decorId: 7,
            name: "웹 호환 소품",
            modelName: "usr_fixture",
            width: 0.2,
            height: 0.3,
            depth: 0.1,
            position: .init(x: 0.2, y: 0.9, z: 0.1),
            rotationY: .pi / 2,
            scale: 0.8,
            catalogId: "usr_fixture",
            category: "figure",
            modelPath: "/api/furniture/usr_fixture/model"
        )
        let bookcase = PlacedFurniture(
            itemId: 1,
            furnitureId: 1,
            furnitureName: "꾸미기 책장",
            position: .zero,
            rotation: .zero,
            scale: .init(x: 1.25, y: 1.25, z: 1.25),
            width: 0.8,
            depth: 0.3,
            height: 1.8,
            modelName: "editable_bookcase",
            decorations: [decoration]
        )
        let frontend = FrontendRoomObject(furniture: bookcase)
        let restored = frontend.editableScanItem(sourceType: "가구", index: 0)
        let restoredDecoration = restored.decorations?.first

        // 웹의 중심 pivot·부모 scale 형식으로 바꿨다가 앱의 바닥 pivot 형식으로
        // 돌아와도 실제 치수와 소품 위치·회전·크기·모델 경로가 유지된다.
        #expect(abs(restored.height - 2.25) < 0.0001)
        #expect(abs(restored.positionY - 1.125) < 0.0001)
        #expect(abs((restoredDecoration?.position.x ?? 0) - decoration.position.x) < 0.0001)
        #expect(abs((restoredDecoration?.position.y ?? 0) - decoration.position.y) < 0.0001)
        #expect(abs((restoredDecoration?.position.z ?? 0) - decoration.position.z) < 0.0001)
        #expect(abs((restoredDecoration?.rotationY ?? 0) - decoration.rotationY) < 0.0001)
        #expect(abs((restoredDecoration?.scale ?? 0) - decoration.scale) < 0.0001)
        #expect(restoredDecoration?.modelName == decoration.modelName)
        #expect(restoredDecoration?.modelPath == decoration.modelPath)
    }

    @Test func decorSupportNormalIsNormalizedBeforeCheckingItsDirection() {
        // editable_bookcase의 비균일 맞춤 스케일 뒤 실제 hit-test에서 관측된 윗면 법선.
        // 길이는 0.508이지만 정규화하면 정확히 위쪽을 향한다.
        #expect(RoomEditorSceneView.isDecorSupportNormal(SCNVector3(0, 0.508, 0)))

        // 수직 면과 유효하지 않은 0 벡터는 선반으로 취급하지 않는다.
        #expect(!RoomEditorSceneView.isDecorSupportNormal(SCNVector3(0.508, 0, 0)))
        #expect(!RoomEditorSceneView.isDecorSupportNormal(SCNVector3Zero))
    }

    @Test func decorCameraKeepsTheOpenShelfDirectionAndFitsTheViewport() {
        let rotatedOpenFace = RoomEditorSceneView.decorFrontDirection(
            from: SCNVector3(x: -2, y: 0.5, z: 0)
        )

        // 책장이 어느 위치에 있든 변환된 로컬 +Z를 그대로 사용해 열린 선반 면을 바라본다.
        #expect(abs(rotatedOpenFace.x + 1) < 0.0001)
        #expect(abs(rotatedOpenFace.y) < 0.0001)

        let defaultOpenFace = RoomEditorSceneView.decorFrontDirection(
            from: SCNVector3(x: 0, y: 0, z: 2)
        )
        #expect(abs(defaultOpenFace.x) < 0.0001)
        #expect(abs(defaultOpenFace.y - 1) < 0.0001)

        // 비정상적으로 수평 성분이 사라진 경우에도 유효한 기본 정면을 반환한다.
        #expect(
            RoomEditorSceneView.decorFrontDirection(from: SCNVector3(0, 1, 0))
                == SIMD2<Float>(0, 1)
        )

        let portraitDistance = RoomEditorSceneView.decorCameraDistance(
            halfWidth: 0.9,
            halfHeight: 0.4,
            halfDepth: 0.15,
            verticalFieldOfViewDegrees: 50,
            aspectRatio: 9.0 / 16.0
        )
        let landscapeDistance = RoomEditorSceneView.decorCameraDistance(
            halfWidth: 0.9,
            halfHeight: 0.4,
            halfDepth: 0.15,
            verticalFieldOfViewDegrees: 50,
            aspectRatio: 16.0 / 9.0
        )
        #expect(portraitDistance > landscapeDistance)
        #expect(landscapeDistance >= 0.8)
    }

    @Test func editorSceneReusesSelectionAndMeasurementNodesForUnchangedState() throws {
        let room = RoomRecord(
            id: "performance-room",
            roomType: "성능 테스트 방",
            itemCount: 0,
            photoCount: 0,
            uploadedAt: Date(),
            fileName: "",
            area: 16
        )
        let viewModel = RoomEditorViewModel(room: room)
        let coordinator = RoomEditorSceneView.Coordinator(
            viewModel: viewModel,
            modelLoader: TestDataFurnitureModelLoader()
        )
        // 측정 노드는 씬 빌드 때 계산한 방 치수(roomMeasurements)를 사용한다.
        coordinator.roomMeasurements = RoomEditorSceneView.Coordinator.fallbackRoomMeasurements(
            bounds: .defaultRoom,
            floorY: 0,
            height: 2.4
        )

        let furniture = SCNNode(
            geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        )
        furniture.name = "furniture-1"
        coordinator.furnitureContainer.addChildNode(furniture)

        coordinator.applySelection(itemID: 1)
        let firstHighlight = try #require(
            furniture.childNode(withName: coordinator.selectionHighlightName, recursively: false)
        )
        coordinator.applySelection(itemID: 1)
        let reusedHighlight = try #require(
            furniture.childNode(withName: coordinator.selectionHighlightName, recursively: false)
        )
        #expect(firstHighlight === reusedHighlight)

        coordinator.measurementContainer.isHidden = true
        coordinator.setMeasurementVisible(true)
        let firstMeasurementNodes = coordinator.measurementContainer.childNodes.map(ObjectIdentifier.init)
        #expect(!firstMeasurementNodes.isEmpty)
        coordinator.setMeasurementVisible(true)
        let reusedMeasurementNodes = coordinator.measurementContainer.childNodes.map(ObjectIdentifier.init)
        #expect(firstMeasurementNodes == reusedMeasurementNodes)

        coordinator.applySelection(itemID: nil)
        #expect(furniture.childNode(withName: coordinator.selectionHighlightName, recursively: false) == nil)
    }

    @Test func shelfDetectorFindsSeparateHorizontalSupportLevels() {
        let scene = SCNScene()
        let bookcase = SCNNode()
        for height: Float in [0.35, 0.85, 1.35] {
            let shelf = SCNNode(
                geometry: SCNBox(width: 1, height: 0.04, length: 0.4, chamferRadius: 0)
            )
            shelf.position = SCNVector3(0, height, 0)
            bookcase.addChildNode(shelf)
        }
        let decorContainer = SCNNode()
        // 월드 좌표의 hit 결과를 피규어 컨테이너 좌표로 바꾸므로 실제 편집 씬과
        // 동일하게 두 노드를 같은 scene graph에 연결한 상태에서 검증한다.
        scene.rootNode.addChildNode(bookcase)
        scene.rootNode.addChildNode(decorContainer)

        let detected = RoomEditorShelfDetector.detectHeights(
            in: bookcase,
            relativeTo: decorContainer
        )
        let levels = RoomEditorViewModel.makeDecorShelfLevels(from: detected)

        #expect(levels.count == 3)
        guard levels.count == 3 else { return }
        #expect(abs(levels[0].height - 0.37) < 0.02)
        #expect(abs(levels[1].height - 0.87) < 0.02)
        #expect(abs(levels[2].height - 1.37) < 0.02)

        let slid = RoomEditorSceneView.constrainedDecorSupportPoint(
            from: SIMD3<Float>(0, 0.6, 0),
            toward: SIMD3<Float>(0.4, 0.6, 0.3)
        ) { x, z, _ in
            abs(x) <= 0.2 && abs(z) <= 0.4 ? 0.62 : nil
        }
        // 대각선 요청이 X 가장자리에 막힌 뒤에도 Z축 이동은 계속되어 가장자리를 따라간다.
        #expect(slid.x >= 0.18 && slid.x <= 0.2)
        #expect(slid.z >= 0.28)
        #expect(abs(slid.y - 0.62) < 0.0001)
    }

    @Test func replacingDecorKeepsItsSupportPointRotationAndIdentity() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let viewModel = RoomEditorViewModel(
            scanItems: [],
            roomName: "꾸미기 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory
        )
        let bookcase = try #require(FurnitureCatalog.items.first { $0.modelFileName == "editable_bookcase" })
        let figure = FurnitureCatalogItem(
            id: "test_figure",
            name: "테스트 피규어",
            group: "피규어",
            category: "figure",
            width: 0.2,
            height: 0.3,
            depth: 0.15,
            modelFileName: "chair"
        )
        let replacement = FurnitureCatalogItem(
            id: "replacement_figure",
            name: "교체 피규어",
            group: "피규어",
            category: "figure",
            width: 0.18,
            height: 0.28,
            depth: 0.12,
            modelFileName: "modern_chair"
        )

        viewModel.place(catalogItem: bookcase)
        viewModel.isMovingSelectedFurniture = false
        viewModel.beginDecorating()

        viewModel.pendingFigure = figure
        // 기존의 책장 전체 사각형 clamp라면 큰 교체 모델에서 안쪽으로 당겨질 위치다.
        // 실제 지지면에서 얻은 점은 교체 전후 그대로 보존해야 한다.
        let supportPoint = FurnitureTransform.Vector3(x: 0.38, y: 0.64, z: 0.02)
        viewModel.placePendingFigure(atLocal: supportPoint)
        viewModel.setSelectedDecorRotation(degrees: 90)
        let original = try #require(viewModel.selectedDecoration)

        viewModel.replaceSelectedDecor(with: replacement)

        let replaced = try #require(viewModel.selectedDecoration)
        #expect(replaced.decorId == original.decorId)
        #expect(replaced.position == original.position)
        #expect(replaced.rotationY == original.rotationY)
        #expect(replaced.name == replacement.name)
        #expect(replaced.modelName == replacement.modelFileName)
        #expect(replaced.scale == 1)

        let constrained = try #require(
            viewModel.constrainedSelectedDecorPosition(.init(x: 20, y: 0.64, z: 20))
        )
        #expect(abs(constrained.x) < bookcase.width / 2)
        #expect(abs(constrained.z) < bookcase.depth / 2)
        await viewModel.discardCurrentDraft()
    }

    @Test func decorAccessibilityControlsPlaceMoveAndDescribeFigure() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let viewModel = RoomEditorViewModel(
            scanItems: [],
            roomName: "꾸미기 접근성 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory
        )
        let bookcase = try #require(
            FurnitureCatalog.items.first { $0.modelFileName == "editable_bookcase" }
        )
        let figure = FurnitureCatalogItem(
            id: "accessible_figure",
            name: "접근성 피규어",
            group: "피규어",
            category: "figure",
            width: 0.08,
            height: 0.10,
            depth: 0.08,
            modelFileName: "chair"
        )

        viewModel.place(catalogItem: bookcase)
        viewModel.isMovingSelectedFurniture = false
        viewModel.beginDecorating()
        #expect(viewModel.decorShelfLevels.map(\.title) == ["아래 선반", "가운데 선반", "위 선반"])

        viewModel.prepareDecorPlacement(figure)
        let middleShelf = try #require(viewModel.decorShelfLevels.first { $0.title == "가운데 선반" })
        viewModel.placePendingFigure(on: middleShelf)
        #expect(viewModel.selectedDecoration?.position.y == middleShelf.height)

        viewModel.nudgeSelectedDecor(deltaX: 0.05, deltaZ: 0)
        viewModel.nudgeSelectedDecor(deltaX: 0, deltaZ: 0.05)
        let moved = try #require(viewModel.selectedDecoration)
        #expect(abs(moved.position.x - 0.05) < 0.0001)
        #expect(abs(moved.position.z - 0.05) < 0.0001)
        #expect(viewModel.selectedDecorAccessibilitySummary.contains("오른쪽 5센티미터"))
        #expect(viewModel.selectedDecorAccessibilitySummary.contains("앞쪽 5센티미터"))
        #expect(viewModel.selectedDecorAccessibilitySummary.contains("크기 10센티미터"))

        viewModel.updateDecorShelfHeights([0.02, 0.03, 0.62, 0.64, 1.20])
        #expect(viewModel.decorShelfLevels.map(\.title) == ["아래 선반", "가운데 선반", "위 선반"])
        let topShelf = try #require(viewModel.decorShelfLevels.last)
        viewModel.moveSelectedDecor(to: topShelf)
        #expect(viewModel.selectedDecoration?.position.y == topShelf.height)
        #expect(viewModel.selectedDecorAccessibilitySummary.contains("위 선반"))
        await viewModel.discardCurrentDraft()
    }

    @Test func decorMatchesFrontendCatalogAndViewModeRestrictions() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let viewModel = RoomEditorViewModel(
            scanItems: [],
            roomName: "편집 제한 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory
        )
        let bookcase = try #require(FurnitureCatalog.items.first { $0.modelFileName == "editable_bookcase" })
        let chair = try #require(FurnitureCatalog.items.first { $0.modelFileName == "chair" })
        let figure = FurnitureCatalogItem(
            id: "allowed_figure",
            name: "허용 피규어",
            group: "피규어",
            category: "FIGURE",
            width: 0.2,
            height: 0.3,
            depth: 0.15,
            modelFileName: "chair"
        )
        let userChair = FurnitureCatalogItem(
            id: "user_chair_as_decor",
            name: "사용자 제작 의자 소품",
            group: "의자",
            category: "chair",
            width: 0.55,
            height: 0.85,
            depth: 0.55,
            modelFileName: "modern_chair",
            source: .user
        )

        #expect(!RoomEditorViewModel.isDecorFigure(chair))
        #expect(RoomEditorViewModel.isDecorFigure(figure))
        #expect(!RoomEditorViewModel.isDecorCatalogItem(chair))
        #expect(RoomEditorViewModel.isDecorCatalogItem(figure))
        #expect(RoomEditorViewModel.isDecorCatalogItem(userChair))

        viewModel.place(catalogItem: bookcase)
        viewModel.isMovingSelectedFurniture = false
        let bookcaseID = try #require(viewModel.selectedItemID)
        viewModel.setViewMode(.skyView)
        viewModel.beginDecorating()
        #expect(!viewModel.isDecorating)
        #expect(viewModel.statusMessage == "스카이뷰를 끈 뒤 책장 꾸미기를 시작해 주세요")

        viewModel.setViewMode(.threeD)
        viewModel.beginDecorating()
        viewModel.prepareDecorPlacement(chair)
        #expect(viewModel.pendingFigure == nil)
        #expect(viewModel.statusMessage == "꾸미기 책장에는 사용자 소품이나 피규어만 올릴 수 있어요")

        viewModel.prepareDecorPlacement(userChair)
        #expect(viewModel.pendingFigure?.id == userChair.id)

        viewModel.prepareDecorPlacement(figure)
        #expect(viewModel.pendingFigure?.id == figure.id)

        viewModel.endDecorating()
        #expect(viewModel.selectedItemID == bookcaseID)
        let furnitureCount = viewModel.layout.furnitures.count
        viewModel.setViewMode(.person)
        viewModel.place(catalogItem: chair)
        #expect(viewModel.layout.furnitures.count == furnitureCount)
        #expect(viewModel.statusMessage == "1인칭 시점에서는 가구를 추가할 수 없어요")
        await viewModel.discardCurrentDraft()
    }

    @Test func editorHistoryCoalescesSliderGestureAndSupportsRedo() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let viewModel = RoomEditorViewModel(
            scanItems: [],
            roomName: "히스토리 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory
        )
        let chair = try #require(FurnitureCatalog.items.first)

        viewModel.place(catalogItem: chair)
        viewModel.beginHistoryTransaction()
        viewModel.setSelectedRotation(degrees: 20)
        viewModel.setSelectedRotation(degrees: 40)
        viewModel.endHistoryTransaction()

        #expect(viewModel.selectedRotationDegrees == 40)
        await viewModel.undo()
        #expect(viewModel.layout.furnitures.count == 1)
        #expect(viewModel.selectedRotationDegrees == 0)

        await viewModel.redo()
        #expect(viewModel.selectedRotationDegrees == 40)
        await viewModel.discardCurrentDraft()
    }

    @Test func editorDraftPersistsAndRestoresLatestLayout() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let original = RoomEditorViewModel(
            scanItems: [],
            roomName: "임시 저장 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory
        )
        let chair = try #require(FurnitureCatalog.items.first)
        original.place(catalogItem: chair)
        await original.persistDraftImmediately()
        #expect(original.draftSavedAt != nil)

        let reopened = RoomEditorViewModel(
            scanItems: [],
            roomName: "임시 저장 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory
        )
        await reopened.loadLayout()

        #expect(reopened.hasRecoverableDraft)
        reopened.restoreRecoverableDraft()
        #expect(reopened.layout.furnitures.count == 1)
        #expect(reopened.hasUnsavedChanges)
        await reopened.discardCurrentDraft()
    }

    @Test func editorDraftReadEncodingWritingAndRemovalRunOutsideMainThread() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let recorder = DiskOperationThreadRecorder()
        let original = RoomEditorViewModel(
            scanItems: [],
            roomName: "복구본 스레드 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory,
            draftOperationObserver: { recorder.record(isMainThread: $0) }
        )
        let chair = try #require(FurnitureCatalog.items.first)
        original.place(catalogItem: chair)
        await original.persistDraftImmediately()

        let reopened = RoomEditorViewModel(
            scanItems: [],
            roomName: "복구본 스레드 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: draftDirectory,
            draftOperationObserver: { recorder.record(isMainThread: $0) }
        )
        await reopened.loadLayout()
        #expect(reopened.hasRecoverableDraft)
        await reopened.discardCurrentDraft()

        let observedThreads = recorder.recordedMainThreadValues
        #expect(observedThreads.count >= 3)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func newerDraftRemovalRejectsAnOlderDelayedWrite() async throws {
        let draftDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }

        let diskStore = RoomEditorDraftDiskStore(directoryURL: draftDirectory)
        let draftFileURL = draftDirectory.appendingPathComponent("revision-order.json")
        let olderWriteRevision = diskStore.reserveRevision()
        let newerRemovalRevision = diskStore.reserveRevision()
        let draft = EditorDraft(
            version: EditorDraft.currentVersion,
            savedAt: Date(),
            layout: RoomLayout(
                roomId: "revision-order",
                roomName: "복구본 순서 테스트",
                viewMode: .threeD,
                space: nil,
                furnitures: []
            )
        )

        let removed = await diskStore.remove(
            at: draftFileURL,
            revision: newerRemovalRevision
        )
        let staleWriteApplied = try await diskStore.write(
            draft,
            to: draftFileURL,
            revision: olderWriteRevision
        )

        #expect(removed)
        #expect(!staleWriteApplied)
        #expect(!FileManager.default.fileExists(atPath: draftFileURL.path))
    }

    @Test func editorDraftSaveFailureIsVisibleAndCanBeRetried() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let blockedDraftDirectory = testRoot.appendingPathComponent("not-a-directory")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        try Data("file blocks directory creation".utf8).write(to: blockedDraftDirectory)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let viewModel = RoomEditorViewModel(
            scanItems: [],
            roomName: "임시 저장 실패 테스트",
            usdzURL: nil,
            area: 16,
            ceilingHeight: 2.4,
            draftDirectoryURL: blockedDraftDirectory
        )
        let chair = try #require(FurnitureCatalog.items.first)
        viewModel.place(catalogItem: chair)
        await viewModel.persistDraftImmediately()

        #expect(viewModel.hasUnsavedChanges)
        #expect(
            viewModel.draftSaveState
                == .failed(message: RoomEditorViewModel.draftSaveFailureMessage)
        )

        try FileManager.default.removeItem(at: blockedDraftDirectory)
        await viewModel.retryDraftSave()

        #expect(viewModel.draftSavedAt != nil)
        #expect(viewModel.draftSaveState.failureMessage == nil)
        await viewModel.discardCurrentDraft()
    }

    @Test func otherRoomTwoIncludesBundledUserGeneratedFurniture() throws {
        let scan = try #require(TestRoomData.scans.first { $0.id == "other-room-2" })
        let loaded = try #require(scan.load())
        let item = try #require(loaded.items.first {
            $0.modelName == "usr_dfcb0a2619784c6faa11b2bfe17eb363"
        })

        #expect(item.detectedCategory == "사용자 생성 가구 테스트")
        #expect(item.width == 1.0)
        #expect(item.height == 1.2)
        #expect(item.depth == 0.8)
        #expect(item.positionX == 0.3)
        #expect(item.positionY == -0.524)
        #expect(item.positionZ == -5.5)
        #expect(
            Bundle.main.url(
                forResource: "usr_dfcb0a2619784c6faa11b2bfe17eb363",
                withExtension: "glb"
            ) != nil
        )
    }

    @Test func spatiumProjectRoundTripsThroughJSON() throws {
        var project = SpatiumProject(id: "1", name: "우리집 인테리어")
        project.rooms = [
            RoomRecord(id: "10", roomType: "거실", itemCount: 8, photoCount: 4, uploadedAt: Date(), fileName: "room-scan.usdz", area: 19.6)
        ]

        let data = try JSONEncoder.spatiumAPI.encode(project)
        let decoded = try JSONDecoder.spatiumAPI.decode(SpatiumProject.self, from: data)

        #expect(decoded.id == "1")
        #expect(decoded.name == "우리집 인테리어")
        #expect(decoded.rooms.count == 1)
        #expect(decoded.rooms.first?.roomType == "거실")
        #expect(decoded.rooms.first?.area == 19.6)
    }

    @Test func resolvedNameFallsBackWhenBlank() {
        let project = SpatiumProject(id: "1", name: "   ")
        #expect(project.resolvedName == "이름 없는 프로젝트")
    }

    @Test func displayRoomCountUsesServerListCountBeforeRoomsLoad() {
        let project = SpatiumProject(id: "1", name: "우리집 인테리어", roomCount: 3)
        #expect(project.displayRoomCount == 3)
    }

    // MARK: - API 명세 계약: 요청 바디의 JSON 키가 문서와 정확히 일치해야 함

    @Test func loginRequestMatchesSpecKeys() throws {
        let request = LoginRequest(email: "a@b.com", password: "pw", keepLogin: true)
        let object = try encodeToDictionary(request)

        #expect(object["email"] as? String == "a@b.com")
        #expect(object["password"] as? String == "pw")
        #expect(object["keepLogin"] as? Bool == true)
    }

    @Test func signUpRequestMatchesSpecKeys() throws {
        let request = SignUpRequest(
            email: "a@b.com", nickname: "동하", password: "pw",
            birthDate: "2000-01-01", gender: .male,
            termsAgreed: true, privacyAgreed: true
        )
        let object = try encodeToDictionary(request)

        #expect(object["nickname"] as? String == "동하")
        #expect(object["birthDate"] as? String == "2000-01-01")
        #expect(object["gender"] as? String == "0")
        #expect(object["termsAgreed"] as? Bool == true)
        #expect(object["privacyAgreed"] as? Bool == true)
    }

    /// 보안 개편 후 소셜 요청은 provider + idToken만 보낸다.
    /// (email/providerUserId는 서버가 idToken 검증으로 직접 얻는다)
    @Test func socialLoginRequestSendsOnlyProviderAndIdToken() throws {
        let apple = SocialLoginRequest(provider: .apple, idToken: "apple.jwt.token")
        let appleObject = try encodeToDictionary(apple)
        #expect(appleObject["provider"] as? String == "APPLE")
        #expect(appleObject["idToken"] as? String == "apple.jwt.token")
        #expect(appleObject["email"] == nil)
        #expect(appleObject["providerUserId"] == nil)

        let google = SocialLoginRequest(provider: .google, idToken: "google.jwt.token")
        let googleObject = try encodeToDictionary(google)
        #expect(googleObject["provider"] as? String == "GOOGLE")
        #expect(googleObject["idToken"] as? String == "google.jwt.token")
    }

    @Test func socialSignUpRequestMatchesSpecKeys() throws {
        let request = SocialSignUpRequest(
            provider: .google, idToken: "google.jwt.token",
            nickname: "김스파티", birthDate: "1998-06-07", gender: .male,
            termsAgreed: true, privacyAgreed: true
        )
        let object = try encodeToDictionary(request)

        #expect(object["provider"] as? String == "GOOGLE")
        #expect(object["idToken"] as? String == "google.jwt.token")
        #expect(object["email"] == nil)
        #expect(object["nickname"] as? String == "김스파티")
        #expect(object["birthDate"] as? String == "1998-06-07")
        #expect(object["gender"] as? String == "0")
        #expect(object["termsAgreed"] as? Bool == true)
        #expect(object["privacyAgreed"] as? Bool == true)
    }

    /// "창문"이 door 키워드 "문"에 부분 매칭돼 문 모델로 렌더되던 회귀 방지.
    @Test func windowCategoryBeatsDoorSubstringMatch() {
        #expect(FurnitureCatalog.category(matching: "창문 창문")?.id == "window")
        #expect(FurnitureCatalog.category(matching: "문 1")?.id == "door")
        #expect(FurnitureCatalog.defaultModelName(matching: "창문") == "window")
    }

    @Test func jwtClaimsExtractEmailAndSubject() throws {
        // {"sub":"12345","email":"a@b.com"} — base64url payload를 가진 가짜 JWT
        let payload = #"{"sub":"12345","email":"a@b.com"}"#
        let base64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(base64).signature"

        #expect(JWTClaims.email(from: token) == "a@b.com")
        #expect(JWTClaims.subject(from: token) == "12345")
    }

    @Test func envelopeDecodesSpecShape() throws {
        let json = """
        {"statusCode": 201, "message": "룸이 생성되었습니다.", "data": {"roomId": 1}}
        """.data(using: .utf8)!

        struct RoomData: Decodable { var roomId: Int }
        let envelope = try JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<RoomData>.self, from: json)

        #expect(envelope.statusCode == 201)
        #expect(envelope.message == "룸이 생성되었습니다.")
        #expect(envelope.data?.roomId == 1)
    }

    @Test func viewModeRawValuesMatchSpec() {
        #expect(RoomViewMode.threeD.rawValue == "3D")
        #expect(RoomViewMode.skyView.rawValue == "SKYVIEW")
    }

    @Test func releaseMetadataRegistersGoogleCallbackAndEncryptionAnswer() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }

        #expect(schemes.contains("com.googleusercontent.apps.75882144038-c0nfcrirlhlod41gl8esi8rtbne5gj4t"))
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test func privacyManifestDeclaresRequiredReasonAPIs() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let root = try #require(propertyList as? [String: Any])
        let entries = try #require(root["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasonEntries: [(String, [String])] = entries.compactMap { entry in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else {
                return nil
            }
            return (type, reasons)
        }
        let reasonsByType: [String: [String]] = Dictionary(uniqueKeysWithValues: reasonEntries)

        #expect(reasonsByType["NSPrivacyAccessedAPICategoryUserDefaults"]?.contains("CA92.1") == true)
        #expect(reasonsByType["NSPrivacyAccessedAPICategoryFileTimestamp"]?.contains("C617.1") == true)
    }

    private func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder.spatiumAPI.encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
struct ImgTo3DUploadImageTests {
    /// 8×8 단색 이미지 — 인코딩 테스트용 최소 입력.
    private func solidImage(size: CGSize = CGSize(width: 8, height: 8)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBrown.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func maximumPixelDimension(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return nil
        }
        return max(width, height)
    }

    @Test func heicPhotoConvertsToPNGForBackend() throws {
        let image = solidImage()
        let heicData = NSMutableData()
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithData(heicData, UTType.heic.identifier as CFString, 1, nil) else {
            return // 이 환경이 HEIC 인코딩을 지원하지 않으면 검증 불가
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return }

        let prepared = try #require(ImgTo3DUploadImage.prepare(rawData: heicData as Data))
        let normalized = prepared.upload
        #expect(normalized.convertedFromIncompatibleFormat)
        #expect(normalized.fileExtension == "png")
        #expect(normalized.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func jpegPhotoPassesThroughUnchanged() throws {
        let image = solidImage()
        let jpeg = try #require(image.jpegData(compressionQuality: 0.9))
        let normalized = try #require(ImgTo3DUploadImage.prepare(rawData: jpeg)).upload
        #expect(!normalized.convertedFromIncompatibleFormat)
        #expect(normalized.fileExtension == "jpg")
        #expect(normalized.data == jpeg)
    }

    @Test func cameraCaptureWithoutRawDataEncodesToPNG() throws {
        let normalized = try #require(ImgTo3DUploadImage.prepare(cameraImage: solidImage())).upload
        #expect(!normalized.convertedFromIncompatibleFormat)
        #expect(normalized.fileExtension == "png")
        #expect(normalized.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func oversizedPhotoIsDownsampledForUploadAndPreview() throws {
        let original = solidImage(size: CGSize(width: 160, height: 80))
        let png = try #require(original.pngData())
        let prepared = try #require(ImgTo3DUploadImage.prepare(
            rawData: png,
            maximumUploadPixelDimension: 64,
            maximumPreviewPixelDimension: 24
        ))

        let uploadDimension = try #require(maximumPixelDimension(of: prepared.upload.data))
        let previewCGImage = try #require(prepared.previewImage.cgImage)
        #expect(uploadDimension <= 64)
        #expect(max(previewCGImage.width, previewCGImage.height) <= 24)
        #expect(prepared.upload.data.count <= ImgTo3DUploadImage.maximumUploadBytes)
    }

    @Test func profileAvatarPreprocessingDownsamplesAndEncodesJPEG() throws {
        let original = solidImage(size: CGSize(width: 1_024, height: 512))
        let png = try #require(original.pngData())
        let prepared = try #require(ProfileAvatarImagePreprocessor.prepare(rawData: png))
        let uploadDimension = try #require(maximumPixelDimension(of: prepared.uploadData))
        let preview = try #require(prepared.previewImage.cgImage)

        #expect(uploadDimension <= ProfileAvatarImagePreprocessor.maximumPixelDimension)
        #expect(max(preview.width, preview.height) <= ProfileAvatarImagePreprocessor.maximumPixelDimension)
        #expect(prepared.uploadData.starts(with: [0xFF, 0xD8]))
    }
}

@MainActor
struct SettingsCacheStorageTests {
    @Test func cacheWorkerCountsAndClearsOnlyManagedDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let managedDirectory = root.appendingPathComponent("RoomScans", isDirectory: true)
        let unmanagedDirectory = root.appendingPathComponent("KeepMe", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unmanagedDirectory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(
            to: managedDirectory.appendingPathComponent("scan.bin")
        )
        let unmanagedFile = unmanagedDirectory.appendingPathComponent("user-data.bin")
        try Data(repeating: 2, count: 2_048).write(to: unmanagedFile)

        let measured = await SettingsCacheStorage.totalBytesInBackground(root: root)
        #expect(measured == 4_096)

        let remaining = await SettingsCacheStorage.clearInBackground(root: root)
        #expect(remaining == 0)
        #expect(FileManager.default.fileExists(atPath: unmanagedFile.path))
    }
}

@MainActor
struct ImgTo3DModelViewerTests {
    @Test func autoAlignmentRemovesPlaceholderTilt() async throws {
        var result: ImgTo3DModelTransform?
        let viewer = makeViewer(onAutoAlignment: { result = $0 })
        let coordinator = viewer.makeCoordinator()
        _ = coordinator.makeScene()
        coordinator.apply(transform: .initial, floorSnap: false)

        coordinator.autoAlignIfNeeded(token: 1, transform: .initial)
        await waitUntil { result != nil }

        let aligned = try #require(result)
        #expect(abs(aligned.xDegrees) < 2)
        #expect(abs(aligned.zDegrees) < 2)
        #expect(aligned.yPosition == 0)
    }

    @Test func worldDimensionsFollowNinetyDegreeRotation() async throws {
        var reportedSize: ImgTo3DModelSize?
        let viewer = makeViewer(onBoundsChanged: { reportedSize = $0 })
        let coordinator = viewer.makeCoordinator()
        _ = coordinator.makeScene()
        var transform = ImgTo3DModelTransform(
            xDegrees: 90,
            yDegrees: 0,
            zDegrees: 0,
            xPosition: 0,
            yPosition: 0,
            zPosition: 0,
            scale: 1
        )

        coordinator.apply(transform: transform, floorSnap: false)
        await waitUntil { reportedSize != nil }

        let rotated = try #require(reportedSize)
        #expect(abs(rotated.width - 1) < 0.001)
        #expect(abs(rotated.height - 0.6) < 0.001)
        #expect(abs(rotated.depth - 0.8) < 0.001)

        transform.scale = 1.5
        reportedSize = nil
        coordinator.apply(transform: transform, floorSnap: false)
        await waitUntil { reportedSize != nil }
        let scaled = try #require(reportedSize)
        #expect(abs(scaled.width - 1.5) < 0.001)
        #expect(abs(scaled.height - 0.9) < 0.001)
        #expect(abs(scaled.depth - 1.2) < 0.001)
    }

    @Test func dismantlingViewerReleasesSceneAndCachedModelResources() {
        let viewer = makeViewer()
        let coordinator = viewer.makeCoordinator()
        let sceneView = SCNView()
        sceneView.scene = coordinator.makeScene()
        sceneView.pointOfView = coordinator.cameraNode
        coordinator.sceneView = sceneView

        #expect(coordinator.retainedModelNodeCountForTesting > 0)
        #expect(coordinator.cachedModelSampleCountForTesting > 0)
        #expect(sceneView.scene != nil)

        ImgTo3DModelViewer.dismantleUIView(sceneView, coordinator: coordinator)

        #expect(sceneView.scene == nil)
        #expect(sceneView.pointOfView == nil)
        #expect(coordinator.sceneView == nil)
        #expect(coordinator.retainedModelNodeCountForTesting == 0)
        #expect(coordinator.cachedModelSampleCountForTesting == 0)
    }

    private func makeViewer(
        onBoundsChanged: @escaping (ImgTo3DModelSize) -> Void = { _ in },
        onAutoAlignment: @escaping (ImgTo3DModelTransform) -> Void = { _ in }
    ) -> ImgTo3DModelViewer {
        ImgTo3DModelViewer(
            transform: .constant(.initial),
            mode: .orbit,
            activeAxis: .free,
            floorSnap: false,
            modelURL: nil,
            cameraPreset: .perspective,
            cameraResetToken: 0,
            autoAlignToken: 0,
            onInteractionBegan: {},
            onModelLoaded: { _, _ in },
            onModelBoundsChanged: onBoundsChanged,
            onAutoAlignment: onAutoAlignment
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
struct FurnitureModelLoaderTests {
    @Test func modelTemplateCacheEvictsLeastRecentlyUsedEntriesWithinLimits() {
        var cache = BoundedLRUCache<String, Int>(countLimit: 3, totalCostLimit: 5)
        cache.insert(1, forKey: "bed", cost: 2)
        cache.insert(2, forKey: "chair", cost: 2)

        let cachedBed = cache.value(forKey: "bed")
        #expect(cachedBed == 1)
        cache.insert(3, forKey: "sofa", cost: 2)

        let evictedChair = cache.value(forKey: "chair")
        #expect(evictedChair == nil)
        #expect(cache.keysInLeastRecentlyUsedOrder == ["bed", "sofa"])
        #expect(cache.totalCost == 4)

        cache.insert(4, forKey: "table", cost: 1)
        cache.insert(5, forKey: "storage", cost: 1)

        #expect(cache.keysInLeastRecentlyUsedOrder == ["sofa", "table", "storage"])
        #expect(cache.count == 3)
        #expect(cache.totalCost == 4)

        cache.removeAll()
        cache.insert(6, forKey: "oversized", cost: 10)
        #expect(cache.keysInLeastRecentlyUsedOrder == ["oversized"])
        #expect(cache.totalCost == 10)

        cache.insert(7, forKey: "latest", cost: 1)
        #expect(cache.keysInLeastRecentlyUsedOrder == ["latest"])
        #expect(cache.totalCost == 1)
    }

    @Test func userGLBIsFittedToCatalogDimensionsInRoom() throws {
        let fileName = "usr_dfcb0a2619784c6faa11b2bfe17eb363"
        _ = try #require(Bundle.main.url(forResource: fileName, withExtension: "glb"))
        let target = (width: 0.60, height: 1.20, depth: 0.45)
        let furniture = PlacedFurniture(
            itemId: -1,
            furnitureId: 1,
            furnitureName: "사용자 가구",
            position: .zero,
            rotation: .zero,
            scale: .one,
            width: target.width,
            depth: target.depth,
            height: target.height,
            modelName: fileName
        )

        let node = TestDataFurnitureModelLoader().makeNode(for: furniture)
        let size = try #require(hierarchySize(of: node))

        #expect(abs(Double(size.x) - target.width) < 0.01)
        #expect(abs(Double(size.y) - target.height) < 0.01)
        #expect(abs(Double(size.z) - target.depth) < 0.01)
    }

    private func hierarchySize(of root: SCNNode) -> SCNVector3? {
        let frame = SCNNode()
        frame.addChildNode(root)
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false

        func accumulate(_ node: SCNNode) {
            if node.geometry != nil {
                let (lower, upper) = node.boundingBox
                let corners = [
                    SCNVector3(lower.x, lower.y, lower.z), SCNVector3(upper.x, lower.y, lower.z),
                    SCNVector3(lower.x, upper.y, lower.z), SCNVector3(upper.x, upper.y, lower.z),
                    SCNVector3(lower.x, lower.y, upper.z), SCNVector3(upper.x, lower.y, upper.z),
                    SCNVector3(lower.x, upper.y, upper.z), SCNVector3(upper.x, upper.y, upper.z)
                ]
                for corner in corners {
                    let point = node.convertPosition(corner, to: frame)
                    minimum = simd_min(minimum, SIMD3(point.x, point.y, point.z))
                    maximum = simd_max(maximum, SIMD3(point.x, point.y, point.z))
                    found = true
                }
            }
            node.childNodes.forEach(accumulate)
        }

        accumulate(root)
        guard found else { return nil }
        let size = maximum - minimum
        return SCNVector3(size.x, size.y, size.z)
    }
}

@MainActor
struct ProjectStorePersistenceTests {
    @Test func initialProjectCacheReadAndDecodingRunOutsideMainThread() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-project-cache-load-\(UUID().uuidString)", isDirectory: true)
        let cacheFileURL = testRoot.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: testRoot) }
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        let cachedProjects = [
            SpatiumProject(id: "project-cached", name: "캐시 프로젝트")
        ]
        let data = try JSONEncoder.spatiumAPI.encode(cachedProjects)
        try data.write(to: cacheFileURL, options: .atomic)

        let recorder = DiskOperationThreadRecorder()
        let store = ProjectStore(
            cacheFileURL: cacheFileURL,
            authenticationStateProvider: { true },
            cacheOperationObserver: { recorder.record(isMainThread: $0) },
            automaticallyRefresh: false
        )

        let didLoadCache = await waitUntil {
            store.projects.map(\.id) == cachedProjects.map(\.id)
        }
        let observedThreads = recorder.recordedMainThreadValues

        #expect(didLoadCache)
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func guestProjectRiskCountReadsCacheOutsideMainThread() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-guest-project-count-\(UUID().uuidString)", isDirectory: true)
        let cacheFileURL = testRoot.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: testRoot) }
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        let cachedProjects = [
            SpatiumProject(id: "local-first", name: "게스트 프로젝트 1"),
            SpatiumProject(id: "project-synced", name: "서버 프로젝트"),
            SpatiumProject(id: "local-second", name: "게스트 프로젝트 2")
        ]
        let data = try JSONEncoder.spatiumAPI.encode(cachedProjects)
        try data.write(to: cacheFileURL, options: .atomic)

        let recorder = DiskOperationThreadRecorder()
        let guestProjectCount = await ProjectStore.guestLocalProjectCount(
            cacheFileURL: cacheFileURL,
            cacheOperationObserver: { recorder.record(isMainThread: $0) }
        )
        let observedThreads = recorder.recordedMainThreadValues

        #expect(guestProjectCount == 2)
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func projectCacheWriteFailureIsVisibleAndCanBeRetried() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-project-cache-\(UUID().uuidString)", isDirectory: true)
        let blockedDirectory = testRoot.appendingPathComponent("not-a-directory")
        let cacheFileURL = blockedDirectory.appendingPathComponent("projects.json")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        try Data("file blocks cache directory creation".utf8).write(to: blockedDirectory)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let store = ProjectStore(
            cacheFileURL: cacheFileURL,
            authenticationStateProvider: { false }
        )
        let firstProject = try await store.createProject(name: "로컬 저장 복구 테스트")

        #expect(store.projects.first?.id == firstProject.id)
        #expect(store.localPersistenceErrorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: cacheFileURL.path))

        // 디스크 오류가 해결되기 전 계속 작업해도 재시도 시점의 최신 메모리 상태를 저장한다.
        let secondProject = try await store.createProject(name: "실패 후 추가한 프로젝트")
        try FileManager.default.removeItem(at: blockedDirectory)
        let didRetry = await store.retryLocalPersistence()

        #expect(didRetry)
        #expect(store.localPersistenceErrorMessage == nil)
        let savedData = try Data(contentsOf: cacheFileURL)
        let savedProjects = try JSONDecoder.spatiumAPI.decode(
            [SpatiumProject].self,
            from: savedData
        )
        #expect(savedProjects.map(\.id) == [secondProject.id, firstProject.id])
        #expect(savedProjects.map(\.name) == ["실패 후 추가한 프로젝트", "로컬 저장 복구 테스트"])
    }

    @Test func projectCacheEncodingAndWritingRunOutsideMainThread() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-project-cache-thread-\(UUID().uuidString)", isDirectory: true)
        let cacheFileURL = testRoot.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let recorder = DiskOperationThreadRecorder()
        let store = ProjectStore(
            cacheFileURL: cacheFileURL,
            authenticationStateProvider: { false },
            cacheOperationObserver: { recorder.record(isMainThread: $0) }
        )

        _ = try await store.createProject(name: "백그라운드 저장 테스트")

        let observedThreads = recorder.recordedMainThreadValues
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func overlappingProjectCacheWritesKeepNewestCompleteSnapshot() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-project-cache-order-\(UUID().uuidString)", isDirectory: true)
        let cacheFileURL = testRoot.appendingPathComponent("projects.json")
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let store = ProjectStore(
            cacheFileURL: cacheFileURL,
            authenticationStateProvider: { false }
        )
        let firstTask = Task { @MainActor in
            try await store.createProject(name: "첫 번째 프로젝트")
        }
        let secondTask = Task { @MainActor in
            try await store.createProject(name: "두 번째 프로젝트")
        }
        let firstProject = try await firstTask.value
        let secondProject = try await secondTask.value

        let savedData = try Data(contentsOf: cacheFileURL)
        let savedProjects = try JSONDecoder.spatiumAPI.decode(
            [SpatiumProject].self,
            from: savedData
        )
        #expect(store.projects.map(\.id) == [secondProject.id, firstProject.id])
        #expect(savedProjects.map(\.id) == store.projects.map(\.id))
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private final class DiskOperationThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func record(isMainThread: Bool) {
        lock.lock()
        values.append(isMainThread)
        lock.unlock()
    }

    var recordedMainThreadValues: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@MainActor
struct RoomSceneModelDiskStoreTests {
    @Test func roomSceneBase64DecodingAndWritingRunOutsideMainThread() async throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-room-scene-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let expectedData = Data((0..<4_096).map { UInt8($0 % 251) })
        let recorder = DiskOperationThreadRecorder()
        let store = RoomSceneModelDiskStore(
            directoryURL: testDirectory,
            operationObserver: { recorder.record(isMainThread: $0) }
        )

        let optionalURL = try await store.materialize(
            base64: expectedData.base64EncodedString(),
            roomID: "room/test"
        )
        let fileURL = try #require(optionalURL)
        let observedThreads = recorder.recordedMainThreadValues

        #expect(fileURL.lastPathComponent == "scene-room_test.usdz")
        #expect(try Data(contentsOf: fileURL) == expectedData)
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func invalidRoomSceneBase64DoesNotCreateACacheFile() async throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-invalid-room-scene-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let store = RoomSceneModelDiskStore(directoryURL: testDirectory)
        let fileURL = try await store.materialize(
            base64: "not-valid-base64!",
            roomID: "room-invalid"
        )

        #expect(fileURL == nil)
        #expect(!FileManager.default.fileExists(atPath: testDirectory.path))
    }
}

@MainActor
struct RoomScanAssetServiceTests {
    @Test func roomScanPackageReadDecodingAndItemMappingRunOutsideMainThread() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-room-scan-package-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let room = try makeFixture(in: testRoot, roomID: "local/package")
        let recorder = DiskOperationThreadRecorder()
        let service = RoomScanAssetService(
            cacheRootURL: testRoot.appendingPathComponent("RoomScans", isDirectory: true),
            diskOperationObserver: { recorder.record(isMainThread: $0) }
        )

        let optionalPackage = try await service.loadPackage(for: room)
        let package = try #require(optionalPackage)
        let item = try #require(package.items.first)
        let observedThreads = recorder.recordedMainThreadValues

        #expect(package.items.count == 1)
        #expect(item.detectedCategory == "chair")
        #expect(item.positionX == 1)
        #expect(item.positionZ == 2)
        #expect(package.floorColor == "#112233")
        #expect(package.usdzURL?.lastPathComponent == "source.usdz")
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func roomScanItemCountReadAndCacheInvalidationRunOutsideMainThread() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-room-scan-count-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let roomID = "local/count"
        let room = try makeFixture(in: testRoot, roomID: roomID)
        let cacheRoot = testRoot.appendingPathComponent("RoomScans", isDirectory: true)
        let roomCache = cacheRoot.appendingPathComponent("local_count", isDirectory: true)
        let recorder = DiskOperationThreadRecorder()
        let service = RoomScanAssetService(
            cacheRootURL: cacheRoot,
            diskOperationObserver: { recorder.record(isMainThread: $0) }
        )

        let itemCount = await service.loadItemCount(for: room)
        #expect(FileManager.default.fileExists(atPath: roomCache.path))

        await service.invalidateCache(forRoomID: roomID)
        let observedThreads = recorder.recordedMainThreadValues

        #expect(itemCount == 1)
        #expect(!FileManager.default.fileExists(atPath: roomCache.path))
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    private func makeFixture(in testRoot: URL, roomID: String) throws -> RoomRecord {
        let sourceDirectory = testRoot.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let jsonURL = sourceDirectory.appendingPathComponent("source.json")
        let usdzURL = sourceDirectory.appendingPathComponent("source.usdz")
        let json = """
        {
          "objects": [
            {
              "category": "chair",
              "dimensions": { "x": 1, "y": 2, "z": 3 },
              "transform": {
                "columns": [
                  [1, 0, 0, 0],
                  [0, 1, 0, 0],
                  [0, 0, 1, 0],
                  [1, 0, 2, 1]
                ]
              }
            }
          ],
          "doors": [],
          "windows": [],
          "_spatiumFloorColor": "#112233"
        }
        """
        try Data(json.utf8).write(to: jsonURL, options: .atomic)
        try Data("test-usdz".utf8).write(to: usdzURL, options: .atomic)

        return RoomRecord(
            id: roomID,
            roomType: "로컬 스캔 테스트",
            itemCount: 0,
            photoCount: 0,
            uploadedAt: Date(),
            fileName: "",
            area: 16,
            scanJsonUrl: jsonURL.absoluteString,
            usdzUrl: usdzURL.absoluteString
        )
    }
}

@MainActor
struct UserFurnitureStoreTests {
    @Test func initialCatalogReadDecodingMigrationAndSortingRunOutsideMainThread() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-furniture-load-thread-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let older = UserFurniture(
            id: "usr_older",
            name: "이전 가구",
            normalizedName: "older furniture",
            category: "other",
            categoryLabel: "기타",
            width: 60,
            height: 120,
            depth: 45,
            modelFileName: "usr_older",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = UserFurniture(
            id: "usr_newer",
            name: "최근 가구",
            normalizedName: "newer furniture",
            category: "chair",
            categoryLabel: "의자",
            width: 0.5,
            height: 0.8,
            depth: 0.5,
            modelFileName: "usr_newer",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let data = try JSONEncoder.spatiumAPI.encode([older, newer])
        try data.write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)

        let recorder = DiskOperationThreadRecorder()
        let store = UserFurnitureStore(
            storageDirectory: directory,
            initialLoadOperationObserver: { recorder.record(isMainThread: $0) }
        )
        await store.waitForInitialCatalogLoad()

        #expect(store.items.map(\.id) == [newer.id, older.id])
        #expect(store.items.last?.width == 0.6)
        #expect(store.items.last?.height == 1.2)
        #expect(store.items.last?.depth == 0.45)
        let observedThreads = recorder.recordedMainThreadValues
        #expect(!observedThreads.isEmpty)
        #expect(observedThreads.allSatisfy { !$0 })
    }

    @Test func legacyCentimeterDimensionsMigrateToMetersBeforeRoomPlacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-furniture-units-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacy = UserFurniture(
            id: "usr_legacy_centimeters",
            name: "나의 가구",
            normalizedName: "my furniture",
            category: "other",
            categoryLabel: "기타",
            width: 60,
            height: 120,
            depth: 45,
            modelFileName: "usr_legacy_centimeters",
            serverModelPath: "/data/user_3d_models/usr_legacy_centimeters.glb",
            createdAt: Date()
        )
        let data = try JSONEncoder.spatiumAPI.encode([legacy])
        try data.write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)

        let store = UserFurnitureStore(storageDirectory: directory)
        await store.waitForInitialCatalogLoad()
        let migrated = try #require(store.items.first)
        #expect(migrated.width == 0.6)
        #expect(migrated.height == 1.2)
        #expect(migrated.depth == 0.45)
        #expect(migrated.catalogItem.width == 0.6)
        #expect(migrated.catalogItem.height == 1.2)
        #expect(migrated.catalogItem.depth == 0.45)

        let relaunched = UserFurnitureStore(storageDirectory: directory)
        await relaunched.waitForInitialCatalogLoad()
        #expect(relaunched.items.first?.width == 0.6)
        #expect(relaunched.items.first?.height == 1.2)
        #expect(relaunched.items.first?.depth == 0.45)
    }

    @Test func mutationStartedDuringInitialLoadPreservesLoadedCatalog() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-furniture-load-mutation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let existing = UserFurniture(
            id: "usr_existing_at_launch",
            name: "기존 가구",
            normalizedName: "existing furniture",
            category: "chair",
            categoryLabel: "의자",
            width: 0.5,
            height: 0.8,
            depth: 0.5,
            modelFileName: "usr_existing_at_launch",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let data = try JSONEncoder.spatiumAPI.encode([existing])
        try data.write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)

        let store = UserFurnitureStore(storageDirectory: directory)
        let added = try await store.add(
            id: "usr_added_at_launch",
            name: "새 가구",
            normalizedName: "new furniture",
            category: "table",
            categoryLabel: "테이블",
            width: 1.2,
            height: 0.75,
            depth: 0.65,
            sourceModelURL: nil
        )

        #expect(Set(store.items.map(\.id)) == Set([existing.id, added.id]))
        let relaunched = UserFurnitureStore(storageDirectory: directory)
        await relaunched.waitForInitialCatalogLoad()
        #expect(Set(relaunched.items.map(\.id)) == Set([existing.id, added.id]))
    }

    @Test func signedOutRefreshKeepsCachedServerFurnitureForNextLogin() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-logout-furniture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserFurnitureStore(
            storageDirectory: directory,
            accessTokenProvider: { nil }
        )
        let cached = try await store.add(
            id: "usr_cached_server_item",
            name: "나의 의자",
            normalizedName: "my chair",
            category: "chair",
            categoryLabel: "의자",
            width: 0.5,
            height: 0.8,
            depth: 0.5,
            sourceModelURL: nil,
            serverModelPath: "/data/user_3d_models/usr_cached_server_item.glb"
        )

        await store.refreshFromBackend()

        #expect(store.items == [cached])
        let relaunched = UserFurnitureStore(
            storageDirectory: directory,
            accessTokenProvider: { nil }
        )
        await relaunched.waitForInitialCatalogLoad()
        #expect(relaunched.items.first?.id == cached.id)
        #expect(relaunched.items.first?.serverModelPath == cached.serverModelPath)
    }

    @Test func missingFurnitureEndpointFallsBackOnlyForNoResourceResponse() {
        #expect(UserFurnitureStore.shouldSaveLocally(after: .server(
            statusCode: 404,
            code: "NOT_FOUND",
            message: "요청한 리소스를 찾을 수 없습니다."
        )))
        #expect(!UserFurnitureStore.shouldSaveLocally(after: .server(
            statusCode: 401,
            code: "UNAUTHORIZED",
            message: "로그인이 필요합니다."
        )))
        #expect(!UserFurnitureStore.shouldSaveLocally(after: .server(
            statusCode: 500,
            code: "FURNITURE_SAVE_FAILED",
            message: "가구 모델 파일 저장에 실패했습니다."
        )))
    }

    @Test func userFurniturePersistsAndJoinsRenderingCatalog() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-user-furniture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserFurnitureStore(storageDirectory: directory)
        let furniture = try await store.add(
            name: "나의 캣타워",
            normalizedName: "cat tower",
            category: "other",
            categoryLabel: "기타",
            width: 0.6,
            height: 1.8,
            depth: 0.7,
            sourceModelURL: nil
        )

        #expect(store.items == [furniture])
        #expect(store.catalogItems.count == FurnitureCatalog.items.count + 1)
        #expect(store.catalogItems.last?.source == .user)
        #expect(store.catalogItems.last?.group == "기타")

        let reloaded = UserFurnitureStore(storageDirectory: directory)
        await reloaded.waitForInitialCatalogLoad()
        #expect(reloaded.items.count == 1)
        #expect(reloaded.items.first?.id == furniture.id)
        #expect(reloaded.items.first?.name == furniture.name)
        #expect(reloaded.items.first?.modelFileName == furniture.modelFileName)
        #expect(FurnitureCatalog.groups(in: reloaded.catalogItems).contains("기타"))
        #expect(FurnitureCatalog.items.contains { $0.id == "tong_glass" })
        #expect(FurnitureCatalog.items.contains { $0.id == "default_stairs" })
    }

    @Test func importedGLBIsCopiedIntoUserFurnitureStorage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-user-model-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("catalog", isDirectory: true)
        let source = root.appendingPathComponent("source.glb")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0x67, 0x6C, 0x54, 0x46]).write(to: source)

        let store = UserFurnitureStore(storageDirectory: directory)
        let furniture = try await store.add(
            name: "사용자 의자",
            normalizedName: "custom chair",
            category: "chair",
            categoryLabel: "의자",
            width: 0.5,
            height: 0.8,
            depth: 0.5,
            sourceModelURL: source
        )
        let copied = directory.appendingPathComponent(furniture.modelFileName).appendingPathExtension("glb")

        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(try Data(contentsOf: copied) == Data([0x67, 0x6C, 0x54, 0x46]))
    }

    @Test func locallySavedFurnitureSynchronizesWithCurrentBackendContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-pending-furniture-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("catalog", isDirectory: true)
        let source = root.appendingPathComponent("pending.glb")
        let glbData = Data([0x67, 0x6C, 0x54, 0x46, 0x02, 0x00, 0x00, 0x00])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try glbData.write(to: source)

        let store = UserFurnitureStore(storageDirectory: directory)
        let local = try await store.add(
            name: "나의 협탁",
            normalizedName: "side table",
            category: "table",
            categoryLabel: "테이블",
            width: 0.5,
            height: 0.6,
            depth: 0.4,
            sourceModelURL: source
        )
        let oldModelURL = directory
            .appendingPathComponent(local.modelFileName)
            .appendingPathExtension("glb")

        let count = await store.synchronizePendingFurniture { fileURL, fileName, metadata in
            #expect(fileURL.standardizedFileURL == oldModelURL.standardizedFileURL)
            #expect((try? Data(contentsOf: fileURL)) == glbData)
            #expect(fileName == "\(local.id).glb")
            #expect(metadata.nameKr == "나의 협탁")
            #expect(metadata.name == "side table")
            #expect(metadata.category == "table")
            #expect(metadata.categoryKr == "테이블")
            #expect(metadata.dimensions == .init(x: 0.5, y: 0.6, z: 0.4))
            return FurnitureCreateResponse(
                id: "usr_server_created",
                modelUrl: "/api/furniture/usr_server_created/model"
            )
        }

        #expect(count == 1)
        let synchronized = try #require(store.items.first)
        #expect(synchronized.id == "usr_server_created")
        #expect(synchronized.serverModelPath == "/api/furniture/usr_server_created/model")
        #expect(!FileManager.default.fileExists(atPath: oldModelURL.path))

        let newModelURL = directory
            .appendingPathComponent("usr_server_created")
            .appendingPathExtension("glb")
        #expect(FileManager.default.fileExists(atPath: newModelURL.path))
        #expect(try Data(contentsOf: newModelURL) == glbData)

        let reloaded = UserFurnitureStore(storageDirectory: directory)
        await reloaded.waitForInitialCatalogLoad()
        let persisted = try #require(reloaded.items.first)
        #expect(persisted.id == synchronized.id)
        #expect(persisted.name == synchronized.name)
        #expect(persisted.modelFileName == synchronized.modelFileName)
        #expect(persisted.serverModelPath == synchronized.serverModelPath)
        // API JSON 코더가 ISO-8601 초 단위로 날짜를 저장하므로 하위 초는 제거된다.
        #expect(abs(persisted.createdAt.timeIntervalSince(synchronized.createdAt)) < 1)
    }

    @Test func concurrentUserFurnitureAddsPreserveEveryCatalogEntry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-concurrent-furniture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserFurnitureStore(storageDirectory: directory)
        let firstTask = Task { @MainActor in
            try await store.add(
                id: "usr_concurrent_first",
                name: "첫 번째 가구",
                normalizedName: "first furniture",
                category: "chair",
                categoryLabel: "의자",
                width: 0.5,
                height: 0.8,
                depth: 0.5,
                sourceModelURL: nil
            )
        }
        let secondTask = Task { @MainActor in
            try await store.add(
                id: "usr_concurrent_second",
                name: "두 번째 가구",
                normalizedName: "second furniture",
                category: "table",
                categoryLabel: "테이블",
                width: 1.2,
                height: 0.75,
                depth: 0.65,
                sourceModelURL: nil
            )
        }

        let first = try await firstTask.value
        let second = try await secondTask.value
        let expectedIDs = Set([first.id, second.id])

        #expect(Set(store.items.map(\.id)) == expectedIDs)
        let reloaded = UserFurnitureStore(storageDirectory: directory)
        await reloaded.waitForInitialCatalogLoad()
        #expect(Set(reloaded.items.map(\.id)) == expectedIDs)
    }

    @Test func failedCatalogWriteRestoresExistingModelAndPublishedItems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-furniture-rollback-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("catalog", isDirectory: true)
        let source = root.appendingPathComponent("replacement.glb")
        let modelURL = directory
            .appendingPathComponent("usr_existing_model")
            .appendingPathExtension("glb")
        let metadataURL = directory.appendingPathComponent("catalog.json", isDirectory: true)
        let previousModel = Data([0x67, 0x6C, 0x54, 0x46, 0x01])
        let replacementModel = Data([0x67, 0x6C, 0x54, 0x46, 0x02])
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try previousModel.write(to: modelURL)
        try replacementModel.write(to: source)
        // catalog.json을 디렉터리로 만들어 모델 복사 후 JSON 원자 쓰기만 실패하게 한다.
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)

        let store = UserFurnitureStore(storageDirectory: directory)
        var receivedError: Error?
        do {
            _ = try await store.add(
                id: "usr_existing_model",
                name: "교체 가구",
                normalizedName: "replacement furniture",
                category: "other",
                categoryLabel: "기타",
                width: 0.6,
                height: 0.7,
                depth: 0.8,
                sourceModelURL: source
            )
        } catch {
            receivedError = error
        }

        #expect(receivedError != nil)
        #expect(store.items.isEmpty)
        #expect(try Data(contentsOf: modelURL) == previousModel)
        #expect(try Data(contentsOf: source) == replacementModel)
        let leftoverTransactionFiles = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".model-staging-") || $0.hasPrefix(".model-backup-") }
        #expect(leftoverTransactionFiles.isEmpty)
    }
}

@MainActor
struct BackendContractTests {
    @Test func signupResponseDecodesCurrentUserPayload() throws {
        let json = """
        {"statusCode":201,"message":"회원가입이 완료되었습니다.","data":{"userId":42,"email":"user@example.com","nickname":"스파티","profileImageUrl":null}}
        """.data(using: .utf8)!

        let envelope = try JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<UserSummary>.self, from: json)
        #expect(envelope.data?.userId == "42")
        #expect(envelope.data?.email == "user@example.com")
        #expect(envelope.data?.nickname == "스파티")
    }

    @Test func deleteResponsesDecodeStringIdentifiers() throws {
        let json = """
        {"statusCode":200,"message":"삭제에 성공했습니다.","data":"project-123"}
        """.data(using: .utf8)!

        let envelope = try JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<String>.self, from: json)
        #expect(envelope.data == "project-123")
    }

    @Test func avatarMultipartUsesBackendImageField() throws {
        let form = try MultipartFormData(parts: [
            .init(name: "image", data: Data([0xFF, 0xD8]), fileName: "avatar.jpg", contentType: "image/jpeg")
        ], boundary: "avatar-contract")
        let body = try #require(String(data: form.body, encoding: .isoLatin1))

        #expect(body.contains("name=\"image\"; filename=\"avatar.jpg\""))
        #expect(body.contains("Content-Type: image/jpeg"))
        #expect(!body.contains("name=\"avatar\""))
    }

    /// 대용량 USDZ/GLB 파일 파트가 실수로 메모리 바디 경로에 올라가지 않도록,
    /// 파일 파트는 스트리밍 `writeBodyFile`만 허용하고 메모리 init은 거부한다.
    @Test func multipartMemoryBodyRejectsFileParts() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-guard-\(UUID().uuidString).bin")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: MultipartFormDataError.self) {
            _ = try MultipartFormData(parts: [
                .init(name: "text", data: Data("value".utf8)),
                .init(name: "model", fileURL: fileURL, contentType: "model/gltf-binary")
            ], boundary: "file-guard-contract")
        }

        // 같은 파트 구성이라도 스트리밍 경로는 정상 동작해야 한다.
        let bodyURL = try MultipartFormData.writeBodyFile(
            parts: [
                .init(name: "text", data: Data("value".utf8)),
                .init(name: "model", fileURL: fileURL, contentType: "model/gltf-binary")
            ],
            boundary: "file-guard-contract"
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let body = try #require(String(data: Data(contentsOf: bodyURL), encoding: .isoLatin1))
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("--file-guard-contract--"))
    }

    @Test func profileImageDecoderSupportsBackendDataURL() {
        let expected = Data([1, 2, 3, 4])
        let source = "data:image/png;base64,\(expected.base64EncodedString())"
        #expect(ProfileImageDataDecoder.decode(source) == expected)
        #expect(ProfileImageDataDecoder.decode("https://example.com/avatar.png") == nil)
    }

    @Test func profileDataURLImageIsDecodedAndDownsampledInBackground() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(
            size: CGSize(width: 1_024, height: 512),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_024, height: 512))
        }
        let png = try #require(original.pngData())
        let source = "data:image/png;base64,\(png.base64EncodedString())"
        let decoded = try #require(await ProfileImageDataDecoder.decodeImageInBackground(source))
        let image = try #require(decoded.cgImage)

        #expect(max(image.width, image.height) <= ProfileImageDataDecoder.maximumDisplayPixelDimension)
    }

    @Test func imgTo3DOptionsMatchSpringGatewayAndFastAPI() {
        #expect(ImgTo3DCategory.allCases.map(\.code) == [
            "figure", "bathtub", "bed", "chair", "dishwasher", "fireplace", "oven",
            "refrigerator", "sink", "sofa", "stairs", "storage", "stove",
            "table", "television", "toilet", "washerDryer", "storage/editable", "other"
        ])
        #expect(ImgTo3DSegmentationProvider.allCases.map(\.rawValue) == ["grounded_sam2", "yolo"])
        #expect(ImgTo3DGenerationProvider.allCases.map(\.rawValue) == [
            "local_triposr", "local_stable_fast_3d"
        ])
        #expect(ImgTo3DRemesh.allCases.map(\.rawValue) == ["none", "triangle", "quad"])
    }

    @Test func imgTo3DUsesSpringGatewayAndDecodesBinaryMetadataHeader() throws {
        #expect(ImgTo3DService.removeBackgroundPath == "/api/ai/remove-background")
        #expect(ImgTo3DService.imageTo3DPath == "/api/ai/image-to-3d")

        let json = """
        {"segmentation_provider":"grounded_sam2","segmented_object":"의자","translated_query":"chair","confidence":0.9321}
        """.data(using: .utf8)!
        let header = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let metadata = try #require(ImgTo3DAIMetadata.decodeHeader(header))

        #expect(metadata.segmentationProvider == "grounded_sam2")
        #expect(metadata.segmentedObject == "의자")
        #expect(metadata.translatedQuery == "chair")
        #expect(metadata.confidence == 0.9321)
        #expect(ImgTo3DAIMetadata.decodeHeader("not-base64!") == nil)
    }

    @Test func onlySpringFurnitureModelURLsReceiveAPIAuthentication() {
        let apiBaseURL = URL(string: "https://spatium.kro.kr")!

        #expect(FurnitureService.protectedModelAPIPath(
            from: "/api/furniture/usr_123/model",
            apiBaseURL: apiBaseURL
        ) == "/api/furniture/usr_123/model")
        #expect(FurnitureService.protectedModelAPIPath(
            from: "https://spatium.kro.kr/api/furniture/usr_123/model",
            apiBaseURL: apiBaseURL
        ) == "/api/furniture/usr_123/model")
        // 같은 경로라도 다른 오리진(외부 호스트)에는 인증 토큰을 붙이지 않는다.
        #expect(FurnitureService.protectedModelAPIPath(
            from: "https://assets.example.com/api/furniture/usr_123/model",
            apiBaseURL: apiBaseURL
        ) == nil)
        #expect(FurnitureService.protectedModelAPIPath(
            from: "/data/3d_models/chair.glb",
            apiBaseURL: apiBaseURL
        ) == nil)
    }

    @Test func springFurnitureMultipartUsesFileAndJSONParts() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-contract-\(UUID().uuidString).glb")
        defer { try? FileManager.default.removeItem(at: modelURL) }
        try Data("glTF".utf8).write(to: modelURL)
        let metadata = FurnitureCreateMetadata(
            nameKr: "의자",
            name: "chair",
            category: "chair",
            categoryKr: "의자",
            dimensions: .init(x: 0.5, y: 0.8, z: 0.5)
        )
        let metadataData = try JSONEncoder.spatiumAPI.encode(metadata)
        let bodyURL = try MultipartFormData.writeBodyFile(
            parts: [
                .init(name: "file", fileURL: modelURL, fileName: "chair.glb", contentType: "model/gltf-binary"),
                .init(name: "metadata", data: metadataData, contentType: "application/json")
            ],
            boundary: "contract-test"
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let bodyData = try Data(contentsOf: bodyURL)
        let body = try #require(String(data: bodyData, encoding: .utf8))

        #expect(body.contains("name=\"file\"; filename=\"chair.glb\""))
        #expect(body.contains("Content-Type: model/gltf-binary"))
        #expect(body.contains("name=\"metadata\""))
        #expect(body.contains("\"nameKr\":\"의자\""))
        #expect(body.contains("\"dimensions\":{"))
        #expect(body.hasSuffix("--contract-test--\r\n"))
    }

    // 서버가 치수를 Double.toString() 문자열로 VARCHAR2 컬럼에 저장하므로,
    // 웹 프런트엔드(toFixed(4))와 동일하게 소수 4자리로 반올림해 보내야
    // 풀 정밀도 문자열(0.42500000000000004 등)로 인한 컬럼 길이 초과 500이 없다.
    @Test func furnitureCreateMetadataRoundsDimensionsLikeWebFrontend() throws {
        let metadata = FurnitureCreateMetadata(
            nameKr: "책장",
            name: "bookcase",
            category: "storage",
            categoryKr: "수납",
            dimensions: .init(x: 0.42500000000000004, y: 1.8000000000000007, z: 0.30000000000000004)
        )

        #expect(metadata.dimensions == .init(x: 0.425, y: 1.8, z: 0.3))

        let json = try #require(
            String(data: JSONEncoder.spatiumAPI.encode(metadata), encoding: .utf8)
        )
        #expect(!json.contains("00000000"))
    }

    @Test func correctedTransformIsBakedIntoValidGLBWrapper() throws {
        let source = try minimalGLB()
        let transform = ImgTo3DModelTransform(
            xDegrees: 90,
            yDegrees: 0,
            zDegrees: 0,
            xPosition: 1,
            yPosition: 2,
            zPosition: 3,
            scale: 1.5
        )
        let result = try GLBTransformBaker.bake(data: source, transform: transform)

        #expect(result.prefix(4) == Data("glTF".utf8))
        #expect(readUInt32(result, at: 8) == UInt32(result.count))
        let jsonLength = Int(readUInt32(result, at: 12))
        let json = result.subdata(in: 20..<(20 + jsonLength))
        let document = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let nodes = try #require(document["nodes"] as? [[String: Any]])
        let wrapper = try #require(nodes.last)
        let matrix = try #require(wrapper["matrix"] as? [Double])
        #expect(wrapper["name"] as? String == "SpatiumIOSCorrection")
        #expect(matrix.count == 16)
        #expect(abs(matrix[12] - 1) < 0.001)
        #expect(abs(matrix[13] - 2) < 0.001)
        #expect(abs(matrix[14] - 3) < 0.001)
    }

    @Test func correctedTransformFileStreamingPreservesBinaryPayload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-streaming-baker-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = directory.appendingPathComponent("source.glb")
        let destinationURL = directory.appendingPathComponent("corrected.glb")
        defer { try? FileManager.default.removeItem(at: directory) }

        let binary = Data(
            repeating: 0xA5,
            count: GLBTransformBaker.streamingBufferSize * 2 + 128
        )
        let source = try minimalGLB(binaryPayload: binary)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: sourceURL)

        let resultURL = try await GLBTransformBaker.bakeFileInBackground(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            transform: .init(xPosition: 1, yPosition: 2, zPosition: 3)
        )
        let result = try Data(contentsOf: resultURL)
        let jsonLength = Int(readUInt32(result, at: 12))
        let binaryHeaderOffset = 20 + jsonLength
        let binaryLength = Int(readUInt32(result, at: binaryHeaderOffset))
        let binaryType = readUInt32(result, at: binaryHeaderOffset + 4)
        let outputBinary = result.subdata(
            in: (binaryHeaderOffset + 8)..<(binaryHeaderOffset + 8 + binaryLength)
        )

        #expect(resultURL == destinationURL)
        #expect(result.prefix(4) == Data("glTF".utf8))
        #expect(readUInt32(result, at: 8) == UInt32(result.count))
        #expect(binaryType == 0x004E4942)
        #expect(outputBinary == binary)
        #expect(try Data(contentsOf: sourceURL) == source)
        let remainingFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(!remainingFiles.contains { $0.pathExtension == "tmp" })
    }

    @Test func invalidGLBStreamingBakeLeavesNoDestinationOrTemporaryFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-streaming-failure-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = directory.appendingPathComponent("invalid.glb")
        let destinationURL = directory.appendingPathComponent("corrected.glb")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid-glb".utf8).write(to: sourceURL)

        do {
            _ = try await GLBTransformBaker.bakeFileInBackground(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                transform: .initial
            )
            Issue.record("손상된 GLB는 보정 파일을 만들지 않아야 합니다.")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
        }

        let remainingFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(remainingFiles.map(\.lastPathComponent) == [sourceURL.lastPathComponent])
    }

    private func minimalGLB(binaryPayload: Data = Data()) throws -> Data {
        var json = try JSONSerialization.data(withJSONObject: [
            "asset": ["version": "2.0"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["name": "Root"]]
        ])
        json.append(contentsOf: repeatElement(UInt8(0x20), count: (4 - json.count % 4) % 4))
        let binaryChunkLength = binaryPayload.isEmpty ? 0 : 8 + binaryPayload.count
        var result = Data("glTF".utf8)
        appendUInt32(2, to: &result)
        appendUInt32(UInt32(20 + json.count + binaryChunkLength), to: &result)
        appendUInt32(UInt32(json.count), to: &result)
        appendUInt32(0x4E4F534A, to: &result)
        result.append(json)
        if !binaryPayload.isEmpty {
            appendUInt32(UInt32(binaryPayload.count), to: &result)
            appendUInt32(0x004E4942, to: &result)
            result.append(binaryPayload)
        }
        return result
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].enumerated().reduce(0) { partial, element in
            partial | UInt32(element.element) << UInt32(element.offset * 8)
        }
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

@MainActor
struct HomeAmbientAnimationTests {
    /// 홈 반복 애니메이션은 "홈 탭 표시 + 앱 포그라운드 + Reduce Motion 꺼짐"이
    /// 모두 만족될 때만 실행된다. (숨겨진 탭·백그라운드·접근성 설정에서 유휴 전력 사용 방지)
    @Test func ambientAnimationsRunOnlyWhenHomeIsVisibleAndActive() {
        #expect(HomeDashboardView.shouldRunAmbientAnimations(
            isActive: true, scenePhase: .active, reduceMotion: false
        ))
        // 가구 만들기 탭으로 이동해 홈이 숨겨진 상태.
        #expect(!HomeDashboardView.shouldRunAmbientAnimations(
            isActive: false, scenePhase: .active, reduceMotion: false
        ))
        // 앱이 백그라운드/인액티브로 전환된 상태.
        #expect(!HomeDashboardView.shouldRunAmbientAnimations(
            isActive: true, scenePhase: .background, reduceMotion: false
        ))
        #expect(!HomeDashboardView.shouldRunAmbientAnimations(
            isActive: true, scenePhase: .inactive, reduceMotion: false
        ))
        // 사용자가 동작 줄이기(Reduce Motion)를 켠 상태.
        #expect(!HomeDashboardView.shouldRunAmbientAnimations(
            isActive: true, scenePhase: .active, reduceMotion: true
        ))
    }
}

@MainActor
struct BoundedConcurrencyTests {
    /// 방·프로젝트 개수 집계가 데이터 규모와 무관하게 순간 동시 요청 수를
    /// `maxConcurrentCountRequests` 이하로 유지하면서 모든 요소를 처리하는지 검증한다.
    @Test func boundedConcurrencyKeepsWindowAndProcessesEveryElement() async {
        actor ConcurrencyTracker {
            private var current = 0
            private(set) var peak = 0
            func begin() {
                current += 1
                peak = max(peak, current)
            }
            func end() {
                current -= 1
            }
        }

        let tracker = ConcurrencyTracker()
        var processed: [Int] = []
        await ProjectStore.withBoundedConcurrency(
            elements: Array(1...23),
            limit: 5,
            operation: { value in
                await tracker.begin()
                try? await Task.sleep(for: .milliseconds(15))
                await tracker.end()
                return value
            },
            process: { processed.append($0) }
        )

        #expect(processed.sorted() == Array(1...23))
        #expect(await tracker.peak <= 5)

        // 기본 상한이 문서 권장 범위(4~6) 안에 있는지도 고정한다.
        #expect((4...6).contains(ProjectStore.maxConcurrentCountRequests))
    }
}

@MainActor
struct SurfaceTintRestoreTests {
    /// 프런트엔드 applyRoomWallColor/applyRoomFloorColor 대응 회귀:
    /// 색을 칠하기 전 원본 diffuse를 기록하고, 선택 해제(nil) 시 스캔 원본 재질로 복원한다.
    @Test func clearingWallAndFloorColorRestoresOriginalScanMaterials() throws {
        let room = RoomRecord(
            id: "tint-restore-room",
            roomType: "틴트 복원 방",
            itemCount: 0,
            photoCount: 0,
            uploadedAt: Date(),
            fileName: "",
            area: 16
        )
        let viewModel = RoomEditorViewModel(room: room)
        let coordinator = RoomEditorSceneView.Coordinator(
            viewModel: viewModel,
            modelLoader: TestDataFurnitureModelLoader()
        )

        // 스캔 셸을 흉내 낸 벽/바닥 mesh — 원본 diffuse를 고유 색으로 구분해 둔다.
        let shell = SCNNode()
        let wall = SCNNode(geometry: SCNBox(width: 3, height: 2.4, length: 0.1, chamferRadius: 0))
        wall.name = "Wall_0_grp"
        wall.geometry?.firstMaterial?.diffuse.contents = UIColor.systemRed
        let floor = SCNNode(geometry: SCNBox(width: 3, height: 0.05, length: 3, chamferRadius: 0))
        floor.name = "Floor_grp"
        floor.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue
        shell.addChildNode(wall)
        shell.addChildNode(floor)

        coordinator.tintWalls(in: shell, color: UIColor.white)
        coordinator.tintFloors(in: shell, color: UIColor.black)
        #expect(wall.geometry?.firstMaterial?.diffuse.contents as? UIColor == UIColor.white)
        #expect(floor.geometry?.firstMaterial?.diffuse.contents as? UIColor == UIColor.black)

        coordinator.tintWalls(in: shell, color: nil)
        coordinator.tintFloors(in: shell, color: nil)
        #expect(wall.geometry?.firstMaterial?.diffuse.contents as? UIColor == UIColor.systemRed)
        #expect(floor.geometry?.firstMaterial?.diffuse.contents as? UIColor == UIColor.systemBlue)

        // 한 번도 tint하지 않은 재질은 nil 적용이 원본을 건드리지 않아야 한다.
        let untouched = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        untouched.name = "Wall_1_grp"
        untouched.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGreen
        coordinator.tintWalls(in: untouched, color: nil)
        #expect(untouched.geometry?.firstMaterial?.diffuse.contents as? UIColor == UIColor.systemGreen)

        // 시야를 가리는 벽과 문·창문은 프런트엔드와 같은 서로 다른 투명도를 사용한다.
        // 문·창문은 벽보다 넓은 방향 범위에서 흐려지고, 방 안쪽에서는 둘 다 완전 복원한다.
        #expect(WallFacingUpdater.previewOpacity(for: -0.3, kind: .wall) == 0.04)
        #expect(WallFacingUpdater.previewOpacity(for: -0.1, kind: .wall) == 1)
        #expect(WallFacingUpdater.previewOpacity(for: -0.1, kind: .reference) == 0.08)
        #expect(WallFacingUpdater.previewOpacity(for: 0.1, kind: .reference) == 1)
    }

    /// 색을 고르지 않은 새 스캔 방은 벽을 기본색으로 덮지 않고 원본 재질을 유지한다.
    @Test func newEditorStartsWithoutForcedWallColor() {
        let room = RoomRecord(
            id: "no-tint-room",
            roomType: "원본 유지 방",
            itemCount: 0,
            photoCount: 0,
            uploadedAt: Date(),
            fileName: "",
            area: 16
        )
        let viewModel = RoomEditorViewModel(room: room)
        #expect(viewModel.wallColorHex == nil)
        #expect(viewModel.resolvedWallColorHex == "#F2EDE5")

        viewModel.setWallColor("#3A3A3A")
        #expect(viewModel.wallColorHex == "#3A3A3A")
        viewModel.setWallColor(nil)
        #expect(viewModel.wallColorHex == nil)
    }
}

@MainActor
struct RoomMeasurementCalculationTests {
    /// 프런트엔드 calculateRoomMeasurements 대응 회귀: 바닥 mesh 삼각형에서
    /// 폭·깊이·실제 면적·외곽 edge(사용 횟수 1)·높이선을 계산한다.
    @Test func floorPolygonProducesOutlineAreaAndHeightSegment() throws {
        // 3m × 2m 바닥(삼각형 2개, y=0.1) + 높이 2.3m 벽 하나로 셸을 구성한다.
        let floorY: Float = 0.1
        let vertices = [
            SCNVector3(0, floorY, 0),
            SCNVector3(3, floorY, 0),
            SCNVector3(3, floorY, 2),
            SCNVector3(0, floorY, 2)
        ]
        let indices: [Int32] = [0, 1, 2, 0, 2, 3]
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let floor = SCNNode(geometry: geometry)
        floor.name = "Floor_grp"

        let wall = SCNNode(geometry: SCNBox(width: 3, height: 2.3, length: 0.05, chamferRadius: 0))
        wall.name = "Wall_0_grp"
        wall.position = SCNVector3(1.5, floorY + 1.15, 0)

        let shell = SCNNode()
        shell.addChildNode(floor)
        shell.addChildNode(wall)

        let measurements = try #require(
            RoomEditorSceneView.Coordinator.calculateRoomMeasurements(from: shell)
        )

        #expect(abs(measurements.width - 3) < 0.01)
        #expect(abs(measurements.depth - 2) < 0.01)
        // 실제 바닥 폴리곤 면적(3×2=6). bounding box가 아니라 삼각형 면적 합이어야 한다.
        #expect(abs(measurements.area - 6) < 0.05)
        // 외곽선은 사용 횟수 1인 edge 4개(대각선 제외), 길이는 3·2·3·2.
        #expect(measurements.outlineSegments.count == 4)
        let lengths = measurements.outlineSegments.map(\.length).sorted()
        #expect(lengths.count == 4)
        if lengths.count == 4 {
            #expect(abs(lengths[0] - 2) < 0.01 && abs(lengths[1] - 2) < 0.01)
            #expect(abs(lengths[2] - 3) < 0.01 && abs(lengths[3] - 3) < 0.01)
        }
        // 높이선은 바닥 테두리 바깥 모서리(maxX+0.18, minZ-0.18)에 수직으로 선다.
        #expect(abs(measurements.heightSegment.start.x - 3.18) < 0.01)
        #expect(abs(measurements.heightSegment.start.z - (-0.18)) < 0.01)
        #expect(measurements.heightSegment.length > 2.2)
        // 외곽선 Y는 바닥 평면 높이를 따른다.
        #expect(abs((measurements.outlineSegments.first?.start.y ?? 0) - floorY) < 0.01)
    }

    /// 바닥 mesh가 없는 박스 방 폴백은 bounding box 직사각형 외곽선을 만든다.
    @Test func fallbackMeasurementsUseRectangleOutline() {
        let measurements = RoomEditorSceneView.Coordinator.fallbackRoomMeasurements(
            bounds: HorizontalBounds(minX: -2, maxX: 2, minZ: -1.5, maxZ: 1.5),
            floorY: 0,
            height: 2.4
        )
        #expect(abs(measurements.width - 4) < 0.001)
        #expect(abs(measurements.depth - 3) < 0.001)
        #expect(abs(measurements.area - 12) < 0.001)
        #expect(measurements.outlineSegments.count == 4)
        #expect(abs(measurements.heightSegment.length - 2.4) < 0.001)
    }
}
