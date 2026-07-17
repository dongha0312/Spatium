import QuartzCore
import SceneKit
import SwiftUI

/// SceneKit surface for the room editor. Camera control is handed to SceneKit
/// while nothing is selected; selecting a furniture item switches panning to
/// "move the selected item on the floor plane" until the user taps empty space.
struct RoomEditorSceneView: UIViewRepresentable {
    @ObservedObject var viewModel: RoomEditorViewModel

    private let modelLoader: FurnitureModelLoader = TestDataFurnitureModelLoader()

    /// `SCNHitTestResult.worldNormal`은 노드에 비균일 스케일이 걸리면 단위 벡터가
    /// 아닐 수 있다. 방향만 비교하도록 길이를 제거해야 책장 모델의 수평 선반을
    /// 안정적으로 지지면으로 판정할 수 있다.
    static func isDecorSupportNormal(_ normal: SCNVector3) -> Bool {
        let vector = SIMD3<Float>(normal.x, normal.y, normal.z)
        let length = simd_length(vector)
        guard length.isFinite, length > .ulpOfOne else { return false }
        return normal.y / length >= 0.7
    }

    /// 꾸미기 책장 모델은 열린 선반 면이 로컬 +Z를 향하도록 제작되어 있다.
    /// 방 중심 위치와 무관하게 이 축을 그대로 사용해야 배치/회전된 책장의 뒤판으로
    /// 카메라가 뒤집히지 않는다.
    static func decorFrontDirection(from worldLocalPositiveZ: SCNVector3) -> SIMD2<Float> {
        var direction = SIMD2(worldLocalPositiveZ.x, worldLocalPositiveZ.z)
        let length = simd_length(direction)
        guard length.isFinite, length > 0.001 else { return SIMD2(0, 1) }
        direction /= length
        return direction
    }

    func makeUIView(context: Context) -> SCNView {
        let view = CameraFittingSceneView()
        view.backgroundColor = UIColor { traits in
            UIColor(hexString: traits.userInterfaceStyle == .dark ? "#2A3436" : "#F2EEE6")
        }
        view.antialiasingMode = .multisampling4X
        // ProMotion 기기에서 드래그가 120Hz로 갱신되도록. (60Hz 기기에선 SceneKit이 알아서 낮춰 잡음)
        view.preferredFramesPerSecond = 120
        view.delegate = context.coordinator.wallFacingUpdater
        view.scene = context.coordinator.buildScene(for: viewModel.layout)
        view.allowsCameraControl = viewModel.viewMode != .person
        view.pointOfView = context.coordinator.cameraNode
        view.onLayout = { [coordinator = context.coordinator, weak view] in
            guard let view else { return }
            let size = view.bounds.size
            guard size.width > 0, size.height > 0, coordinator.cameraLayoutSize != size else { return }
            coordinator.cameraLayoutSize = size
            coordinator.applyCamera(mode: coordinator.viewModel.viewMode, animated: false)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = false
        // 선택된 가구 위에서 시작한 터치만 받도록 delegate에서 거른다. 그 외의 드래그/핀치는
        // 전부 SceneKit 카메라 컨트롤로 흘러가, 이동 모드에서도 시점 회전·확대가 그대로 된다.
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.movePanGesture = pan

        // 사람 뷰 전용 조작(시선/걷기/전진). SceneKit 기본 카메라 컨트롤은 이동 위치를
        // 가로챌 수 없어 가구/벽 충돌을 걸 수 없으므로, 사람 뷰에서는 직접 처리한다.
        let personLook = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePersonLook(_:)))
        personLook.maximumNumberOfTouches = 1
        personLook.isEnabled = false
        // 탭 이동을 먼저 판정한다. 이동량이 있으면 tap이 즉시 실패하고 기존 시선 팬이
        // 이어받으므로, 드래그 둘러보기는 유지하면서 짧은 탭이 팬에 먹히는 것을 막는다.
        personLook.require(toFail: tap)
        view.addGestureRecognizer(personLook)
        context.coordinator.personLookGesture = personLook

        let personWalk = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePersonWalk(_:)))
        personWalk.minimumNumberOfTouches = 2
        personWalk.maximumNumberOfTouches = 2
        personWalk.isEnabled = false
        view.addGestureRecognizer(personWalk)
        context.coordinator.personWalkGesture = personWalk

        let personPinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePersonPinch(_:)))
        personPinch.isEnabled = false
        view.addGestureRecognizer(personPinch)
        context.coordinator.personPinchGesture = personPinch
        context.coordinator.sceneView = view

        context.coordinator.applyCamera(mode: viewModel.viewMode, animated: false)
        DispatchQueue.main.async {
            context.coordinator.applyCamera(mode: viewModel.viewMode, animated: false)
        }
        // 최초 씬은 이미 만들었으니, 다음 updateUIView가 불필요한 전체 재생성을 하지 않도록 맞춥니다.
        context.coordinator.renderedRevision = viewModel.sceneRevision
        context.coordinator.renderedViewMode = viewModel.viewMode
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator

        if coordinator.renderedRevision != viewModel.sceneRevision {
            if viewModel.usdzURL != nil {
                // 스캔 방: 카메라(보던 각도/확대)를 유지한 채 가구/벽색만 증분 반영해 시점이 튀지 않게 합니다.
                coordinator.rebuildFurnitureNodes(for: viewModel.layout)
                coordinator.retintWallsIfNeeded(to: viewModel.wallColorHex)
                coordinator.retintFloorsIfNeeded(to: viewModel.floorColorHex)
            } else {
                // 박스(저장) 방: 방 크기/색이 바뀔 수 있어 전체 재생성.
                view.scene = coordinator.buildScene(for: viewModel.layout)
                coordinator.applyCamera(mode: viewModel.viewMode, animated: false)
                coordinator.renderedViewMode = viewModel.viewMode
            }
            coordinator.renderedRevision = viewModel.sceneRevision
        }

        if coordinator.renderedViewMode != viewModel.viewMode {
            coordinator.applyCamera(mode: viewModel.viewMode, animated: true)
            coordinator.renderedViewMode = viewModel.viewMode
        }

        coordinator.applySelection(itemID: viewModel.selectedItemID)
        coordinator.setMeasurementVisible(viewModel.isMeasuring)
        coordinator.syncSelectedRotation(from: viewModel.layout, selectedID: viewModel.selectedItemID)
        coordinator.syncSelectedSize(from: viewModel.layout, selectedID: viewModel.selectedItemID)
        coordinator.syncDecorState(from: viewModel.layout)
        coordinator.syncDecorCamera()
        coordinator.resolveWallPenetrationIfNeeded()
        // 이동 모드에서도 카메라 컨트롤은 그대로 둔다. 가구 드래그는 "선택된 가구 위에서 시작한
        // 한 손가락 팬"만 가로채고, 나머지(빈 곳 드래그·핀치)는 평소처럼 시점 조작이 된다.
        // 사람 뷰는 기본 카메라 컨트롤 대신 전용 제스처(시선/걷기 + 가구·벽 충돌)를 쓴다.
        let isEditingSelection = viewModel.isMovingSelectedFurniture && viewModel.selectedItemID != nil
        let isEditingDecor = viewModel.isDecorating && viewModel.pendingFigure == nil
        let isPersonMode = viewModel.viewMode == .person
        view.allowsCameraControl = !isPersonMode
        coordinator.movePanGesture?.isEnabled = isEditingSelection || isEditingDecor
        coordinator.personLookGesture?.isEnabled = isPersonMode
        coordinator.personWalkGesture?.isEnabled = isPersonMode
        coordinator.personPinchGesture?.isEnabled = isPersonMode
        coordinator.updateCameraGestureRequirements(on: view)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        // CADisplayLink가 사람뷰 coordinator를 유지하지 않도록 화면 종료 시 확실히 정리한다.
        coordinator.stopPersonComfortMotion()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, modelLoader: modelLoader)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let viewModel: RoomEditorViewModel
        let modelLoader: FurnitureModelLoader

        /// 드래그 기준 바닥만 hitTest 하기 위한 전용 카테고리 비트(다른 노드는 기본값이라 걸리지 않음).
        static let floorHitCategory = 1 << 20

        weak var sceneView: SCNView?
        var movePanGesture: UIPanGestureRecognizer?
        /// SwiftUI의 넓은 ObservableObject 갱신이 들어와도 같은 선택 노드의
        /// 하이라이트 geometry를 매번 지웠다가 만들지 않도록 현재 대상을 기억한다.
        weak var highlightedFurnitureNode: SCNNode?
        var renderedSelectedItemID: Int?
        /// 측정 모드에서 드래그 이벤트가 120Hz로 들어와도 치수 노드는 60Hz까지만
        /// 다시 만든다. 제스처 종료 시에는 마지막 위치를 강제로 한 번 반영한다.
        var lastInteractiveMeasurementRefreshTime: CFTimeInterval = 0
        let interactiveMeasurementRefreshInterval: CFTimeInterval = 1.0 / 60.0
        /// 드래그 시작 시 "손가락이 짚은 바닥 지점 → 가구 중심" 오프셋.
        /// 이걸 유지해야 가구의 잡은 부분이 손가락에 붙어 따라온다. (없으면 중심이 손가락으로 점프)
        var dragGrabOffset = SIMD2<Float>(0, 0)
        /// 프런트엔드의 figure-move interaction 대응. 소품 노드는 드래그 중 직접 움직이고,
        /// 종료 시점에만 ViewModel에 최종 위치를 커밋해 히스토리/씬 재생성을 한 번으로 제한한다.
        var draggingDecorID: Int?
        var decorDragStartPosition: SCNVector3?
        /// 벽/가구에 새로 막히는 순간(엣지)에만 햅틱을 한 번 주기 위한 상태.
        var isSnapEngaged = false
        /// require(toFail:)를 이미 걸어둔 카메라 제스처들. (중복 설정 방지)
        var cameraGestureRequirementConfigured = Set<ObjectIdentifier>()

        // MARK: 사람 뷰 상태
        var personLookGesture: UIPanGestureRecognizer?
        var personWalkGesture: UIPanGestureRecognizer?
        var personPinchGesture: UIPinchGestureRecognizer?
        /// 시선 방향(라디안). yaw 0 = -Z, pitch + = 위.
        var personYaw: Float = 0
        var personPitch: Float = 0
        /// 사용자가 요청한 시선/위치. 실제 카메라는 display link가 여기로 부드럽게 따라간다.
        /// 입력 이벤트마다 카메라를 즉시 움직이면 손가락 샘플링의 들쭉날쭉함이 그대로 눈에
        /// 전달돼 멀미가 나므로, 사람뷰에서만 목표와 실제 위치를 분리한다.
        var personTargetYaw: Float = 0
        var personTargetPitch: Float = 0
        var personTargetPosition: SIMD2<Float>?
        var personWalkVelocity = SIMD2<Float>(0, 0)
        var personMotionDisplayLink: CADisplayLink?
        var lastPersonMotionTimestamp: CFTimeInterval?
        var lastLookTranslation = CGPoint.zero
        var lastWalkTranslation = CGPoint.zero
        /// 카메라(사람 몸통)의 수평 충돌 반경(m).
        static let personBodyRadius: Float = 0.25
        /// 멀미를 줄이기 위한 보행/시선 파라미터. 실제 걷는 속도에 가깝게 제한해 장거리
        /// 탭이 화면을 훅 끌고 가는 느낌을 막고, 시선은 아주 짧은 시간만 보간해 조작 지연은 없다.
        static let personMaxTapTravel: Float = 2.8
        static let personWalkMaxSpeed: Float = 1.90
        static let personWalkAcceleration: Float = 7.5
        static let personLookResponse: Float = 0.055
        var renderedRevision = 0
        var renderedViewMode: RoomViewMode?
        var cameraLayoutSize = CGSize.zero

        let cameraNode = SCNNode()
        let furnitureContainer = SCNNode()
        /// item ID별 마지막 GLB 렌더 형태. SceneKit의 SCNNode는 userData를 제공하지 않아
        /// coordinator가 별도로 보관한다.
        var furnitureRenderSignatures: [Int: String] = [:]
        /// item ID별 마지막 피규어(꾸미기) 렌더 형태. 바뀐 책장의 피규어들만 다시 만든다.
        var decorRenderSignatures: [Int: String] = [:]
        /// 노드 생성 시점의 (표시 치수, 노드 스케일). 크기 슬라이더가 GLB를 다시 만들지 않고
        /// "기준 대비 비율"로 스케일만 조정할 수 있게 한다. (맞춤 스케일이 축별 선형이라
        /// 비율 스케일 결과는 리빌드 결과와 정확히 같다)
        var renderedBaseStates: [Int: (width: Double, depth: Double, height: Double, scale: SCNVector3)] = [:]
        /// 꾸미기 카메라가 적용된 책장 itemId. viewModel.decoratingItemID와 비교해 전환을 감지한다.
        var decorCameraItemID: Int?
        let floorNode = SCNNode()
        let measurementContainer = SCNNode()
        let selectionHighlightName = "__selection_highlight"
        var floorSide: CGFloat = 4
        /// 카메라가 바라볼 방/가구의 중심(수평). 방이 원점에서 벗어나 있어도 화면 중앙에 오게 합니다.
        var sceneCenter = SCNVector3(0, 0.4, 0)
        /// 중심에서 방을 감싸는 반경(m). 카메라 거리 산정에 사용합니다.
        var sceneRadius: Float = 3
        /// 방/가구를 모두 포함하는 수평 경계. Skyview 배율과 드래그 한계에 사용합니다.
        var sceneBounds = HorizontalBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)
        /// 실제 방 셸만의 수평 경계. 가구가 밖으로 튀어나와도 이 값은 넓히지 않습니다.
        var roomBounds = HorizontalBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)
        var wallColliders: [WallCollider] = []
        /// 벽 메우기 패널의 충돌 면. 셸 벽 콜라이더는 개구부 자리가 비어 있으므로,
        /// 메운 자리는 패널 박스로 콜라이더를 만들어 실제 벽처럼 가구 이동을 막는다.
        var infillColliders: [WallCollider] = []
        var shellViewFacingSurfaces: [WallFacingUpdater.Wall] = []
        var measurementSegments: [MeasurementSegment] = []
        var roomHeight: Float = 2.4
        /// 방 바닥의 월드 Y. 스캔 메시는 AR 좌표계라 0이 아닐 수 있고,
        /// 측정 치수선을 이 높이에 붙여야 바닥에 깔린 도면처럼 보인다.
        var floorLevel: Float = 0
        var isScannedRoom = false
        let wallMeasurementInset: Float = 0.16
        let overallMeasurementOffset: Float = 0.8
        let measurementCameraPadding: Float = 1.25
        /// 파싱한 USDZ 방 셸(가구 제거 완료)을 캐시. 재생성 때 매번 디스크에서 다시 파싱하지 않도록.
        var shellCache: [String: SCNNode] = [:]
        /// 현재 씬에 올라간 방 셸(벽 색 재적용용) 및 마지막으로 반영한 벽 색.
        weak var shellNode: SCNNode?
        var renderedWallColor = ""
        var renderedFloorColor: String?
        /// 카메라를 향한(시야를 가리는) 벽을 반투명 처리하는 렌더 델리게이트. (프런트 updateViewFacingWalls 대응)
        let wallFacingUpdater = WallFacingUpdater()

        init(viewModel: RoomEditorViewModel, modelLoader: FurnitureModelLoader) {
            self.viewModel = viewModel
            self.modelLoader = modelLoader
        }

        // MARK: - Scene construction

        func buildScene(for layout: RoomLayout) -> SCNScene {
            let scene = SCNScene()

            // These nodes are reused across rebuilds; detach from any previous scene first.
            floorNode.removeFromParentNode()
            furnitureContainer.removeFromParentNode()
            measurementContainer.removeFromParentNode()
            cameraNode.removeFromParentNode()

            // GLB(PBR) 재질이 납작/검게 나오지 않도록 이미지 기반 조명 환경.
            scene.lightingEnvironment.contents = UIColor(white: 0.85, alpha: 1)
            scene.lightingEnvironment.intensity = 1.2

            if let usdzURL = viewModel.usdzURL {
                buildScannedShell(into: scene, usdzURL: usdzURL, layout: layout)
            } else {
                buildBoxRoom(into: scene, layout: layout)
            }

            scene.rootNode.addChildNode(furnitureContainer)
            rebuildFurnitureNodes(for: layout)
            scene.rootNode.addChildNode(measurementContainer)
            rebuildMeasurementNodes()
            measurementContainer.isHidden = !viewModel.isMeasuring

            let camera = SCNCamera()
            camera.zFar = 300
            // 사람 뷰(방 안 1인칭)에서 1m 이내 벽/가구가 잘려 보이지 않도록 near plane을 당긴다.
            camera.zNear = 0.05
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 500
            scene.rootNode.addChildNode(ambient)

            let directional = SCNNode()
            directional.light = SCNLight()
            directional.light?.type = .directional
            directional.light?.intensity = 700
            directional.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
            scene.rootNode.addChildNode(directional)

            return scene
        }

        /// 면적 기반의 단순 박스 방(벽 2면 + 바닥). 서버/저장된 방 편집용.
        func buildBoxRoom(into scene: SCNScene, layout: RoomLayout) {
            isScannedRoom = false
            wallColliders = []
            shellViewFacingSurfaces = []
            wallFacingUpdater.setWalls([])
            sceneCenter = SCNVector3(0, 0.4, 0)
            let side = CGFloat((layout.space?.area ?? 16).squareRoot())
            floorSide = max(side, 2)
            sceneRadius = Float(floorSide) * 0.7
            sceneBounds = HorizontalBounds(
                minX: -Float(floorSide) / 2,
                maxX: Float(floorSide) / 2,
                minZ: -Float(floorSide) / 2,
                maxZ: Float(floorSide) / 2
            )
            roomBounds = sceneBounds
            measurementSegments = Self.measurementSegments(for: sceneBounds)
            floorLevel = 0
            let wallHeight = CGFloat(layout.space?.ceilingHeight ?? 2.4)
            roomHeight = Float(wallHeight)
            let wallColor = UIColor(hexString: layout.space?.wallColor ?? "#F2EDE5")

            let floor = SCNBox(width: floorSide, height: 0.05, length: floorSide, chamferRadius: 0)
            let floorMaterial = SCNMaterial()
            floorMaterial.diffuse.contents = UIColor(hexString: layout.space?.floorColor ?? "#DECCB3")
            floor.materials = [floorMaterial]
            floorNode.geometry = floor
            floorNode.name = "floor"
            floorNode.categoryBitMask = Coordinator.floorHitCategory
            floorNode.position = SCNVector3(0, -0.025, 0)
            scene.rootNode.addChildNode(floorNode)

            for (position, rotationY) in [
                (SCNVector3(0, Float(wallHeight / 2), Float(-floorSide / 2)), Float(0)),
                (SCNVector3(Float(-floorSide / 2), Float(wallHeight / 2), 0), Float.pi / 2)
            ] {
                let wall = SCNBox(width: floorSide, height: wallHeight, length: 0.04, chamferRadius: 0)
                let material = SCNMaterial()
                material.diffuse.contents = wallColor
                wall.materials = [material]
                let node = SCNNode(geometry: wall)
                node.position = position
                node.eulerAngles.y = rotationY
                scene.rootNode.addChildNode(node)
            }
        }

        /// 실제 스캔 방 메시(USDZ)에서 벽/바닥(Arch_grp)만 남기고 가구(Object_grp)는 제거,
        /// 그 위에서 실물 GLB 가구를 편집합니다. 드래그 이동용 투명 바닥판을 함께 깝니다.
        func buildScannedShell(into scene: SCNScene, usdzURL: URL, layout: RoomLayout) {
            isScannedRoom = true
            shellViewFacingSurfaces = []
            roomHeight = Float(layout.space?.ceilingHeight ?? 2.4)
            let wallColor = UIColor(hexString: layout.space?.wallColor ?? "#F2EDE5")
            let floorColor = layout.space?.floorColor
            var scannedBounds: HorizontalBounds?
            var meshFloorY: Float?

            if let template = shellTemplate(for: usdzURL) {
                let shell = template.clone()
                // 벽 색상을 스캔 벽 메시에도 반영.
                tintWalls(in: shell, color: wallColor)
                if let floorColor {
                    tintFloors(in: shell, color: UIColor(hexString: floorColor))
                }
                scene.rootNode.addChildNode(shell)
                shellNode = shell
                renderedWallColor = layout.space?.wallColor ?? "#F2EDE5"
                renderedFloorColor = floorColor
                scannedBounds = Self.horizontalBounds(of: shell)
                meshFloorY = Self.shellFloorY(of: shell)
                let center = scannedBounds.map { SCNVector3($0.centerX, 0, $0.centerZ) } ?? SCNVector3(0, 0, 0)
                wallColliders = Self.makeWallColliders(from: shell, roomCenter: center)
                measurementSegments = wallColliders
                    .filter { $0.length >= 0.35 }
                    .map { MeasurementSegment(center: $0.center, normal: $0.normal, length: $0.length) }
                shellViewFacingSurfaces = Self.makeViewFacingSurfaces(from: wallColliders)
                shellViewFacingSurfaces += Self.makeDoorWindowViewFacingSurfaces(from: shell, roomCenter: center)
                refreshViewFacingTransparencyTargets()
            }

            roomBounds = scannedBounds ?? .defaultRoom
            if measurementSegments.isEmpty {
                measurementSegments = Self.measurementSegments(for: roomBounds)
            }
            sceneBounds = roomBounds
            sceneBounds.expand(by: 0.35)

            sceneCenter = SCNVector3(sceneBounds.centerX, 0.4, sceneBounds.centerZ)
            sceneRadius = max(sceneBounds.radius, 1.5)
            floorSide = CGFloat(max(sceneBounds.width, sceneBounds.depth) + 1.5)

            let dragFloor = SCNBox(width: floorSide * 3, height: 0.01, length: floorSide * 3, chamferRadius: 0)
            let floorMaterial = SCNMaterial()
            floorMaterial.diffuse.contents = UIColor.clear
            floorMaterial.transparency = 0.001
            floorMaterial.writesToDepthBuffer = false
            floorMaterial.readsFromDepthBuffer = false
            dragFloor.materials = [floorMaterial]
            floorNode.geometry = dragFloor
            floorNode.name = "floor"
            floorNode.categoryBitMask = Coordinator.floorHitCategory
            // 바닥 높이는 방 메시(Floor mesh)에서 찾는 것을 우선한다. 가구 최저 Y로만 잡으면
            // 모든 가구를 띄워 저장한 방에서 그 높이가 새 바닥으로 굳어(F12) 슬라이더 0점,
            // 새 가구 배치, 드래그 평면, 사람 뷰 눈높이가 전부 떠 버린다.
            // 가구 바닥과 메시 바닥이 거의 같으면(정상 배치) 가구 값을 유지해 기존 저장분의
            // 높이 슬라이더가 0에서 흔들리지 않게 한다.
            let furnitureFloorY = layout.furnitures.map { Float($0.position.y) }.min()
            let floorLevel: Float
            if let meshFloorY {
                if let furnitureFloorY, abs(furnitureFloorY - meshFloorY) < 0.1 {
                    floorLevel = furnitureFloorY
                } else {
                    floorLevel = meshFloorY
                }
            } else {
                floorLevel = furnitureFloorY ?? -0.005
            }
            self.floorLevel = floorLevel
            viewModel.adoptFloorY(Double(floorLevel))
            floorNode.position = SCNVector3(sceneCenter.x, floorLevel, sceneCenter.z)
            scene.rootNode.addChildNode(floorNode)
        }

        /// 스캔 셸에서 실제 바닥 높이(월드 Y)를 찾는다. Floor/Ground/Slab mesh의 윗면을
        /// 우선 쓰고, 없으면 셸 전체의 최저점으로 근사한다. (RoomPlan 좌표계는 바닥이
        /// y=0이 아닐 수 있어, 가구 최저 Y 추정만으로는 띄운 가구가 바닥을 끌어올린다)
        static func shellFloorY(of root: SCNNode) -> Float? {
            var floorTop: Float?
            var overallMin: Float?

            func visit(_ node: SCNNode) {
                if node.geometry != nil {
                    let (minBounds, maxBounds) = node.boundingBox
                    let corners = [
                        SCNVector3(minBounds.x, minBounds.y, minBounds.z),
                        SCNVector3(maxBounds.x, minBounds.y, minBounds.z),
                        SCNVector3(minBounds.x, maxBounds.y, minBounds.z),
                        SCNVector3(maxBounds.x, maxBounds.y, minBounds.z),
                        SCNVector3(minBounds.x, minBounds.y, maxBounds.z),
                        SCNVector3(maxBounds.x, minBounds.y, maxBounds.z),
                        SCNVector3(minBounds.x, maxBounds.y, maxBounds.z),
                        SCNVector3(maxBounds.x, maxBounds.y, maxBounds.z)
                    ].map { node.convertPosition($0, to: nil) }
                    if let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max() {
                        overallMin = min(overallMin ?? minY, minY)
                        if isFloorGeometryNode(node) {
                            floorTop = max(floorTop ?? maxY, maxY)
                        }
                    }
                }
                node.childNodes.forEach(visit)
            }

            visit(root)
            return floorTop ?? overallMin
        }

        /// 가구(Object_grp)를 제거한 방 셸 템플릿. 처음 한 번만 파싱하고 캐시합니다.
        func shellTemplate(for usdzURL: URL) -> SCNNode? {
            let key = usdzURL.path
            if let cached = shellCache[key] { return cached }
            guard let roomScene = try? SCNScene(url: usdzURL) else { return nil }
            let template = SCNNode()
            template.name = "room-shell"
            for child in roomScene.rootNode.childNodes {
                template.addChildNode(child)
            }
            while let furnitureGroup = template.childNode(withName: "Object_grp", recursively: true) {
                furnitureGroup.removeFromParentNode()
            }
            shellCache[key] = template
            return template
        }

        /// 벽 색이 바뀐 경우에만 현재 셸 벽을 다시 칠합니다. (전체 씬 재생성 없이)
        func retintWallsIfNeeded(to hex: String) {
            guard hex != renderedWallColor else { return }
            renderedWallColor = hex
            if let shellNode {
                tintWalls(in: shellNode, color: UIColor(hexString: hex))
            }
        }

        /// 프런트엔드 applyRoomFloorColor 대응. 바닥색을 지정하지 않은 스캔은
        /// 원본 USDZ 재질을 보존하고, 사용자가 선택한 경우에만 Floor/Ground/Slab mesh를 tint합니다.
        func retintFloorsIfNeeded(to hex: String?) {
            guard hex != renderedFloorColor else { return }
            renderedFloorColor = hex
            guard let shellNode, let hex else { return }
            tintFloors(in: shellNode, color: UIColor(hexString: hex))
        }

        /// 스캔 벽 메시(이름에 "Wall" 포함)의 diffuse를 선택한 벽 색으로 덮습니다.
        func tintWalls(in node: SCNNode, color: UIColor) {
            if let name = node.name, name.localizedCaseInsensitiveContains("wall"), let geometry = node.geometry {
                geometry.materials.forEach { $0.diffuse.contents = color }
            }
            node.childNodes.forEach { tintWalls(in: $0, color: color) }
        }

        func tintFloors(in node: SCNNode, color: UIColor) {
            if Self.isFloorGeometryNode(node), let geometry = node.geometry {
                geometry.materials.forEach { $0.diffuse.contents = color }
            }
            node.childNodes.forEach { tintFloors(in: $0, color: color) }
        }

        func syncSelectedRotation(from layout: RoomLayout, selectedID: Int?) {
            guard let selectedID,
                  let item = layout.furnitures.first(where: { $0.itemId == selectedID }),
                  let node = furnitureContainer.childNode(withName: "furniture-\(selectedID)", recursively: false) else { return }
            let rotationY = Float(item.rotation.y)
            let positionY = Float(item.position.y)
            let didChange = abs(node.eulerAngles.y - rotationY) > 0.0001
                || abs(node.position.y - positionY) > 0.0001
            guard didChange else { return }
            node.eulerAngles.y = rotationY
            // 높이(수직) 슬라이더 값을 바로 반영. x/z는 드래그가 관리하므로 y만 맞춘다.
            node.position.y = positionY
            syncDecorContainer(forItemID: selectedID)
            if viewModel.isMeasuring {
                rebuildMeasurementNodes()
            }
        }

        /// 크기 슬라이더 값을 리빌드 없이 반영한다. 노드 생성 시점의 (치수, 스케일)을 기준으로
        /// "새 치수 / 기준 치수" 비율만 곱한다 — GLB 맞춤 스케일이 축별 선형이라 리빌드와 결과가 같다.
        func syncSelectedSize(from layout: RoomLayout, selectedID: Int?) {
            guard let selectedID,
                  let item = layout.furnitures.first(where: { $0.itemId == selectedID }),
                  !RoomEditorViewModel.isWallInfill(item),
                  let base = renderedBaseStates[selectedID],
                  let node = furnitureContainer.childNode(withName: "furniture-\(selectedID)", recursively: false) else { return }
            let display = displayFurniture(for: item)
            let ratioX = Float(((display.width ?? 0.5) * display.scale.x) / max(base.width, 0.001))
            let ratioY = Float(((display.height ?? 0.5) * display.scale.y) / max(base.height, 0.001))
            let ratioZ = Float(((display.depth ?? 0.5) * display.scale.z) / max(base.depth, 0.001))
            let target = SCNVector3(base.scale.x * ratioX, base.scale.y * ratioY, base.scale.z * ratioZ)
            guard abs(node.scale.x - target.x) > 0.0001
                || abs(node.scale.y - target.y) > 0.0001
                || abs(node.scale.z - target.z) > 0.0001 else { return }
            node.scale = target
            if viewModel.isMeasuring {
                rebuildMeasurementNodes()
            }
        }

        func applySelection(itemID: Int?) {
            let selectedNode = itemID.flatMap {
                furnitureContainer.childNode(withName: "furniture-\($0)", recursively: false)
            }
            if renderedSelectedItemID == itemID {
                if itemID == nil, highlightedFurnitureNode == nil { return }
                if let selectedNode, highlightedFurnitureNode === selectedNode { return }
            }

            highlightedFurnitureNode?.childNode(
                withName: selectionHighlightName,
                recursively: false
            )?.removeFromParentNode()
            highlightedFurnitureNode = nil
            renderedSelectedItemID = itemID

            guard let selectedNode else { return }
            addSelectionHighlight(to: selectedNode)
            highlightedFurnitureNode = selectedNode
        }

        func removeSelectionHighlight(from node: SCNNode) {
            node.childNode(withName: selectionHighlightName, recursively: false)?.removeFromParentNode()
        }

        func addSelectionHighlight(to node: SCNNode) {
            guard let bounds = Self.localHierarchyBounds(of: node) else { return }
            let width = max(CGFloat(bounds.max.x - bounds.min.x) + 0.06, 0.08)
            let height = max(CGFloat(bounds.max.y - bounds.min.y) + 0.06, 0.08)
            let depth = max(CGFloat(bounds.max.z - bounds.min.z) + 0.06, 0.08)

            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.01)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.95, green: 0.69, blue: 0.36, alpha: 1)
            material.emission.contents = UIColor(red: 0.95, green: 0.69, blue: 0.36, alpha: 0.45)
            material.fillMode = .lines
            material.isDoubleSided = true
            box.materials = [material]

            let highlight = SCNNode(geometry: box)
            highlight.name = selectionHighlightName
            highlight.position = SCNVector3(
                (bounds.min.x + bounds.max.x) / 2,
                (bounds.min.y + bounds.max.y) / 2,
                (bounds.min.z + bounds.max.z) / 2
            )
            node.addChildNode(highlight)
        }

        func setMeasurementVisible(_ isVisible: Bool) {
            let didChange = measurementContainer.isHidden == isVisible
            guard didChange else { return }
            if isVisible {
                rebuildMeasurementNodes()
            }
            measurementContainer.isHidden = !isVisible
            if didChange, viewModel.viewMode == .skyView {
                applyCamera(mode: viewModel.viewMode, animated: true)
            }
        }

        /// 가구 드래그 중 실시간 치수 표시를 유지하되, 매 터치 샘플마다 텍스트/선 geometry를
        /// 전부 재생성하지 않는다. 종료 이벤트는 force로 최종 위치를 빠짐없이 반영한다.
        func rebuildMeasurementsDuringInteraction(
            at timestamp: CFTimeInterval = CACurrentMediaTime(),
            force: Bool = false
        ) {
            guard viewModel.isMeasuring else { return }
            guard force
                    || timestamp - lastInteractiveMeasurementRefreshTime >= interactiveMeasurementRefreshInterval else {
                return
            }
            lastInteractiveMeasurementRefreshTime = timestamp
            rebuildMeasurementNodes()
        }

        func rebuildMeasurementNodes() {
            measurementContainer.childNodes.forEach { $0.removeFromParentNode() }

            // 뷰별로 다른 구성:
            //  - 스캔룸 스카이뷰: 전체 가로/세로만 표시해 도면을 가리지 않음
            //  - 박스룸 스카이뷰: 벽별 치수 + 전체 가로/세로
            //  - 3D: 전체 가로/세로/높이만
            let isSkyview = viewModel.viewMode == .skyView
            addOverallMeasurementNodes(includeHeight: !isSkyview)
            if isSkyview {
                // 탑다운에서는 세로 높이선이 점으로 보여 쓸 수 없으므로 라벨로 표기한다.
                addSkyviewHeightLabel()
            }
            guard isSkyview, !isScannedRoom else { return }

            // 아주 짧은 턱(60cm 미만)과, 전체 치수와 사실상 같은(95% 이상) 벽 치수는
            // 나란히 두 줄로 겹쳐 보이기만 해서 생략.
            let bounds = dynamicOverallBounds()
            let filteredSegments = measurementSegments.filter { segment in
                guard segment.length >= 0.6 else { return false }
                let direction = Self.dimensionDirection(for: segment.normal)
                let total = abs(direction.x) > abs(direction.z) ? bounds.width : bounds.depth
                return segment.length < total * 0.95
            }
            for segment in filteredSegments {
                // 벽 "바깥"에 두면 ㄱ자(오목)로 꺾인 방에서는 다른 날개의 내부를 가로질러
                // 떠 보인다. 도면처럼 각 벽의 "안쪽"에 바짝 붙여(normal은 방 안쪽 방향)
                // 방 모양과 상관없이 항상 자기 벽을 따라 정렬되게 한다.
                addHorizontalDimensionLine(
                    center: segment.center,
                    direction: Self.dimensionDirection(for: segment.normal),
                    normal: segment.normal,
                    length: segment.length,
                    label: Self.formatCentimeters(segment.length),
                    y: floorLevel + 0.02,
                    offset: wallMeasurementInset,
                    style: .wall
                )
            }
            // 프론트엔드 측정모드는 벽 치수(가로/세로/높이)만 보여주고 가구별 치수 라벨은 두지 않습니다.
        }

        func addOverallMeasurementNodes(includeHeight: Bool) {
            let bounds = dynamicOverallBounds()
            // 전체 치수는 벽별 치수(0.35)보다 더 바깥(0.8)에 둬 도면처럼 층이 지게 한다.
            addHorizontalDimensionLine(
                center: SCNVector3(bounds.centerX, 0, bounds.maxZ),
                direction: SCNVector3(1, 0, 0),
                normal: SCNVector3(0, 0, 1),
                length: bounds.width,
                label: Self.formatCentimeters(bounds.width),
                y: floorLevel + 0.03,
                offset: overallMeasurementOffset,
                style: .overall
            )
            addHorizontalDimensionLine(
                center: SCNVector3(bounds.maxX, 0, bounds.centerZ),
                direction: SCNVector3(0, 0, 1),
                normal: SCNVector3(1, 0, 0),
                length: bounds.depth,
                label: Self.formatCentimeters(bounds.depth),
                y: floorLevel + 0.03,
                offset: overallMeasurementOffset,
                style: .overall
            )
            if includeHeight {
                // 높이선은 방 모서리 바로 옆에 붙여야 "이 방의 높이"로 읽힌다.
                // (가로/세로선처럼 0.8까지 빼면 허공에 떠 있는 것처럼 보임)
                addVerticalDimensionLine(
                    position: SCNVector3(bounds.maxX + 0.2, floorLevel + roomHeight / 2, bounds.maxZ + 0.2),
                    height: roomHeight,
                    label: Self.formatCentimeters(roomHeight),
                    style: .overall
                )
            }
        }

        /// 스카이뷰 전용 높이 표기: 세로(깊이) 치수선과 같은 열, 방 위쪽 모서리 바깥에 라벨로 띄운다.
        func addSkyviewHeightLabel() {
            let bounds = dynamicOverallBounds()
            let label = Self.makeMeasurementLabel(
                text: "높이 \(Self.formatCentimeters(roomHeight))",
                style: .overall
            )
            label.position = SCNVector3(bounds.maxX + 0.8, floorLevel + 0.02, bounds.minZ - 0.35)
            measurementContainer.addChildNode(label)
        }

        func addObjectMeasurementNodes() {
            for furniture in viewModel.layout.furnitures {
                guard let node = furnitureContainer.childNode(withName: "furniture-\(furniture.itemId)", recursively: false) else {
                    continue
                }
                let renderFurniture = displayFurniture(for: furniture)
                let text = [
                    "X \(Self.formatMeters(Float(renderFurniture.width ?? 0)))",
                    "Y \(Self.formatMeters(Float(renderFurniture.height ?? 0)))",
                    "Z \(Self.formatMeters(Float(renderFurniture.depth ?? 0)))"
                ].joined(separator: "  ")
                let label = Self.makeMeasurementLabel(text: text, style: .object)
                label.name = "__measurement_label"
                let basePosition = node.convertPosition(.init(0, 0, 0), to: nil)
                label.position = SCNVector3(
                    basePosition.x,
                    basePosition.y + Float(renderFurniture.height ?? 0.8) + 0.18,
                    basePosition.z
                )
                measurementContainer.addChildNode(label)
            }
        }

        func dynamicOverallBounds() -> HorizontalBounds {
            var bounds = roomBounds
            for furniture in viewModel.layout.furnitures {
                guard let node = furnitureContainer.childNode(withName: "furniture-\(furniture.itemId)", recursively: false) else {
                    continue
                }
                let renderFurniture = displayFurniture(for: furniture)
                let footprint = Self.rotatedFootprint(for: renderFurniture)
                bounds = HorizontalBounds.union(bounds, HorizontalBounds(
                    minX: node.position.x - footprint.x,
                    maxX: node.position.x + footprint.x,
                    minZ: node.position.z - footprint.z,
                    maxZ: node.position.z + footprint.z
                )) ?? bounds
            }
            return bounds
        }

        func addHorizontalDimensionLine(
            center: SCNVector3,
            direction: SCNVector3,
            normal: SCNVector3,
            length: Float,
            label: String,
            y: Float,
            offset: Float,
            style: MeasurementLabelStyle
        ) {
            guard length > 0.05 else { return }
            let tangent = direction.normalizedXZ
            let outward = normal.normalizedXZ
            let lineCenter = SCNVector3(
                center.x + outward.x * offset,
                y,
                center.z + outward.z * offset
            )
            let half = length / 2
            let start = SCNVector3(lineCenter.x - tangent.x * half, y, lineCenter.z - tangent.z * half)
            let end = SCNVector3(lineCenter.x + tangent.x * half, y, lineCenter.z + tangent.z * half)
            measurementContainer.addChildNode(Self.makeHorizontalStroke(
                center: lineCenter,
                direction: tangent,
                length: length,
                style: style
            ))
            measurementContainer.addChildNode(Self.makeHorizontalStroke(
                center: start,
                direction: outward,
                length: 0.20,
                style: style
            ))
            measurementContainer.addChildNode(Self.makeHorizontalStroke(
                center: end,
                direction: outward,
                length: 0.20,
                style: style
            ))

            // 라벨은 선과 겹치지 않게 선 옆(수직 방향)으로 밀어 둔다.
            // 탑다운(스카이뷰)에서는 y 오프셋이 안 보이므로 수평 오프셋이 충분히 커야 한다.
            let textNode = Self.makeMeasurementLabel(text: label, style: style)
            textNode.position = SCNVector3(
                lineCenter.x + outward.x * 0.3,
                y + 0.16,
                lineCenter.z + outward.z * 0.3
            )
            measurementContainer.addChildNode(textNode)
        }

        /// `position`은 선의 "중심"이다. 눈금/라벨도 같은 중심 기준으로 배치해야
        /// 바닥이 y=0이 아닌 스캔 방에서도 선·눈금·라벨이 어긋나지 않는다.
        func addVerticalDimensionLine(position: SCNVector3, height: Float, label: String, style: MeasurementLabelStyle) {
            guard height > 0.05 else { return }
            let bottomY = position.y - height / 2
            let topY = position.y + height / 2
            measurementContainer.addChildNode(Self.makeVerticalStroke(center: position, height: height, style: style))
            measurementContainer.addChildNode(Self.makeHorizontalStroke(
                center: SCNVector3(position.x, bottomY, position.z),
                direction: SCNVector3(1, 0, 0),
                length: 0.18,
                style: style
            ))
            measurementContainer.addChildNode(Self.makeHorizontalStroke(
                center: SCNVector3(position.x, topY, position.z),
                direction: SCNVector3(1, 0, 0),
                length: 0.18,
                style: style
            ))
            let textNode = Self.makeMeasurementLabel(text: label, style: style)
            textNode.position = SCNVector3(position.x + 0.12, position.y, position.z)
            measurementContainer.addChildNode(textNode)
        }

        static func makeHorizontalStroke(center: SCNVector3, direction: SCNVector3, length: Float, style: MeasurementLabelStyle) -> SCNNode {
            let box = SCNBox(width: CGFloat(max(length, 0.01)), height: 0.012, length: 0.012, chamferRadius: 0)
            box.materials = [measurementMaterial(color: style.lineColor)]
            let node = SCNNode(geometry: box)
            node.position = center
            node.eulerAngles.y = -atan2f(direction.z, direction.x)
            node.renderingOrder = 40
            return node
        }

        static func makeVerticalStroke(center: SCNVector3, height: Float, style: MeasurementLabelStyle) -> SCNNode {
            let box = SCNBox(width: 0.012, height: CGFloat(max(height, 0.01)), length: 0.012, chamferRadius: 0)
            box.materials = [measurementMaterial(color: style.lineColor)]
            let node = SCNNode(geometry: box)
            node.position = center
            node.renderingOrder = 40
            return node
        }

        static func measurementMaterial(color: UIColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            material.lightingModel = .constant
            material.isDoubleSided = true
            // 프론트엔드처럼 벽/가구에 가려지지 않고 항상 보이도록 깊이 테스트를 끈다.
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            return material
        }

        static func dimensionDirection(for normal: SCNVector3) -> SCNVector3 {
            SCNVector3(-normal.z, 0, normal.x).normalizedXZ
        }

        static func makeMeasurementLabel(text: String, style: MeasurementLabelStyle) -> SCNNode {
            let (image, pixelSize) = measurementLabelImage(text: text, style: style)
            // 텍스트 높이(월드)를 기준으로 이미지 비율에 맞춰 평면 크기를 정해, 글자가 라벨을 꽉 채우게 한다.
            let worldHeight = style.labelWorldHeight
            let aspect = pixelSize.width / max(pixelSize.height, 1)
            let plane = SCNPlane(width: worldHeight * aspect, height: worldHeight)
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.emission.contents = image
            material.lightingModel = .constant
            material.isDoubleSided = true
            // 라벨도 벽/가구에 가려지지 않고 항상 보이게 (프론트엔드 CSS2D 라벨과 동일한 느낌).
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            node.constraints = [billboard]
            node.renderingOrder = 41
            return node
        }

        /// 텍스트에 꼭 맞는(여백 최소) 고해상도 라벨 이미지와 그 픽셀 크기를 함께 반환합니다.
        static func measurementLabelImage(text: String, style: MeasurementLabelStyle) -> (image: UIImage, size: CGSize) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let font = UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.textColor,
                // 다크모드에서는 흰 글자 둘레를 어둡게 둘러 밝은 바닥/벽 위에서도 구분한다.
                // 라이트모드는 기존 흰 후광을 유지한다.
                .strokeColor: style.textHaloColor,
                .strokeWidth: -3.0
            ]
            let lineSizes = lines.map { ($0 as NSString).size(withAttributes: attributes) }
            let textWidth = lineSizes.map { $0.width }.max() ?? 1
            let lineHeight = lineSizes.map { $0.height }.max() ?? 1
            let padX: CGFloat = 22
            let padY: CGFloat = 14
            let size = CGSize(
                width: max(textWidth + padX * 2, 1),
                height: max(lineHeight * CGFloat(lines.count) + padY * 2, 1)
            )
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                context.cgContext.clear(CGRect(origin: .zero, size: size))
                var y = padY
                for (index, line) in lines.enumerated() {
                    let lineWidth = lineSizes[index].width
                    (line as NSString).draw(
                        at: CGPoint(x: (size.width - lineWidth) / 2, y: y),
                        withAttributes: attributes
                    )
                    y += lineHeight
                }
            }
            return (image, size)
        }

        static func formatMeters(_ value: Float) -> String {
            String(format: "%.2fm", value)
        }

        /// 프론트엔드와 동일하게 치수를 cm 정수로 표기합니다. (예: 3.5m → "350 cm")
        static func formatCentimeters(_ value: Float) -> String {
            "\(max(Int((value * 100).rounded()), 1)) cm"
        }

        func refreshViewFacingTransparencyTargets() {
            guard isScannedRoom else {
                wallFacingUpdater.setWalls([])
                return
            }
            wallFacingUpdater.setWalls(shellViewFacingSurfaces + furnitureDoorWindowViewFacingSurfaces())
        }

        static func makeViewFacingSurfaces(from colliders: [WallCollider]) -> [WallFacingUpdater.Wall] {
            // 충돌은 triangle별로 세분화하지만, 투명화는 같은 mesh에 대해 한 번만 처리한다.
            // 그렇지 않으면 스캔 mesh의 수백 개 face가 렌더 프레임마다 같은 material을 반복
            // 변경해 사람뷰 프레임이 떨어질 수 있다.
            var seenNodes = Set<ObjectIdentifier>()
            return colliders.compactMap { collider in
                guard let node = collider.node,
                      seenNodes.insert(ObjectIdentifier(node)).inserted else {
                    return nil
                }
                return WallFacingUpdater.Wall(
                    node: node,
                    centerXZ: SIMD2(collider.center.x, collider.center.z),
                    normalXZ: SIMD2(collider.normal.x, collider.normal.z)
                )
            }
        }

        static func makeDoorWindowViewFacingSurfaces(from root: SCNNode, roomCenter: SCNVector3) -> [WallFacingUpdater.Wall] {
            var surfaces: [WallFacingUpdater.Wall] = []

            func visit(_ node: SCNNode) {
                if isDoorWindowGeometryNode(node), let collider = WallCollider(node: node, roomCenter: roomCenter) {
                    surfaces += makeViewFacingSurfaces(from: [collider])
                }
                node.childNodes.forEach(visit)
            }

            visit(root)
            return surfaces
        }

        func furnitureDoorWindowViewFacingSurfaces() -> [WallFacingUpdater.Wall] {
            let roomCenter = SCNVector3(roomBounds.centerX, 0, roomBounds.centerZ)
            return viewModel.layout.furnitures.compactMap { furniture in
                guard Self.isDoorOrWindow(furniture),
                      let node = furnitureContainer.childNode(withName: "furniture-\(furniture.itemId)", recursively: false) else {
                    return nil
                }
                let renderFurniture = displayFurniture(for: furniture)
                let center = node.presentation.position
                let rotationY = Float(renderFurniture.rotation.y)
                var normal = SCNVector3(sinf(rotationY), 0, cosf(rotationY)).normalizedXZ
                let toRoomCenter = SCNVector3(roomCenter.x - center.x, 0, roomCenter.z - center.z)
                if normal.dotXZ(toRoomCenter) < 0 {
                    normal = SCNVector3(-normal.x, 0, -normal.z)
                }
                return WallFacingUpdater.Wall(
                    node: node,
                    centerXZ: SIMD2(center.x, center.z),
                    normalXZ: SIMD2(normal.x, normal.z)
                )
            }
        }

        static func isWallGeometryNode(_ node: SCNNode) -> Bool {
            guard node.geometry != nil else { return false }
            var current: SCNNode? = node
            var hasWallName = false
            while let candidate = current {
                let name = candidate.name ?? ""
                if name.localizedCaseInsensitiveContains("door") ||
                    name.localizedCaseInsensitiveContains("window") {
                    return false
                }
                if name.range(of: #"^Wall(_\d+_grp|\d+)$"#, options: [.regularExpression, .caseInsensitive]) != nil ||
                    name.localizedCaseInsensitiveContains("wall") {
                    hasWallName = true
                }
                current = candidate.parent
            }
            return hasWallName
        }

        /// 프런트엔드 isUsdFloorMesh와 같은 이름 기반 판별.
        /// 문/창문 메시는 이름에 바닥 관련 단어가 있어도 색칠하지 않습니다.
        static func isFloorGeometryNode(_ node: SCNNode) -> Bool {
            guard node.geometry != nil else { return false }
            var current: SCNNode? = node
            while let candidate = current {
                let name = candidate.name ?? ""
                if isDoorOrWindowName(name) {
                    return false
                }
                if name.localizedCaseInsensitiveContains("floor") ||
                    name.localizedCaseInsensitiveContains("ground") ||
                    name.localizedCaseInsensitiveContains("slab") {
                    return true
                }
                current = candidate.parent
            }
            return false
        }

        static func isDoorWindowGeometryNode(_ node: SCNNode) -> Bool {
            guard node.geometry != nil else { return false }
            var current: SCNNode? = node
            while let candidate = current {
                if isDoorOrWindowName(candidate.name) {
                    return true
                }
                current = candidate.parent
            }
            return false
        }

        static func isDoorOrWindow(_ furniture: PlacedFurniture) -> Bool {
            isDoorOrWindowName(furniture.furnitureName) || isDoorOrWindowName(furniture.modelName)
        }

        static func isDoorOrWindowName(_ name: String?) -> Bool {
            guard let name else { return false }
            return name.localizedCaseInsensitiveContains("door") ||
                name.localizedCaseInsensitiveContains("window") ||
                name.localizedCaseInsensitiveContains("문") ||
                name.localizedCaseInsensitiveContains("창문")
        }

        static func measurementSegments(for bounds: HorizontalBounds) -> [MeasurementSegment] {
            [
                MeasurementSegment(
                    center: SCNVector3(bounds.centerX, 0, bounds.minZ),
                    normal: SCNVector3(0, 0, 1),
                    length: bounds.width
                ),
                MeasurementSegment(
                    center: SCNVector3(bounds.centerX, 0, bounds.maxZ),
                    normal: SCNVector3(0, 0, -1),
                    length: bounds.width
                ),
                MeasurementSegment(
                    center: SCNVector3(bounds.minX, 0, bounds.centerZ),
                    normal: SCNVector3(1, 0, 0),
                    length: bounds.depth
                ),
                MeasurementSegment(
                    center: SCNVector3(bounds.maxX, 0, bounds.centerZ),
                    normal: SCNVector3(-1, 0, 0),
                    length: bounds.depth
                )
            ]
        }
    }
}

struct MeasurementSegment {
    var center: SCNVector3
    var normal: SCNVector3
    var length: Float
}

enum MeasurementLabelStyle {
    case wall
    case object
    case overall

    var lineColor: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(white: 1, alpha: 0.96)
            }
            switch self {
            // 라이트모드 도면 스타일: 치수선/눈금은 기존 진한 색 유지.
            case .wall, .overall:
                return UIColor(white: 0.10, alpha: 0.95)
            case .object:
                return UIColor(red: 0.20, green: 0.27, blue: 0.32, alpha: 0.88)
            }
        }
    }

    var textColor: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return .white
            }
            switch self {
            // 라이트모드 도면 스타일: 라벨도 기존 진한 색 유지.
            case .wall, .overall:
                return UIColor(white: 0.08, alpha: 1)
            case .object:
                return UIColor(red: 0.12, green: 0.20, blue: 0.24, alpha: 1)
            }
        }
    }

    var textHaloColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.02, alpha: 0.82)
                : UIColor.white.withAlphaComponent(0.9)
        }
    }

    /// 라벨 텍스트의 월드 높이(m). 클수록 화면에서 글자가 커집니다.
    var labelWorldHeight: CGFloat {
        switch self {
        case .overall: 0.17
        case .wall: 0.15
        case .object: 0.14
        }
    }
}

struct FurnitureFootprint {
    var halfWidth: Float
    var halfDepth: Float
    var rotationY: Float

    private var xAxis: SCNVector3 {
        SCNVector3(cosf(rotationY), 0, -sinf(rotationY))
    }

    private var zAxis: SCNVector3 {
        SCNVector3(sinf(rotationY), 0, cosf(rotationY))
    }

    func projectionRadius(on axis: SCNVector3) -> Float {
        abs(axis.dotXZ(xAxis)) * halfWidth + abs(axis.dotXZ(zAxis)) * halfDepth
    }

    func contains(point: SIMD2<Float>, center: SIMD2<Float>, padding: Float = 0) -> Bool {
        let relative = SCNVector3(point.x - center.x, 0, point.y - center.y)
        let localX = relative.dotXZ(xAxis)
        let localZ = relative.dotXZ(zAxis)
        return abs(localX) < halfWidth + padding && abs(localZ) < halfDepth + padding
    }
}

struct WallCollider {
    var normal: SCNVector3
    var projection: Float
    var lengthAxis: SCNVector3
    var lengthCenter: Float
    var halfLength: Float
    /// 벽 메시 노드(카메라 방향에 따라 반투명 처리용) 및 수평 중심.
    weak var node: SCNNode?
    var center: SCNVector3

    init?(node: SCNNode, roomCenter: SCNVector3) {
        // 축 정렬 bounding box의 8개 꼭짓점만 쓰면 대각선 벽이 실제보다 넓은 사각형
        // 충돌 영역으로 부풀어 난다. 프런트엔드 wallColliders처럼 실제 geometry 정점을
        // 월드 좌표로 변환해 벽의 길이·두께·방향을 계산한다.
        let points = Self.worldGeometryPoints(of: node)
        guard points.count >= 3,
              let lengthAxis = Self.dominantHorizontalAxis(points) else { return nil }

        let candidateNormal = SCNVector3(-lengthAxis.z, 0, lengthAxis.x).normalizedXZ
        guard candidateNormal.lengthXZ > 0 else { return nil }

        let normalRange = Self.projectionRange(points, axis: candidateNormal)
        let lengthRange = Self.projectionRange(points, axis: lengthAxis)
        guard normalRange.max > normalRange.min,
              lengthRange.max - lengthRange.min > 0.05 else { return nil }

        let roomSide: Float = roomCenter.dotXZ(candidateNormal) >= (normalRange.min + normalRange.max) / 2 ? 1 : -1
        normal = SCNVector3(candidateNormal.x * roomSide, 0, candidateNormal.z * roomSide).normalizedXZ
        projection = roomSide > 0 ? normalRange.max : -normalRange.min
        self.lengthAxis = lengthAxis
        lengthCenter = (lengthRange.min + lengthRange.max) / 2
        halfLength = (lengthRange.max - lengthRange.min) / 2
        self.node = node
        let sumX = points.reduce(Float(0)) { $0 + $1.x }
        let sumZ = points.reduce(Float(0)) { $0 + $1.z }
        center = SCNVector3(sumX / Float(points.count), 0, sumZ / Float(points.count))
    }

    /// 스캔된 벽의 실제 삼각형 face마다 만든 콜라이더.
    ///
    /// 하나의 Wall mesh에는 서로 다른 방향의 대각선/ㄱ자 면이 섞일 수 있다. 전체 정점으로
    /// 한 축을 추정하면 그 면들이 만든 빈 공간까지 벽으로 취급하게 된다. 웹의
    /// `worldWallFaceCollidersFromGeometry`와 동일하게 수직에 가까운 각 triangle만 사용해
    /// 벽의 실제 면과 같은 방향·길이의 충돌 영역을 만든다.
    static func faceColliders(node: SCNNode, roomCenter: SCNVector3) -> [WallCollider] {
        worldGeometryTriangles(of: node).compactMap { triangle in
            WallCollider(node: node, facePoints: triangle, roomCenter: roomCenter)
        }
    }

    private init?(node: SCNNode, facePoints points: [SCNVector3], roomCenter: SCNVector3) {
        guard points.count == 3 else { return nil }

        let edgeA = SCNVector3(
            points[1].x - points[0].x,
            points[1].y - points[0].y,
            points[1].z - points[0].z
        )
        let edgeB = SCNVector3(
            points[2].x - points[0].x,
            points[2].y - points[0].y,
            points[2].z - points[0].z
        )
        let faceNormal = SCNVector3(
            edgeA.y * edgeB.z - edgeA.z * edgeB.y,
            edgeA.z * edgeB.x - edgeA.x * edgeB.z,
            edgeA.x * edgeB.y - edgeA.y * edgeB.x
        )
        let faceAreaTwice = sqrtf(
            faceNormal.x * faceNormal.x +
                faceNormal.y * faceNormal.y +
                faceNormal.z * faceNormal.z
        )
        // 퇴화한 면과 바닥/천장에 가까운 면은 벽 충돌 대상이 아니다.
        guard faceAreaTwice > 0.000002,
              abs(faceNormal.y / faceAreaTwice) <= 0.25 else { return nil }

        let candidateNormal = SCNVector3(faceNormal.x, 0, faceNormal.z).normalizedXZ
        guard candidateNormal.lengthXZ > 0 else { return nil }

        let candidateProjection = points.reduce(Float(0)) { $0 + $1.dotXZ(candidateNormal) } / Float(points.count)
        let roomSide: Float = roomCenter.dotXZ(candidateNormal) >= candidateProjection ? 1 : -1
        normal = SCNVector3(
            candidateNormal.x * roomSide,
            0,
            candidateNormal.z * roomSide
        ).normalizedXZ
        projection = candidateProjection * roomSide
        lengthAxis = SCNVector3(-normal.z, 0, normal.x).normalizedXZ

        let lengthRange = Self.projectionRange(points, axis: lengthAxis)
        let heightRange = Self.verticalRange(points)
        let faceLength = lengthRange.max - lengthRange.min
        let faceHeight = heightRange.max - heightRange.min
        // 웹과 같은 최소 크기. 창/문 개구부의 아주 작은 찌꺼기 triangle은 충돌면이 되지 않는다.
        guard faceLength >= 0.05, faceHeight >= 0.05 else { return nil }

        lengthCenter = (lengthRange.min + lengthRange.max) / 2
        halfLength = faceLength / 2
        self.node = node
        let centerY = (heightRange.min + heightRange.max) / 2
        center = SCNVector3(
            normal.x * projection + lengthAxis.x * lengthCenter,
            centerY,
            normal.z * projection + lengthAxis.z * lengthCenter
        )
    }

    func overlapsSpan(center: SCNVector3, footprint: FurnitureFootprint) -> Bool {
        let radius = footprint.projectionRadius(on: lengthAxis)
        let projected = center.dotXZ(lengthAxis)
        return abs(projected - lengthCenter) <= halfLength + radius + 0.04
    }

    var length: Float {
        halfLength * 2
    }

    private static func worldBoxCorners(of node: SCNNode) -> [SCNVector3] {
        let (minBounds, maxBounds) = node.boundingBox
        return [
            SCNVector3(minBounds.x, minBounds.y, minBounds.z),
            SCNVector3(maxBounds.x, minBounds.y, minBounds.z),
            SCNVector3(minBounds.x, maxBounds.y, minBounds.z),
            SCNVector3(maxBounds.x, maxBounds.y, minBounds.z),
            SCNVector3(minBounds.x, minBounds.y, maxBounds.z),
            SCNVector3(maxBounds.x, minBounds.y, maxBounds.z),
            SCNVector3(minBounds.x, maxBounds.y, maxBounds.z),
            SCNVector3(maxBounds.x, maxBounds.y, maxBounds.z)
        ].map { node.convertPosition($0, to: nil) }
    }

    private static func worldGeometryPoints(of node: SCNNode) -> [SCNVector3] {
        guard let source = node.geometry?.sources(for: .vertex).first,
              source.usesFloatComponents,
              source.componentsPerVector >= 3,
              source.bytesPerComponent == MemoryLayout<Float>.size,
              source.dataStride >= source.bytesPerComponent * source.componentsPerVector else {
            return worldBoxCorners(of: node)
        }

        var points: [SCNVector3] = []
        points.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { rawBuffer in
            for index in 0..<source.vectorCount {
                let offset = index * source.dataStride + source.dataOffset
                guard offset + MemoryLayout<Float>.size * 3 <= rawBuffer.count else { continue }
                let x = rawBuffer.loadUnaligned(fromByteOffset: offset, as: Float.self)
                let y = rawBuffer.loadUnaligned(
                    fromByteOffset: offset + MemoryLayout<Float>.size,
                    as: Float.self
                )
                let z = rawBuffer.loadUnaligned(
                    fromByteOffset: offset + MemoryLayout<Float>.size * 2,
                    as: Float.self
                )
                points.append(node.convertPosition(SCNVector3(x, y, z), to: nil))
            }
        }
        return points.isEmpty ? worldBoxCorners(of: node) : points
    }

    private static func worldGeometryTriangles(of node: SCNNode) -> [[SCNVector3]] {
        guard let geometry = node.geometry else { return [] }
        guard let source = geometry.sources(for: .vertex).first,
              source.usesFloatComponents,
              source.componentsPerVector >= 3,
              source.bytesPerComponent == MemoryLayout<Float>.size,
              source.dataStride >= source.bytesPerComponent * source.componentsPerVector,
              // `worldGeometryPoints`가 source를 읽지 못하면 bounding box를 반환한다. face index가
              // 그 fallback 점에 적용되면 잘못된 면이 생기므로, 지원하는 실제 source만 허용한다.
              source.vectorCount > 0 else { return [] }
        let vertices = worldGeometryPoints(of: node)
        guard
              source.vectorCount == vertices.count else { return [] }

        var triangles: [[SCNVector3]] = []
        for element in geometry.elements where element.primitiveType == .triangles {
            let indices = Self.indices(in: element)
            guard !indices.isEmpty else { continue }
            for offset in stride(from: 0, to: indices.count - 2, by: 3) {
                let a = indices[offset]
                let b = indices[offset + 1]
                let c = indices[offset + 2]
                guard vertices.indices.contains(a), vertices.indices.contains(b), vertices.indices.contains(c) else { continue }
                triangles.append([vertices[a], vertices[b], vertices[c]])
            }
        }
        return triangles
    }

    private static func indices(in element: SCNGeometryElement) -> [Int] {
        guard element.bytesPerIndex > 0 else { return [] }
        let indexCount = element.primitiveCount * 3
        guard indexCount > 0 else { return [] }

        var indices: [Int] = []
        indices.reserveCapacity(indexCount)
        element.data.withUnsafeBytes { rawBuffer in
            for index in 0..<indexCount {
                let offset = index * element.bytesPerIndex
                guard offset + element.bytesPerIndex <= rawBuffer.count else { break }
                let value: Int
                switch element.bytesPerIndex {
                case 1:
                    value = Int(rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                case 2:
                    value = Int(rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                case 4:
                    value = Int(rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                default:
                    return
                }
                indices.append(value)
            }
        }
        return indices
    }

    private static func dominantHorizontalAxis(_ points: [SCNVector3]) -> SCNVector3? {
        var bestLength: Float = 0
        var best = SCNVector3(0, 0, 0)

        for a in points.indices {
            for b in points.indices where b > a {
                let dx = points[b].x - points[a].x
                let dz = points[b].z - points[a].z
                let length = dx * dx + dz * dz
                if length > bestLength {
                    bestLength = length
                    best = SCNVector3(dx, 0, dz)
                }
            }
        }

        guard bestLength > 1e-8 else { return nil }
        return best.normalizedXZ
    }

    private static func projectionRange(_ points: [SCNVector3], axis: SCNVector3) -> (min: Float, max: Float) {
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        for point in points {
            let projected = point.dotXZ(axis)
            minValue = min(minValue, projected)
            maxValue = max(maxValue, projected)
        }
        return (minValue, maxValue)
    }

    private static func verticalRange(_ points: [SCNVector3]) -> (min: Float, max: Float) {
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        for point in points {
            minValue = min(minValue, point.y)
            maxValue = max(maxValue, point.y)
        }
        return (minValue, maxValue)
    }
}

private final class CameraFittingSceneView: SCNView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// 프런트엔드 `updateViewFacingWalls` 대응 — 카메라 쪽(시야를 가리는 쪽)을 향한 벽을 매 프레임 반투명 처리해
/// 어느 각도에서도 방 안이 보이게 합니다. 렌더 스레드에서 호출되므로 벽 목록은 잠금으로 보호합니다.
final class WallFacingUpdater: NSObject, SCNSceneRendererDelegate {
    struct Wall {
        let node: SCNNode
        let centerXZ: SIMD2<Float>
        let normalXZ: SIMD2<Float>   // 방 안쪽(room-facing) 방향
    }

    private let lock = NSLock()
    private var walls: [Wall] = []
    private var wallsRevision = 0
    private var enabled = true
    /// 렌더 콜백은 ProMotion 기기에서 초당 120번 들어올 수 있지만 벽 투명도는
    /// 30Hz면 충분하다. 카메라·벽 목록·활성 상태가 그대로면 계산 자체를 생략한다.
    private let minimumEvaluationInterval: TimeInterval = 1.0 / 30.0
    private var lastEvaluationTime: TimeInterval = -.infinity
    private var lastCameraXZ: SIMD2<Float>?
    private var lastWallsRevision = -1
    private var lastEnabled = true
    /// 벽 투명화 on/off. 스카이뷰(탑다운)에서는 꺼서 벽이 사라져 보이지 않게 합니다.
    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            enabled = newValue
            lock.unlock()
        }
    }

    func setWalls(_ newWalls: [Wall]) {
        lock.lock()
        // 교체 전에 더 이상 투명화 대상이 아닌 노드만 다시 불투명으로 복원합니다.
        let nextNodes = Set(newWalls.map { ObjectIdentifier($0.node) })
        for wall in walls where !nextNodes.contains(ObjectIdentifier(wall.node)) {
            wall.node.opacity = 1
        }
        walls = newWalls
        wallsRevision &+= 1
        lock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pointOfView = renderer.pointOfView else { return }
        let cameraPosition = pointOfView.presentation.simdWorldPosition
        let cameraXZ = SIMD2<Float>(cameraPosition.x, cameraPosition.z)

        lock.lock()
        let snapshot = walls
        let revision = wallsRevision
        let isEnabled = enabled
        lock.unlock()

        let stateChanged = revision != lastWallsRevision || isEnabled != lastEnabled
        let cameraMoved = lastCameraXZ.map { simd_distance_squared($0, cameraXZ) > 0.000_004 } ?? true
        guard stateChanged
                || (cameraMoved && time - lastEvaluationTime >= minimumEvaluationInterval) else {
            return
        }
        lastEvaluationTime = time
        lastCameraXZ = cameraXZ
        lastWallsRevision = revision
        lastEnabled = isEnabled

        // 스카이뷰 등 투명화가 꺼진 모드에서는 벽을 전부 불투명으로 복원만 한다.
        guard isEnabled else {
            for wall in snapshot where abs(wall.node.opacity - 1) > 0.001 {
                wall.node.opacity = 1
            }
            return
        }

        for wall in snapshot {
            let toCamera = cameraXZ - wall.centerXZ
            let length = simd_length(toCamera)
            guard length > 0.0001 else { continue }
            // 카메라가 벽의 방 바깥쪽에 있으면(벽이 시야를 가리면) 반투명.
            let dot = simd_dot(toCamera / length, wall.normalXZ)
            let target: CGFloat = dot < -0.2 ? 0.14 : 1.0
            if abs(wall.node.opacity - target) > 0.02 {
                wall.node.opacity = target
            }
        }
    }
}

struct HorizontalBounds {
    var minX: Float
    var maxX: Float
    var minZ: Float
    var maxZ: Float

    static let defaultRoom = HorizontalBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)

    var width: Float { max(maxX - minX, 0.1) }
    var depth: Float { max(maxZ - minZ, 0.1) }
    var centerX: Float { (minX + maxX) / 2 }
    var centerZ: Float { (minZ + maxZ) / 2 }
    var radius: Float { hypotf(width, depth) / 2 }

    mutating func expand(by padding: Float) {
        minX -= padding
        maxX += padding
        minZ -= padding
        maxZ += padding
    }

    func inset(by padding: Float) -> HorizontalBounds {
        guard width > padding * 2, depth > padding * 2 else { return self }
        return HorizontalBounds(
            minX: minX + padding,
            maxX: maxX - padding,
            minZ: minZ + padding,
            maxZ: maxZ - padding
        )
    }

    func clampedX(_ value: Float, inset: Float) -> Float {
        let lower = minX + inset
        let upper = maxX - inset
        guard lower <= upper else { return centerX }
        return min(max(value, lower), upper)
    }

    func clampedZ(_ value: Float, inset: Float) -> Float {
        let lower = minZ + inset
        let upper = maxZ - inset
        guard lower <= upper else { return centerZ }
        return min(max(value, lower), upper)
    }

    static func union(_ lhs: HorizontalBounds?, _ rhs: HorizontalBounds?) -> HorizontalBounds? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return HorizontalBounds(
                minX: min(lhs.minX, rhs.minX),
                maxX: max(lhs.maxX, rhs.maxX),
                minZ: min(lhs.minZ, rhs.minZ),
                maxZ: max(lhs.maxZ, rhs.maxZ)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}

extension UIColor {
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        guard hex.count == 6 else {
            self.init(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension SCNVector3 {
    var lengthXZ: Float {
        hypotf(x, z)
    }

    var normalizedXZ: SCNVector3 {
        let length = lengthXZ
        guard length > 1e-8 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(x / length, 0, z / length)
    }

    func dotXZ(_ other: SCNVector3) -> Float {
        x * other.x + z * other.z
    }
}
