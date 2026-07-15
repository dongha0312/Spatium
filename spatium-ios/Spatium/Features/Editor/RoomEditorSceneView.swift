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
        /// 드래그 시작 시 "손가락이 짚은 바닥 지점 → 가구 중심" 오프셋.
        /// 이걸 유지해야 가구의 잡은 부분이 손가락에 붙어 따라온다. (없으면 중심이 손가락으로 점프)
        private var dragGrabOffset = SIMD2<Float>(0, 0)
        /// 프런트엔드의 figure-move interaction 대응. 소품 노드는 드래그 중 직접 움직이고,
        /// 종료 시점에만 ViewModel에 최종 위치를 커밋해 히스토리/씬 재생성을 한 번으로 제한한다.
        private var draggingDecorID: Int?
        private var decorDragStartPosition: SCNVector3?
        /// 벽/가구에 새로 막히는 순간(엣지)에만 햅틱을 한 번 주기 위한 상태.
        private var isSnapEngaged = false
        /// require(toFail:)를 이미 걸어둔 카메라 제스처들. (중복 설정 방지)
        private var cameraGestureRequirementConfigured = Set<ObjectIdentifier>()

        // MARK: 사람 뷰 상태
        var personLookGesture: UIPanGestureRecognizer?
        var personWalkGesture: UIPanGestureRecognizer?
        var personPinchGesture: UIPinchGestureRecognizer?
        /// 시선 방향(라디안). yaw 0 = -Z, pitch + = 위.
        private var personYaw: Float = 0
        private var personPitch: Float = 0
        /// 사용자가 요청한 시선/위치. 실제 카메라는 display link가 여기로 부드럽게 따라간다.
        /// 입력 이벤트마다 카메라를 즉시 움직이면 손가락 샘플링의 들쭉날쭉함이 그대로 눈에
        /// 전달돼 멀미가 나므로, 사람뷰에서만 목표와 실제 위치를 분리한다.
        private var personTargetYaw: Float = 0
        private var personTargetPitch: Float = 0
        private var personTargetPosition: SIMD2<Float>?
        private var personWalkVelocity = SIMD2<Float>(0, 0)
        private var personMotionDisplayLink: CADisplayLink?
        private var lastPersonMotionTimestamp: CFTimeInterval?
        private var lastLookTranslation = CGPoint.zero
        private var lastWalkTranslation = CGPoint.zero
        /// 카메라(사람 몸통)의 수평 충돌 반경(m).
        private static let personBodyRadius: Float = 0.25
        /// 멀미를 줄이기 위한 보행/시선 파라미터. 실제 걷는 속도에 가깝게 제한해 장거리
        /// 탭이 화면을 훅 끌고 가는 느낌을 막고, 시선은 아주 짧은 시간만 보간해 조작 지연은 없다.
        private static let personMaxTapTravel: Float = 2.8
        private static let personWalkMaxSpeed: Float = 1.90
        private static let personWalkAcceleration: Float = 7.5
        private static let personLookResponse: Float = 0.055
        var renderedRevision = 0
        var renderedViewMode: RoomViewMode?
        var cameraLayoutSize = CGSize.zero

        let cameraNode = SCNNode()
        private let furnitureContainer = SCNNode()
        /// item ID별 마지막 GLB 렌더 형태. SceneKit의 SCNNode는 userData를 제공하지 않아
        /// coordinator가 별도로 보관한다.
        private var furnitureRenderSignatures: [Int: String] = [:]
        /// item ID별 마지막 피규어(꾸미기) 렌더 형태. 바뀐 책장의 피규어들만 다시 만든다.
        private var decorRenderSignatures: [Int: String] = [:]
        /// 노드 생성 시점의 (표시 치수, 노드 스케일). 크기 슬라이더가 GLB를 다시 만들지 않고
        /// "기준 대비 비율"로 스케일만 조정할 수 있게 한다. (맞춤 스케일이 축별 선형이라
        /// 비율 스케일 결과는 리빌드 결과와 정확히 같다)
        private var renderedBaseStates: [Int: (width: Double, depth: Double, height: Double, scale: SCNVector3)] = [:]
        /// 꾸미기 카메라가 적용된 책장 itemId. viewModel.decoratingItemID와 비교해 전환을 감지한다.
        private var decorCameraItemID: Int?
        private let floorNode = SCNNode()
        private let measurementContainer = SCNNode()
        private let selectionHighlightName = "__selection_highlight"
        private var floorSide: CGFloat = 4
        /// 카메라가 바라볼 방/가구의 중심(수평). 방이 원점에서 벗어나 있어도 화면 중앙에 오게 합니다.
        private var sceneCenter = SCNVector3(0, 0.4, 0)
        /// 중심에서 방을 감싸는 반경(m). 카메라 거리 산정에 사용합니다.
        private var sceneRadius: Float = 3
        /// 방/가구를 모두 포함하는 수평 경계. Skyview 배율과 드래그 한계에 사용합니다.
        private var sceneBounds = HorizontalBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)
        /// 실제 방 셸만의 수평 경계. 가구가 밖으로 튀어나와도 이 값은 넓히지 않습니다.
        private var roomBounds = HorizontalBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)
        private var wallColliders: [WallCollider] = []
        /// 벽 메우기 패널의 충돌 면. 셸 벽 콜라이더는 개구부 자리가 비어 있으므로,
        /// 메운 자리는 패널 박스로 콜라이더를 만들어 실제 벽처럼 가구 이동을 막는다.
        private var infillColliders: [WallCollider] = []
        private var shellViewFacingSurfaces: [WallFacingUpdater.Wall] = []
        private var measurementSegments: [MeasurementSegment] = []
        private var roomHeight: Float = 2.4
        /// 방 바닥의 월드 Y. 스캔 메시는 AR 좌표계라 0이 아닐 수 있고,
        /// 측정 치수선을 이 높이에 붙여야 바닥에 깔린 도면처럼 보인다.
        private var floorLevel: Float = 0
        private var isScannedRoom = false
        private let wallMeasurementInset: Float = 0.16
        private let overallMeasurementOffset: Float = 0.8
        private let measurementCameraPadding: Float = 1.25
        /// 파싱한 USDZ 방 셸(가구 제거 완료)을 캐시. 재생성 때 매번 디스크에서 다시 파싱하지 않도록.
        private var shellCache: [String: SCNNode] = [:]
        /// 현재 씬에 올라간 방 셸(벽 색 재적용용) 및 마지막으로 반영한 벽 색.
        private weak var shellNode: SCNNode?
        private var renderedWallColor = ""
        private var renderedFloorColor: String?
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
        private func buildBoxRoom(into scene: SCNScene, layout: RoomLayout) {
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
        private func buildScannedShell(into scene: SCNScene, usdzURL: URL, layout: RoomLayout) {
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
        private static func shellFloorY(of root: SCNNode) -> Float? {
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
        private func shellTemplate(for usdzURL: URL) -> SCNNode? {
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
        private func tintWalls(in node: SCNNode, color: UIColor) {
            if let name = node.name, name.localizedCaseInsensitiveContains("wall"), let geometry = node.geometry {
                geometry.materials.forEach { $0.diffuse.contents = color }
            }
            node.childNodes.forEach { tintWalls(in: $0, color: color) }
        }

        private func tintFloors(in node: SCNNode, color: UIColor) {
            if Self.isFloorGeometryNode(node), let geometry = node.geometry {
                geometry.materials.forEach { $0.diffuse.contents = color }
            }
            node.childNodes.forEach { tintFloors(in: $0, color: color) }
        }

        func rebuildFurnitureNodes(for layout: RoomLayout) {
            let roomCenter = SCNVector3(roomBounds.centerX, 0, roomBounds.centerZ)
            let requestedIDs = Set(layout.furnitures.map(\.itemId))
            // 프런트엔드처럼 기존 GLB 인스턴스를 유지한다. 추가/삭제/교체된 모델만 다시
            // 만들므로 벽 색상 변경이나 다른 가구의 회전 때문에 전체 모델을 복제하지 않는다.
            furnitureContainer.childNodes
                .filter { node in
                    if let itemID = Self.furnitureID(fromNodeOrAncestors: node) {
                        return !requestedIDs.contains(itemID)
                    }
                    if let itemID = Self.decorContainerItemID(node) {
                        return !requestedIDs.contains(itemID)
                    }
                    return true
                }
                .forEach { $0.removeFromParentNode() }
            furnitureRenderSignatures = furnitureRenderSignatures.filter { requestedIDs.contains($0.key) }
            decorRenderSignatures = decorRenderSignatures.filter { requestedIDs.contains($0.key) }
            renderedBaseStates = renderedBaseStates.filter { requestedIDs.contains($0.key) }

            for furniture in layout.furnitures {
                let renderFurniture = displayFurniture(for: furniture)
                let nodeName = "furniture-\(furniture.itemId)"
                let signature = furnitureRenderSignature(for: renderFurniture, source: furniture)
                if let existing = furnitureContainer.childNode(withName: nodeName, recursively: false),
                   furnitureRenderSignatures[furniture.itemId] == signature {
                    applyRenderTransform(to: existing, furniture: renderFurniture, source: furniture, roomCenter: roomCenter)
                    updateDecorContainer(for: furniture, furnitureNode: existing)
                    continue
                }

                furnitureContainer.childNode(withName: nodeName, recursively: false)?.removeFromParentNode()
                let node = RoomEditorViewModel.isWallInfill(furniture)
                    ? makeWallInfillNode(for: renderFurniture)
                    : modelLoader.makeNode(for: renderFurniture)
                furnitureRenderSignatures[furniture.itemId] = signature
                // 유효 치수(치수 × 렌더 스케일) 기준 — 방 크기 제한(fittingScaleLimit)이 걸린
                // 상태에서도 크기 슬라이더 비율 계산이 어긋나지 않는다.
                renderedBaseStates[furniture.itemId] = (
                    width: (renderFurniture.width ?? 0.5) * renderFurniture.scale.x,
                    depth: (renderFurniture.depth ?? 0.5) * renderFurniture.scale.z,
                    height: (renderFurniture.height ?? 0.5) * renderFurniture.scale.y,
                    scale: node.scale
                )
                applyRenderTransform(to: node, furniture: renderFurniture, source: furniture, roomCenter: roomCenter)
                furnitureContainer.addChildNode(node)
                updateDecorContainer(for: furniture, furnitureNode: node)
            }
            // 벽 메우기 패널은 실제 벽처럼 가구 드래그/되밀기를 막아야 한다. 패널 박스 노드로
            // 콜라이더를 만들어 셸 벽 콜라이더와 함께 검사한다. (패널 추가/제거 때마다 갱신)
            infillColliders = layout.furnitures
                .filter { RoomEditorViewModel.isWallInfill($0) }
                .compactMap { furniture in
                    furnitureContainer.childNode(withName: "furniture-\(furniture.itemId)", recursively: false)
                        .flatMap { WallCollider(node: $0, roomCenter: roomCenter) }
                }
            applySelection(itemID: viewModel.selectedItemID)
            refreshViewFacingTransparencyTargets()
        }

        /// 모델/크기에만 의존하는 렌더 시그니처. 위치·회전은 재사용한 노드에 즉시 반영한다.
        /// 벽 메우기 패널은 벽 색으로 칠하므로 벽 색이 바뀌면 다시 만들도록 색을 포함한다.
        private func furnitureRenderSignature(for furniture: PlacedFurniture, source: PlacedFurniture) -> String {
            [
                furniture.furnitureId.description,
                furniture.furnitureName,
                furniture.modelName ?? "",
                furniture.width?.description ?? "",
                furniture.height?.description ?? "",
                furniture.depth?.description ?? "",
                furniture.scale.x.description,
                furniture.scale.y.description,
                furniture.scale.z.description,
                RoomEditorViewModel.isWallInfill(source) ? "infill:\(viewModel.wallColorHex)" : ""
            ].joined(separator: "|")
        }

        /// 스캔 결과를 처음 렌더할 때는 RoomPlan이 감지한 transform을 그대로 사용한다.
        /// 문/창문만 벽과의 z-fighting을 막기 위해 방 안쪽으로 3cm 넣는다.
        private func applyRenderTransform(
            to node: SCNNode,
            furniture: PlacedFurniture,
            source: PlacedFurniture,
            roomCenter: SCNVector3
        ) {
            node.position = SCNVector3(furniture.position.x, furniture.position.y, furniture.position.z)
            node.eulerAngles = SCNVector3(furniture.rotation.x, furniture.rotation.y, furniture.rotation.z)
            guard Self.isDoorOrWindow(source) else { return }

            let dx = roomCenter.x - node.position.x
            let dz = roomCenter.z - node.position.z
            let length = sqrtf(dx * dx + dz * dz)
            guard length > 0.0001 else { return }
            let inset: Float = 0.03
            node.position.x += dx / length * inset
            node.position.z += dz / length * inset
        }

        /// 벽 메우기 패널 노드 — 문/창문을 '벽으로 메우기'로 지운 자리를 GLB 대신 벽 색 박스로 막습니다.
        /// pivot을 바닥에 둬 가구 모델과 같은 규약(position.y = 바닥면)으로 배치하고, 크기는
        /// 스케일을 반영해 박스 치수에 직접 반영합니다. 일반 가구로 취급돼 사람 뷰 충돌·측정에 함께 잡힙니다.
        private func makeWallInfillNode(for furniture: PlacedFurniture) -> SCNNode {
            let width = CGFloat(max(Float(furniture.width ?? 0.9), 0.05) * max(Float(furniture.scale.x), 0.001))
            let height = CGFloat(max(Float(furniture.height ?? 2.0), 0.05) * max(Float(furniture.scale.y), 0.001))
            let depth = CGFloat(max(Float(furniture.depth ?? 0.1), 0.05) * max(Float(furniture.scale.z), 0.001))
            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(hexString: viewModel.wallColorHex)
            material.locksAmbientWithDiffuse = true
            box.materials = [material]

            let node = SCNNode(geometry: box)
            node.name = "furniture-\(furniture.itemId)"
            // pivot을 아래로 내려 박스 바닥이 position.y에 오게 한다(placeholder 규약과 동일).
            node.pivot = SCNMatrix4MakeTranslation(0, Float(-height / 2), 0)
            node.position = SCNVector3(Float(furniture.position.x), Float(furniture.position.y), Float(furniture.position.z))
            node.eulerAngles.y = Float(furniture.rotation.y)
            return node
        }

        // MARK: - 책장 꾸미기 (피규어) 렌더링

        /// 피규어들은 가구 노드의 "자식"이 아니라 나란히 놓인 전용 컨테이너에 담는다.
        /// 가구 노드는 GLB 맞춤 스케일(비균일)이 걸려 있어 자식으로 붙이면 피규어가 찌그러지므로,
        /// 스케일 없는 컨테이너를 가구와 같은 위치/회전으로 동기화해 부모 역할을 시킨다.
        private func updateDecorContainer(for furniture: PlacedFurniture, furnitureNode: SCNNode) {
            let containerName = "decorbox-\(furniture.itemId)"
            let decorations = furniture.decorations ?? []

            guard !decorations.isEmpty else {
                furnitureContainer.childNode(withName: containerName, recursively: false)?.removeFromParentNode()
                decorRenderSignatures[furniture.itemId] = nil
                return
            }

            let container: SCNNode
            if let existing = furnitureContainer.childNode(withName: containerName, recursively: false) {
                container = existing
            } else {
                container = SCNNode()
                container.name = containerName
                furnitureContainer.addChildNode(container)
            }
            syncDecorContainerTransform(container: container, furnitureNode: furnitureNode)

            let signature = decorations.map { d in
                [
                    d.decorId.description, d.modelName ?? "", d.name,
                    d.width.description, d.height.description, d.depth.description,
                    d.position.x.description, d.position.y.description, d.position.z.description,
                    d.rotationY.description, d.scale.description
                ].joined(separator: "|")
            }.joined(separator: "#")
            guard decorRenderSignatures[furniture.itemId] != signature else { return }
            decorRenderSignatures[furniture.itemId] = signature

            container.childNodes.forEach { $0.removeFromParentNode() }
            for decoration in decorations {
                let name = "decor-\(furniture.itemId)-\(decoration.decorId)"
                // 래퍼가 배치(위치/회전/균일 크기)를, 안쪽 모델 노드가 GLB 맞춤 스케일을 담당한다.
                // 분리해 두면 크기 슬라이더가 맞춤 스케일을 다시 계산할 필요 없이 래퍼만 만진다.
                let wrapper = SCNNode()
                wrapper.name = name
                wrapper.position = SCNVector3(decoration.position.x, decoration.position.y, decoration.position.z)
                wrapper.eulerAngles.y = Float(decoration.rotationY)
                let uniform = Float(max(decoration.scale, 0.001))
                wrapper.scale = SCNVector3(uniform, uniform, uniform)
                wrapper.addChildNode(modelLoader.makeDecorNode(identifier: name, decoration: decoration))
                container.addChildNode(wrapper)
            }
        }

        private func syncDecorContainerTransform(container: SCNNode, furnitureNode: SCNNode) {
            container.position = furnitureNode.position
            container.eulerAngles = SCNVector3(0, furnitureNode.eulerAngles.y, 0)
        }

        /// 가구 노드가 직접 움직였을 때(드래그/슬라이더/벽 되밀기) 피규어 컨테이너를 따라 붙인다.
        private func syncDecorContainer(forItemID itemID: Int) {
            guard let node = furnitureContainer.childNode(withName: "furniture-\(itemID)", recursively: false),
                  let container = furnitureContainer.childNode(withName: "decorbox-\(itemID)", recursively: false) else { return }
            syncDecorContainerTransform(container: container, furnitureNode: node)
        }

        private static func decorContainerItemID(_ node: SCNNode) -> Int? {
            guard let name = node.name, name.hasPrefix("decorbox-") else { return nil }
            return Int(name.dropFirst("decorbox-".count))
        }

        /// "decor-<가구ID>-<피규어ID>" 이름을 노드 또는 조상에서 찾아 해석한다.
        /// 가구ID는 로컬 아이템일 때 음수라서("decor--2-1"), 마지막 "-"를 기준으로 나눈다.
        private static func decorID(fromNodeOrAncestors node: SCNNode) -> (itemID: Int, decorID: Int)? {
            var current: SCNNode? = node
            while let candidate = current {
                if let name = candidate.name, name.hasPrefix("decor-"), !name.hasPrefix("decorbox-") {
                    let body = name.dropFirst("decor-".count)
                    if let separator = body.lastIndex(of: "-"),
                       let itemID = Int(body[..<separator]),
                       let decorID = Int(body[body.index(after: separator)...]) {
                        return (itemID, decorID)
                    }
                }
                current = candidate.parent
            }
            return nil
        }

        /// 꾸미기 모드의 선택 하이라이트 + 회전/크기 슬라이더 실시간 반영.
        func syncDecorState(from layout: RoomLayout) {
            let decoratingID = viewModel.decoratingItemID
            let selectedDecorID = viewModel.selectedDecorID

            for container in furnitureContainer.childNodes {
                guard let itemID = Self.decorContainerItemID(container) else { continue }
                for figure in container.childNodes {
                    removeSelectionHighlight(from: figure)
                    guard let id = Self.decorID(fromNodeOrAncestors: figure),
                          id.itemID == itemID else { continue }
                    if itemID == decoratingID, id.decorID == selectedDecorID {
                        addSelectionHighlight(to: figure)
                    }
                    // 슬라이더 연속 조작(회전/크기)은 sceneRevision 없이 노드에 바로 반영한다.
                    if let decoration = layout.furnitures
                        .first(where: { $0.itemId == itemID })?
                        .decorations?.first(where: { $0.decorId == id.decorID }) {
                        figure.eulerAngles.y = Float(decoration.rotationY)
                        let uniform = Float(max(decoration.scale, 0.001))
                        figure.scale = SCNVector3(uniform, uniform, uniform)
                    }
                }
            }
        }

        /// 꾸미기 모드 진입/이탈에 맞춰 카메라를 책장 정면 뷰로 전환하거나 원래대로 되돌린다.
        func syncDecorCamera() {
            let target = viewModel.decoratingItemID
            guard decorCameraItemID != target else { return }
            if let target,
               let node = furnitureContainer.childNode(withName: "furniture-\(target)", recursively: false) {
                decorCameraItemID = target
                applyDecorCamera(to: node)
            } else {
                decorCameraItemID = nil
                applyCamera(mode: viewModel.viewMode, animated: true)
            }
        }

        /// 웹 computeDecorView 대응: 책장의 열린 선반 정면에서 25도 위로 내려다보는
        /// 근접 시점. 선반 안쪽 바닥이 보여 피규어를 올릴 자리를 탭하기 좋다.
        private func applyDecorCamera(to node: SCNNode) {
            guard let bounds = Self.localHierarchyBounds(of: node) else { return }
            let localCenter = SCNVector3(
                (bounds.min.x + bounds.max.x) / 2,
                (bounds.min.y + bounds.max.y) / 2,
                (bounds.min.z + bounds.max.z) / 2
            )
            let worldCenter = node.convertPosition(localCenter, to: nil)
            let size = SIMD3(
                (bounds.max.x - bounds.min.x) * node.scale.x,
                (bounds.max.y - bounds.min.y) * node.scale.y,
                (bounds.max.z - bounds.min.z) * node.scale.z
            )
            let radius = max(simd_length(size) / 2, 0.4)

            // 모델의 열린 면은 로컬 +Z다. 가구 회전은 convertVector에 이미 반영되므로,
            // 방 중심을 기준으로 다시 뒤집으면 책장 뒤판을 바라보게 될 수 있다.
            let frontWorld = node.convertVector(SCNVector3(0, 0, 1), to: nil)
            let front = RoomEditorSceneView.decorFrontDirection(from: frontWorld)

            let distance = max(radius * 2.2, 1.1)
            let elevation = Float(25 * Double.pi / 180)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            cameraNode.camera?.usesOrthographicProjection = false
            cameraNode.camera?.fieldOfView = 60
            cameraNode.position = SCNVector3(
                worldCenter.x + front.x * distance * cos(elevation),
                worldCenter.y + distance * sin(elevation),
                worldCenter.z + front.y * distance * cos(elevation)
            )
            cameraNode.look(at: worldCenter, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.commit()
            sceneView?.pointOfView = cameraNode

            // 궤도 회전 중심을 책장으로 옮겨, 꾸미는 동안의 시점 조작이 책장을 축으로 돌게 한다.
            if let controller = sceneView?.defaultCameraController {
                controller.interactionMode = .orbitTurntable
                controller.target = worldCenter
                controller.automaticTarget = false
            }
        }

        /// 꾸미기 모드의 탭: 대기 소품의 선반 배치 → 기존 소품 선택 → 빈 곳 선택 해제 순으로 판정.
        private func handleDecorTap(at point: CGPoint, in sceneView: SCNView, decoratingID: Int) {
            let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

            let wantsPlacement = viewModel.pendingFigure != nil
            if wantsPlacement,
               // 웹 decorSurface 대응: 책장 mesh 중 "위를 향한 면"(정규화한 법선 Y ≥ 0.7 — 상판·선반 바닥)만
               // 지지면으로 인정한다. 옆면/앞면 탭은 배치로 이어지지 않는다.
               let support = hits.first(where: { hit in
                   Self.furnitureID(fromNodeOrAncestors: hit.node) == decoratingID
                       && RoomEditorSceneView.isDecorSupportNormal(hit.worldNormal)
               }),
               let container = furnitureContainer.childNode(withName: "decorbox-\(decoratingID)", recursively: false)
                   ?? makeDecorContainerIfMissing(for: decoratingID) {
                let local = container.convertPosition(support.worldCoordinates, from: nil)
                let position = FurnitureTransform.Vector3(x: Double(local.x), y: Double(local.y), z: Double(local.z))
                viewModel.placePendingFigure(atLocal: position)
                viewModel.statusMessage = nil
                return
            }

            if wantsPlacement {
                viewModel.statusMessage = "소품을 놓을 선반의 윗면을 탭하세요"
                return
            }

            // 프런트와 동일하게 새 소품 배치가 대기 중이면 기존 소품보다 선반 배치를 우선한다.
            // 배치 대기가 아닐 때 기존 소품을 탭하면 선택하고, 이후 드래그로 이동할 수 있다.
            if !wantsPlacement,
               let decor = hits.compactMap({ Self.decorID(fromNodeOrAncestors: $0.node) })
                .first(where: { $0.itemID == decoratingID }) {
                viewModel.selectedDecorID = decor.decorID
                viewModel.statusMessage = nil
                return
            }

            viewModel.selectedDecorID = nil
        }

        /// 첫 피규어를 올릴 때는 컨테이너가 아직 없다. 가구 노드 transform으로 즉석 생성해
        /// 월드 → 부모 로컬 변환에 쓴다. (실제 피규어 노드는 다음 rebuild에서 채워진다)
        private func makeDecorContainerIfMissing(for itemID: Int) -> SCNNode? {
            guard let node = furnitureContainer.childNode(withName: "furniture-\(itemID)", recursively: false) else {
                return nil
            }
            let container = SCNNode()
            container.name = "decorbox-\(itemID)"
            syncDecorContainerTransform(container: container, furnitureNode: node)
            furnitureContainer.addChildNode(container)
            return container
        }

        func applyCamera(mode: RoomViewMode, animated: Bool) {
            let radius = max(sceneRadius, 1.5)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.4 : 0
            switch mode {
            case .threeD:
                if isScannedRoom {
                    cameraNode.camera?.usesOrthographicProjection = true
                    cameraNode.camera?.orthographicScale = Double(scannedRoomPerspectiveScale())
                    cameraNode.position = scannedRoomPerspectiveCameraPosition(radius: radius)
                } else {
                    cameraNode.camera?.usesOrthographicProjection = false
                    cameraNode.camera?.fieldOfView = 60 // 사람 뷰(70°)에서 돌아올 때 기본 화각 복원
                    // 방 반경의 ~2.2배 거리에서 아이소메트릭 각도로 프레이밍.
                    cameraNode.position = SCNVector3(
                        sceneCenter.x + radius * 1.1,
                        radius * 1.25,
                        sceneCenter.z + radius * 1.5
                    )
                }
                // 스카이뷰(수직)에서 돌아올 때 look(at:)만 쓰면 직전 롤이 남아 화면이 기울어진다.
                // 월드 위쪽(+Y)을 명시해 항상 수평이 잡힌 3D 뷰로 복귀하게 한다.
                cameraNode.look(at: sceneCenter, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            case .skyView:
                cameraNode.camera?.usesOrthographicProjection = true
                cameraNode.camera?.orthographicScale = Double(skyViewScale())
                cameraNode.position = SCNVector3(sceneCenter.x, radius * 3 + 2, sceneCenter.z)
                // 수직 탑다운에서 look(at:)은 화면 위쪽(롤)이 정해지지 않아 직전 카메라 상태에 따라
                // 평면도가 뒤집혀 보인다. 방향을 명시적으로 고정: -Z가 화면 위, +X가 오른쪽.
                cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            case .person:
                // 방 중앙, 사람 눈높이(~1.45m)에서 시작하는 1인칭 뷰.
                cameraNode.camera?.usesOrthographicProjection = false
                // 휴대폰의 작은 화면에서는 너무 넓은 화각이 가장자리 왜곡과 빠른 optical flow를
                // 키워 멀미를 유발한다. 실내를 충분히 보면서도 편안한 65°로 제한한다.
                cameraNode.camera?.fieldOfView = 65
                let eyeY = floorLevel + 1.45
                let start = safePersonStartPosition(preferred: SIMD2(sceneCenter.x, sceneCenter.z))
                let eye = SCNVector3(start.x, eyeY, start.y)
                cameraNode.position = eye
                // 4방향 중 가장 먼 벽까지 시야가 열린 쪽을 바라보며 시작한다.
                // (코앞 벽을 보고 시작하는 것 방지 — 이후 드래그로 자유롭게 둘러본다)
                let direction = openestViewDirection(from: eye)
                let lookAt = SCNVector3(
                    eye.x + direction.x * max(radius, 1),
                    eyeY,
                    eye.z + direction.y * max(radius, 1)
                )
                cameraNode.look(at: lookAt, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
                // 이후 시선 제스처가 이어갈 yaw/pitch 상태를 실제 오리엔테이션에서 읽어온다.
                personYaw = cameraNode.eulerAngles.y
                personPitch = cameraNode.eulerAngles.x
                personTargetYaw = personYaw
                personTargetPitch = personPitch
                personTargetPosition = start
                personWalkVelocity = .zero
            }
            SCNTransaction.commit()
            // 벽 투명화는 3D 시점 전용. 탑다운에서는 벽이 시야를 가리지 않는데도
            // 반투명 처리돼 방이 부분만 렌더된 것처럼 보이고, 사람 뷰에서는 방 안이라
            // 모든 벽이 그대로 보여야 하므로 끈다.
            wallFacingUpdater.isEnabled = (mode == .threeD)
            sceneView?.pointOfView = cameraNode

            if mode == .person {
                startPersonComfortMotion()
            } else {
                stopPersonComfortMotion()
            }

            // 사람 뷰는 기본 카메라 컨트롤을 끄고(updateUIView) 전용 제스처로 움직인다.
            if mode != .person, let controller = sceneView?.defaultCameraController {
                // 스카이뷰는 평면도 역할이므로 회전/기울기를 완전히 막고 평행 이동만 허용한다.
                // 핀치 확대·축소는 SCNView 기본 카메라 컨트롤이 계속 처리한다.
                // 일반 3D 뷰만 방 중심을 축으로 도는 턴테이블 회전을 사용한다.
                controller.interactionMode = mode == .skyView ? .pan : .orbitTurntable
                controller.target = sceneCenter
                controller.automaticTarget = false
                controller.inertiaEnabled = true
            }
        }

        // MARK: - 사람 뷰 조작 (시선 / 걷기 / 충돌)

        /// 한 손가락 드래그 = 시선 조절. 좌우는 고개 돌리기, 위아래는 위/아래 보기.
        @objc func handlePersonLook(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView else { return }
            if gesture.state == .began { lastLookTranslation = .zero }
            let translation = gesture.translation(in: sceneView)
            let dx = Float(translation.x - lastLookTranslation.x)
            let dy = Float(translation.y - lastLookTranslation.y)
            lastLookTranslation = translation

            // 원래 감도(0.004)는 100pt 드래그에 약 23°가 돌아 작은 손 떨림도 과하게
            // 느껴졌다. 감도를 낮추고 display link 보간 대상으로만 갱신한다.
            personTargetYaw += dx * 0.0022
            // 아래 보기 한계를 약 60°까지 열어 발밑/가구 하단도 자연스럽게 확인할 수 있게 한다.
            // 위쪽은 과도하게 젖혀지지 않도록 기존과 비슷한 범위로 유지한다.
            personTargetPitch = max(-1.05, min(0.68, personTargetPitch + dy * 0.00175))
        }

        /// 두 손가락 드래그 = 보조 이동. 위로 밀면 전진, 좌우로 밀면 옆걸음.
        @objc func handlePersonWalk(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView else { return }
            if gesture.state == .began { lastWalkTranslation = .zero }
            let translation = gesture.translation(in: sceneView)
            let dx = Float(translation.x - lastWalkTranslation.x)
            let dy = Float(translation.y - lastWalkTranslation.y)
            lastWalkTranslation = translation

            // 한 번의 제스처 샘플이 늦게 몰려와도 순간 점프하지 않게 이동량을 제한한다.
            movePersonCamera(
                forward: max(-0.10, min(0.10, -dy * 0.0035)),
                strafe: max(-0.10, min(0.10, dx * 0.0035))
            )
        }

        /// 핀치 = 앞뒤 이동(벌리면 전진).
        @objc func handlePersonPinch(_ gesture: UIPinchGestureRecognizer) {
            let delta = Float(gesture.scale - 1)
            gesture.scale = 1
            movePersonCamera(forward: max(-0.10, min(0.10, delta * 0.55)), strafe: 0)
        }

        /// 시선 기준으로 걷되, 벽은 미끄러지며 막히고 가구는 몸통 반경만큼 못 들어가게 한다.
        private func movePersonCamera(forward: Float, strafe: Float) {
            // 보간 중에도 두 손가락 이동은 사용자가 바라보려는 방향을 기준으로 한다.
            let forwardDir = SIMD2(-sinf(personTargetYaw), -cosf(personTargetYaw))
            let rightDir = SIMD2(cosf(personTargetYaw), -sinf(personTargetYaw))
            var movement = forwardDir * forward + rightDir * strafe
            guard simd_length_squared(movement) > 1e-10 else { return }

            // 벽: 가구 이동과 같은 로직으로, 뚫는 성분만 깎아 벽을 따라 미끄러지게.
            let body = FurnitureFootprint(
                halfWidth: Self.personBodyRadius,
                halfDepth: Self.personBodyRadius,
                rotationY: 0
            )
            let motionPosition = personTargetPosition ?? SIMD2(cameraNode.position.x, cameraNode.position.z)
            movement = wallConstrainedMovement(
                footprint: body,
                from: SCNVector3(motionPosition.x, cameraNode.position.y, motionPosition.y),
                movement: movement
            )

            // 가구: 몸통 반경만큼 부풀린 발자국 안으로 못 들어가게 축별로 차단.
            // (축별 검사라 가구 모서리에서도 걸리지 않고 옆으로 미끄러진다)
            var position = motionPosition
            let stepX = SIMD2(position.x + movement.x, position.y)
            if !personIntersectsFurniture(at: stepX) { position = stepX }
            let stepZ = SIMD2(position.x, position.y + movement.y)
            if !personIntersectsFurniture(at: stepZ) { position = stepZ }

            personTargetPosition = position
        }

        /// 해당 위치가 (문/창문 제외) 어떤 가구의 발자국 + 몸통 반경 안인지 검사.
        private func personIntersectsFurniture(at point: SIMD2<Float>) -> Bool {
            for furniture in viewModel.layout.furnitures where !Self.isDoorOrWindow(furniture) {
                guard let node = furnitureContainer.childNode(withName: "furniture-\(furniture.itemId)", recursively: false) else { continue }
                let renderFurniture = displayFurniture(for: furniture)
                let footprint = FurnitureFootprint(
                    halfWidth: Float(renderFurniture.width ?? 0.8) * max(Float(renderFurniture.scale.x), 0.001) / 2,
                    halfDepth: Float(renderFurniture.depth ?? 0.8) * max(Float(renderFurniture.scale.z), 0.001) / 2,
                    rotationY: Float(renderFurniture.rotation.y)
                )
                if footprint.contains(point: point, center: SIMD2(node.position.x, node.position.z), padding: Self.personBodyRadius) {
                    return true
                }
            }
            return false
        }

        private func personIntersectsWall(at point: SIMD2<Float>) -> Bool {
            let colliders = wallColliders + infillColliders
            guard !colliders.isEmpty else { return false }
            let body = FurnitureFootprint(
                halfWidth: Self.personBodyRadius,
                halfDepth: Self.personBodyRadius,
                rotationY: 0
            )
            let position = SCNVector3(point.x, floorLevel + 1.45, point.y)
            for wall in colliders {
                guard wall.overlapsSpan(center: position, footprint: body) else { continue }
                let radius = body.projectionRadius(on: wall.normal)
                let innerMost = position.dotXZ(wall.normal) - radius
                if innerMost < wall.projection + Self.wallContactMargin {
                    return true
                }
            }
            return false
        }

        private func safePersonStartPosition(preferred: SIMD2<Float>) -> SIMD2<Float> {
            let bounds = roomBounds.inset(by: Self.personBodyRadius + 0.08)
            let clampedPreferred = SIMD2(
                bounds.clampedX(preferred.x, inset: 0),
                bounds.clampedZ(preferred.y, inset: 0)
            )
            if isSafePersonPosition(clampedPreferred) {
                return clampedPreferred
            }

            let step: Float = 0.35
            let maxRing = 12
            for ring in 1...maxRing {
                let distance = Float(ring) * step
                let samples = max(8, ring * 8)
                for index in 0..<samples {
                    let angle = Float(index) / Float(samples) * Float.pi * 2
                    let candidate = SIMD2(
                        bounds.clampedX(clampedPreferred.x + cosf(angle) * distance, inset: 0),
                        bounds.clampedZ(clampedPreferred.y + sinf(angle) * distance, inset: 0)
                    )
                    if isSafePersonPosition(candidate) {
                        return candidate
                    }
                }
            }
            return clampedPreferred
        }

        private func isSafePersonPosition(_ point: SIMD2<Float>) -> Bool {
            !personIntersectsFurniture(at: point) && !personIntersectsWall(at: point)
        }

        /// 사람 뷰 시작 방향: 눈 위치에서 ±X/±Z 네 방향으로 벽까지의 거리를 재서
        /// 가장 멀리까지 트여 있는 방향을 고른다. 벽 콜라이더가 없으면 -Z(기존 기본값).
        private func openestViewDirection(from eye: SCNVector3) -> SIMD2<Float> {
            let candidates: [SIMD2<Float>] = [SIMD2(0, -1), SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1)]
            guard !wallColliders.isEmpty else { return candidates[0] }

            func wallDistance(along direction: SIMD2<Float>) -> Float {
                var nearest = Float.greatestFiniteMagnitude
                let origin = SIMD2(eye.x, eye.z)
                // 시선이 벽면과 만나는 지점 검사를 위한 아주 작은 발자국.
                let probe = FurnitureFootprint(halfWidth: 0.05, halfDepth: 0.05, rotationY: 0)
                for wall in wallColliders {
                    let normal = SIMD2(wall.normal.x, wall.normal.z)
                    let approach = simd_dot(direction, normal)
                    guard approach < -1e-4 else { continue } // 벽을 향해 다가가는 방향만
                    let t = (simd_dot(origin, normal) - wall.projection) / -approach
                    guard t > 0.05 else { continue }
                    let hit = origin + direction * t
                    guard wall.overlapsSpan(center: SCNVector3(hit.x, eye.y, hit.y), footprint: probe) else { continue }
                    nearest = min(nearest, t)
                }
                return nearest
            }

            return candidates.max(by: { wallDistance(along: $0) < wallDistance(along: $1) }) ?? candidates[0]
        }

        private func skyViewScale() -> Float {
            let padding: Float = isScannedRoom ? 1.04 : 1.15
            let measurementPadding = viewModel.isMeasuring ? measurementCameraPadding * 2 : 0
            let verticalFit = sceneBounds.depth + measurementPadding
            let measuredAspect = Float((sceneView?.bounds.width ?? 0) / max(sceneView?.bounds.height ?? 1, 1))
            let aspect = isScannedRoom ? max(measuredAspect, 0.56) : measuredAspect
            let horizontalFit = aspect > 0 ? (sceneBounds.width + measurementPadding) / aspect : sceneBounds.width + measurementPadding
            return max(verticalFit, horizontalFit, 2.5) * padding
        }

        private func scannedRoomPerspectiveCameraPosition(radius: Float) -> SCNVector3 {
            let x = sceneCenter.x + radius * 0.7
            let z = sceneCenter.z + radius * 0.85
            let y = max(radius * 1.25, 4)
            return SCNVector3(x, y, z)
        }

        private func scannedRoomPerspectiveScale() -> Float {
            max(sceneBounds.width, sceneBounds.depth, 3) * 1.05
        }

        /// 회전·높이 슬라이더 조작을 전체 리빌드 없이 선택 노드에 즉시 반영합니다.
        func syncSelectedRotation(from layout: RoomLayout, selectedID: Int?) {
            guard let selectedID,
                  let item = layout.furnitures.first(where: { $0.itemId == selectedID }),
                  let node = furnitureContainer.childNode(withName: "furniture-\(selectedID)", recursively: false) else { return }
            node.eulerAngles.y = Float(item.rotation.y)
            // 높이(수직) 슬라이더 값을 바로 반영. x/z는 드래그가 관리하므로 y만 맞춘다.
            node.position.y = Float(item.position.y)
            syncDecorContainer(forItemID: selectedID)
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
            for node in furnitureContainer.childNodes {
                removeSelectionHighlight(from: node)
                // itemID가 nil일 때 이름 없는 노드(피규어 컨테이너 등)의 nil과 겹쳐
                // 하이라이트가 붙지 않도록 선택이 있을 때만 비교한다.
                guard let itemID else { continue }
                if Self.furnitureID(fromNodeOrAncestors: node) == itemID {
                    addSelectionHighlight(to: node)
                }
            }
        }

        private func removeSelectionHighlight(from node: SCNNode) {
            node.childNode(withName: selectionHighlightName, recursively: false)?.removeFromParentNode()
        }

        private func addSelectionHighlight(to node: SCNNode) {
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
            if isVisible {
                rebuildMeasurementNodes()
            }
            measurementContainer.isHidden = !isVisible
            if didChange, viewModel.viewMode == .skyView {
                applyCamera(mode: viewModel.viewMode, animated: true)
            }
        }

        private func rebuildMeasurementNodes() {
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

        private func addOverallMeasurementNodes(includeHeight: Bool) {
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
        private func addSkyviewHeightLabel() {
            let bounds = dynamicOverallBounds()
            let label = Self.makeMeasurementLabel(
                text: "높이 \(Self.formatCentimeters(roomHeight))",
                style: .overall
            )
            label.position = SCNVector3(bounds.maxX + 0.8, floorLevel + 0.02, bounds.minZ - 0.35)
            measurementContainer.addChildNode(label)
        }

        private func addObjectMeasurementNodes() {
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

        private func dynamicOverallBounds() -> HorizontalBounds {
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

        private func addHorizontalDimensionLine(
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
        private func addVerticalDimensionLine(position: SCNVector3, height: Float, label: String, style: MeasurementLabelStyle) {
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

        private static func makeHorizontalStroke(center: SCNVector3, direction: SCNVector3, length: Float, style: MeasurementLabelStyle) -> SCNNode {
            let box = SCNBox(width: CGFloat(max(length, 0.01)), height: 0.012, length: 0.012, chamferRadius: 0)
            box.materials = [measurementMaterial(color: style.lineColor)]
            let node = SCNNode(geometry: box)
            node.position = center
            node.eulerAngles.y = -atan2f(direction.z, direction.x)
            node.renderingOrder = 40
            return node
        }

        private static func makeVerticalStroke(center: SCNVector3, height: Float, style: MeasurementLabelStyle) -> SCNNode {
            let box = SCNBox(width: 0.012, height: CGFloat(max(height, 0.01)), length: 0.012, chamferRadius: 0)
            box.materials = [measurementMaterial(color: style.lineColor)]
            let node = SCNNode(geometry: box)
            node.position = center
            node.renderingOrder = 40
            return node
        }

        private static func measurementMaterial(color: UIColor) -> SCNMaterial {
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

        private static func dimensionDirection(for normal: SCNVector3) -> SCNVector3 {
            SCNVector3(-normal.z, 0, normal.x).normalizedXZ
        }

        private static func makeMeasurementLabel(text: String, style: MeasurementLabelStyle) -> SCNNode {
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
        private static func measurementLabelImage(text: String, style: MeasurementLabelStyle) -> (image: UIImage, size: CGSize) {
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

        private static func formatMeters(_ value: Float) -> String {
            String(format: "%.2fm", value)
        }

        /// 프론트엔드와 동일하게 치수를 cm 정수로 표기합니다. (예: 3.5m → "350 cm")
        private static func formatCentimeters(_ value: Float) -> String {
            "\(max(Int((value * 100).rounded()), 1)) cm"
        }

        // MARK: - Gestures

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            guard viewModel.viewMode != .person else {
                viewModel.selectedItemID = nil
                viewModel.isMovingSelectedFurniture = false
                movePersonCameraToTappedFloor(gesture)
                return
            }

            let point = gesture.location(in: sceneView)

            // 꾸미기 모드: 탭은 피규어 선택/배치 전용으로 동작한다.
            if let decoratingID = viewModel.decoratingItemID {
                handleDecorTap(at: point, in: sceneView, decoratingID: decoratingID)
                return
            }

            let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

            if let itemID = hits.compactMap({ Self.furnitureID(fromNodeOrAncestors: $0.node) }).first {
                viewModel.selectedItemID = itemID
            } else if let decor = hits.compactMap({ Self.decorID(fromNodeOrAncestors: $0.node) }).first {
                // 꾸미기 모드 밖에서 피규어를 탭하면 피규어가 올려진 책장을 선택한다.
                viewModel.selectedItemID = decor.itemID
            } else {
                viewModel.selectedItemID = nil
                viewModel.isMovingSelectedFurniture = false
            }
        }

        private func movePersonCameraToTappedFloor(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let point = gesture.location(in: sceneView)
            let hits = sceneView.hitTest(point, options: [.categoryBitMask: Self.floorHitCategory])
            if let floorHit = hits.first {
                walkPersonCamera(toward: SIMD2(floorHit.worldCoordinates.x, floorHit.worldCoordinates.z))
                return
            }

            // 투명 드래그 바닥은 SceneKit hit-test에서 제외될 수 있다(특히 스캔 메시의
            // 깊이 상태와 겹칠 때). 프런트엔드처럼 화면 탭 광선과 실제 바닥 평면의 교점으로
            // 목적지를 계산하면, 바닥 mesh hit 유무와 관계없이 탭 이동이 항상 동작한다.
            guard let target = floorPoint(from: point, in: sceneView) else { return }
            walkPersonCamera(toward: target)
        }

        private func floorPoint(from screenPoint: CGPoint, in sceneView: SCNView) -> SIMD2<Float>? {
            let near = sceneView.unprojectPoint(
                SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0)
            )
            let far = sceneView.unprojectPoint(
                SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1)
            )
            let direction = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
            guard abs(direction.y) > 1e-6 else { return nil }

            let distance = (floorLevel - near.y) / direction.y
            guard distance >= 0 else { return nil }
            return SIMD2(
                near.x + direction.x * distance,
                near.z + direction.z * distance
            )
        }

        /// 탭한 지점을 향해 "걸어서" 이동한다. 순간이동이 아니라 5cm 스텝 스윕이라
        /// 경로 중간의 벽·가구를 통과하지 않고, 목적지가 가구 위/벽 뒤라도
        /// 갈 수 있는 곳까지 가서 그 앞에 멈춘다. (탭이 조용히 무시되는 일 없음)
        private func walkPersonCamera(toward target: SIMD2<Float>) {
            let body = FurnitureFootprint(
                halfWidth: Self.personBodyRadius,
                halfDepth: Self.personBodyRadius,
                rotationY: 0
            )
            // 목표가 멀어도 한 번에 방을 가로지르지 않는다. 사람 눈높이 카메라의 장거리
            // 고속 활주는 가장 멀미가 큰 패턴이라, 편안한 보행 거리만 이동하고 다음 탭에서 이어간다.
            let start = personTargetPosition ?? SIMD2(cameraNode.position.x, cameraNode.position.z)
            var position = start
            let requested = target - start
            let total = simd_length(requested)
            guard total > 0.05 else { return }
            let travel = min(total, Self.personMaxTapTravel)
            let comfortTarget = start + requested / total * travel
            let stepCount = max(1, Int(ceilf(travel / 0.04)))
            let step = (comfortTarget - start) / Float(stepCount)

            for _ in 0..<stepCount {
                let adjusted = wallConstrainedMovement(
                    footprint: body,
                    from: SCNVector3(position.x, cameraNode.position.y, position.y),
                    movement: step
                )
                var next = position
                let stepX = SIMD2(next.x + adjusted.x, next.y)
                if !personIntersectsFurniture(at: stepX) { next = stepX }
                let stepZ = SIMD2(next.x, next.y + adjusted.y)
                if !personIntersectsFurniture(at: stepZ) { next = stepZ }
                if simd_length(next - position) < 0.005 { break } // 벽/가구에 막혀 더 못 감
                position = next
            }

            let distance = simd_length(position - start)
            guard distance > 0.02 else { return }
            // display link가 가속/감속을 적용하며 목표까지 걷는다. SceneKit transaction으로
            // 일정 속도 이동을 시키는 것보다 입력 중단/재입력 때도 속도가 자연스럽게 이어진다.
            personTargetPosition = position
        }

        private func startPersonComfortMotion() {
            guard personMotionDisplayLink == nil else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(advancePersonComfortMotion(_:)))
            displayLink.preferredFramesPerSecond = 120
            displayLink.add(to: .main, forMode: .common)
            personMotionDisplayLink = displayLink
            lastPersonMotionTimestamp = nil
        }

        func stopPersonComfortMotion() {
            personMotionDisplayLink?.invalidate()
            personMotionDisplayLink = nil
            personTargetPosition = nil
            personWalkVelocity = .zero
            lastPersonMotionTimestamp = nil
        }

        @objc private func advancePersonComfortMotion(_ displayLink: CADisplayLink) {
            guard viewModel.viewMode == .person else {
                stopPersonComfortMotion()
                return
            }
            defer { lastPersonMotionTimestamp = displayLink.timestamp }
            guard let previousTimestamp = lastPersonMotionTimestamp else { return }
            let deltaTime = Float(min(max(displayLink.timestamp - previousTimestamp, 1.0 / 240.0), 1.0 / 30.0))

            // 시선은 55ms 반응 시간으로만 완화한다. 손가락과 눈 사이의 지연은 느껴지지 않으면서
            // 미세한 방향 전환의 톱니/급정지를 제거한다.
            let lookBlend = 1 - expf(-deltaTime / Self.personLookResponse)
            personYaw += Self.shortestAngle(from: personYaw, to: personTargetYaw) * lookBlend
            personPitch += (personTargetPitch - personPitch) * lookBlend
            cameraNode.eulerAngles = SCNVector3(personPitch, personYaw, 0)

            guard let target = personTargetPosition else { return }
            let current = SIMD2(cameraNode.position.x, cameraNode.position.z)
            let remaining = target - current
            let distance = simd_length(remaining)
            guard distance > 0.002 else {
                cameraNode.position = SCNVector3(target.x, cameraNode.position.y, target.y)
                personWalkVelocity = .zero
                return
            }

            // 목표가 멀수록 보행 속도까지만, 가까워질수록 자연스럽게 감속한다.
            let desiredSpeed = min(Self.personWalkMaxSpeed, distance * 4.5)
            let desiredVelocity = remaining / distance * desiredSpeed
            let velocityDelta = desiredVelocity - personWalkVelocity
            let maxVelocityChange = Self.personWalkAcceleration * deltaTime
            let velocityDeltaLength = simd_length(velocityDelta)
            if velocityDeltaLength > maxVelocityChange {
                personWalkVelocity += velocityDelta / velocityDeltaLength * maxVelocityChange
            } else {
                personWalkVelocity = desiredVelocity
            }

            let step = personWalkVelocity * deltaTime
            if simd_length(step) >= distance {
                cameraNode.position = SCNVector3(target.x, cameraNode.position.y, target.y)
                personWalkVelocity = .zero
            } else {
                cameraNode.position = SCNVector3(
                    current.x + step.x,
                    cameraNode.position.y,
                    current.y + step.y
                )
            }
        }

        private static func shortestAngle(from: Float, to: Float) -> Float {
            var difference = (to - from).truncatingRemainder(dividingBy: .pi * 2)
            if difference > .pi { difference -= .pi * 2 }
            if difference < -.pi { difference += .pi * 2 }
            return difference
        }

        /// 가구 이동 팬은 "선택된 가구 위에서 시작한 터치"만 받는다. 그 외 터치는 받지 않아
        /// 즉시 실패하고, 카메라 컨트롤(시점 회전/이동/핀치 줌)이 평소처럼 이어받는다.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === movePanGesture else { return true }
            guard let sceneView else { return false }
            let point = touch.location(in: sceneView)
            let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

            // 꾸미기 중에는 기존 소품에서 시작한 한 손가락 팬만 가로챈다. 빈 곳 팬은
            // SceneKit 카메라 컨트롤로 그대로 전달되어 프런트의 제한된 orbit 조작과 같다.
            if let decoratingID = viewModel.decoratingItemID {
                guard viewModel.pendingFigure == nil else { return false }
                return hits.contains {
                    Self.decorID(fromNodeOrAncestors: $0.node)?.itemID == decoratingID
                }
            }

            guard let selectedID = viewModel.selectedItemID else { return false }
            // 벽 메우기 패널은 벽 구조라 드래그로 옮길 수 없다.
            if let item = viewModel.layout.furnitures.first(where: { $0.itemId == selectedID }),
               RoomEditorViewModel.isWallInfill(item) {
                return false
            }
            return hits.contains { Self.furnitureID(fromNodeOrAncestors: $0.node) == selectedID }
        }

        /// SceneKit 카메라 컨트롤(회전/이동/핀치) 제스처들이 가구 이동 팬의 "실패"를 기다리게 한다.
        /// 이동 팬은 선택된 가구 위에서 시작한 터치만 받으므로(delegate 참고), 그 외 터치에선
        /// 즉시 실패 처리되어 카메라 조작이 평소처럼 동작한다.
        func updateCameraGestureRequirements(on view: SCNView) {
            guard let movePan = movePanGesture else { return }
            for recognizer in view.gestureRecognizers ?? [] where recognizer !== movePan {
                let id = ObjectIdentifier(recognizer)
                guard !cameraGestureRequirementConfigured.contains(id) else { continue }
                recognizer.require(toFail: movePan)
                cameraGestureRequirementConfigured.insert(id)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView else { return }

            if let decoratingID = viewModel.decoratingItemID {
                handleDecorPan(gesture, in: sceneView, decoratingID: decoratingID)
                return
            }

            guard
                  let selectedID = viewModel.selectedItemID,
                  let node = furnitureContainer.childNode(withName: "furniture-\(selectedID)", recursively: false) else { return }

            // 바닥 노드만 hitTest 하도록 전용 카테고리로 제한합니다. (모든 노드 검사 → 바닥만 = 훨씬 가벼움)
            let point = gesture.location(in: sceneView)
            let hits = sceneView.hitTest(point, options: [.categoryBitMask: Self.floorHitCategory])
            guard let floorHit = hits.first else { return }

            // 드래그 시작: 손가락이 짚은 지점과 가구 중심의 간격을 기억해,
            // 가구의 "잡은 부분"이 손가락에 붙어 1:1로 따라오게 한다.
            if gesture.state == .began {
                dragGrabOffset = SIMD2(
                    node.position.x - floorHit.worldCoordinates.x,
                    node.position.z - floorHit.worldCoordinates.z
                )
                isSnapEngaged = false
            }

            let proposed = SCNVector3(
                floorHit.worldCoordinates.x + dragGrabOffset.x,
                node.position.y,
                floorHit.worldCoordinates.z + dragGrabOffset.y
            )
            let item = viewModel.layout.furnitures.first(where: { $0.itemId == selectedID })
            let renderFurniture = item.map { displayFurniture(for: $0) }

            // 웹 에디터(constrainedMovementBeforeWallCollision)와 동일한 이동 방식:
            // 목표 지점까지의 "이동 벡터"에서 벽을 파고드는 성분만 깎아낸다. 자석 스냅 없이도
            // 벽 쪽으로 밀면 남은 여유만큼만 이동해 벽에 딱 붙어 멈추고, 접선 성분은 살아 있어
            // 벽에 붙은 채로 자연스럽게 미끄러진다. 충돌 후 되돌리는 후처리는 하지 않는다.
            // 문/창문은 벽에 놓이는 reference라 웹과 동일하게 충돌 제한에서 제외한다.
            var next = proposed
            if let item, let renderFurniture, !Self.isDoorOrWindow(item) {
                let movement = SIMD2(proposed.x - node.position.x, proposed.z - node.position.z)
                let allowed = wallConstrainedMovement(for: renderFurniture, from: node.position, movement: movement)
                next = SCNVector3(node.position.x + allowed.x, node.position.y, node.position.z + allowed.y)
            }
            node.position = next
            // 책장 위 피규어들이 드래그를 실시간으로 따라오게 컨테이너를 동기화한다.
            syncDecorContainer(forItemID: selectedID)

            // 벽/가구에 새로 막히는 순간에만 가벼운 햅틱 — 닿았다는 걸 손끝으로 알 수 있게.
            let blockedDistance = simd_length(SIMD2(next.x - proposed.x, next.z - proposed.z))
            if blockedDistance > 0.02, !isSnapEngaged {
                isSnapEngaged = true
                Haptics.impact(.light)
            } else if blockedDistance < 0.005 {
                isSnapEngaged = false
            }

            if viewModel.isMeasuring {
                rebuildMeasurementNodes()
            }

            if gesture.state == .ended || gesture.state == .cancelled {
                // 벽 투명도 대상은 드래그 중엔 바뀔 일이 거의 없으니, 매 이벤트 대신 종료 시 한 번만 갱신.
                refreshViewFacingTransparencyTargets()
                guard let item else { return }
                viewModel.commitTransform(
                    itemID: selectedID,
                    transform: FurnitureTransform(
                        position: .init(x: Double(next.x), y: Double(next.y), z: Double(next.z)),
                        rotation: item.rotation,
                        scale: item.scale
                    )
                )
            }
        }

        /// 프런트엔드 `figure-move` 대응. 선반 위를 드래그하면 해당 표면으로 스냅하고,
        /// 손가락이 잠시 표면을 벗어나면 현재 선반 높이의 평면을 따라 책장 가장자리까지 이동한다.
        private func handleDecorPan(
            _ gesture: UIPanGestureRecognizer,
            in sceneView: SCNView,
            decoratingID: Int
        ) {
            let point = gesture.location(in: sceneView)
            let container = furnitureContainer.childNode(
                withName: "decorbox-\(decoratingID)",
                recursively: false
            )

            if gesture.state == .began {
                let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                guard let decor = hits.compactMap({ Self.decorID(fromNodeOrAncestors: $0.node) })
                    .first(where: { $0.itemID == decoratingID }),
                      let wrapper = container?.childNode(
                        withName: "decor-\(decoratingID)-\(decor.decorID)",
                        recursively: false
                      ) else { return }
                draggingDecorID = decor.decorID
                decorDragStartPosition = wrapper.position
                viewModel.selectedDecorID = decor.decorID
                Haptics.selection()
            }

            guard let container, let decorID = draggingDecorID,
                  let wrapper = container.childNode(
                    withName: "decor-\(decoratingID)-\(decorID)",
                    recursively: false
                  ) else { return }

            if gesture.state == .cancelled || gesture.state == .failed {
                if let start = decorDragStartPosition {
                    wrapper.position = start
                }
                draggingDecorID = nil
                decorDragStartPosition = nil
                return
            }

            if let candidate = decorDragPosition(
                at: point,
                in: sceneView,
                decoratingID: decoratingID,
                container: container,
                current: wrapper.position
            ), let constrained = viewModel.constrainedSelectedDecorPosition(candidate) {
                wrapper.position = SCNVector3(
                    Float(constrained.x),
                    Float(constrained.y),
                    Float(constrained.z)
                )
            }

            if gesture.state == .ended {
                viewModel.moveSelectedDecor(
                    toLocal: .init(
                        x: Double(wrapper.position.x),
                        y: Double(wrapper.position.y),
                        z: Double(wrapper.position.z)
                    )
                )
                draggingDecorID = nil
                decorDragStartPosition = nil
            }
        }

        private func decorDragPosition(
            at point: CGPoint,
            in sceneView: SCNView,
            decoratingID: Int,
            container: SCNNode,
            current: SCNVector3
        ) -> FurnitureTransform.Vector3? {
            let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let support = hits.first(where: { hit in
                Self.furnitureID(fromNodeOrAncestors: hit.node) == decoratingID
                    && RoomEditorSceneView.isDecorSupportNormal(hit.worldNormal)
            }) {
                let local = container.convertPosition(support.worldCoordinates, from: nil)
                return .init(x: Double(local.x), y: Double(local.y), z: Double(local.z))
            }

            // 프런트의 constrainedSupportPoint 폴백: 포인터 광선과 현재 선반 높이의
            // 월드 수평면 교차점을 사용한다. 책장 범위 제한은 ViewModel이 적용한다.
            let currentWorld = container.convertPosition(current, to: nil)
            let near = sceneView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let far = sceneView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            let direction = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
            guard abs(direction.y) > 1e-6 else { return nil }
            let distance = (currentWorld.y - near.y) / direction.y
            guard distance >= 0 else { return nil }
            let world = SCNVector3(
                near.x + direction.x * distance,
                currentWorld.y,
                near.z + direction.z * distance
            )
            let local = container.convertPosition(world, from: nil)
            return .init(x: Double(local.x), y: Double(current.y), z: Double(local.z))
        }

        private static func furnitureID(fromNodeOrAncestors node: SCNNode) -> Int? {
            var current: SCNNode? = node
            while let candidate = current {
                if let name = candidate.name, name.hasPrefix("furniture-") {
                    return Int(name.dropFirst("furniture-".count))
                }
                current = candidate.parent
            }
            return nil
        }

        private static func localHierarchyBounds(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
            var found = false
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

            func accumulate(_ node: SCNNode, _ parent: simd_float4x4) {
                if node.name == "__selection_highlight" || node.name == "__measurement_label" { return }
                let transform = parent * node.simdTransform
                if node.geometry != nil {
                    let (minBounds, maxBounds) = node.boundingBox
                    let corners: [SIMD4<Float>] = [
                        .init(minBounds.x, minBounds.y, minBounds.z, 1),
                        .init(maxBounds.x, minBounds.y, minBounds.z, 1),
                        .init(minBounds.x, maxBounds.y, minBounds.z, 1),
                        .init(maxBounds.x, maxBounds.y, minBounds.z, 1),
                        .init(minBounds.x, minBounds.y, maxBounds.z, 1),
                        .init(maxBounds.x, minBounds.y, maxBounds.z, 1),
                        .init(minBounds.x, maxBounds.y, maxBounds.z, 1),
                        .init(maxBounds.x, maxBounds.y, maxBounds.z, 1)
                    ]
                    for corner in corners {
                        let point = transform * corner
                        lo = simd_min(lo, SIMD3(point.x, point.y, point.z))
                        hi = simd_max(hi, SIMD3(point.x, point.y, point.z))
                        found = true
                    }
                }
                for child in node.childNodes {
                    accumulate(child, transform)
                }
            }

            for child in root.childNodes {
                accumulate(child, matrix_identity_float4x4)
            }
            if root.geometry != nil {
                accumulate(root, matrix_identity_float4x4)
            }

            guard found else { return nil }
            return (SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, hi.y, hi.z))
        }

        private static func horizontalBounds(of furnitures: [PlacedFurniture]) -> HorizontalBounds? {
            var bounds: HorizontalBounds?
            for furniture in furnitures {
                let footprint = Self.rotatedFootprint(for: furniture)
                let halfWidth = footprint.x
                let halfDepth = footprint.z
                let itemBounds = HorizontalBounds(
                    minX: Float(furniture.position.x) - halfWidth,
                    maxX: Float(furniture.position.x) + halfWidth,
                    minZ: Float(furniture.position.z) - halfDepth,
                    maxZ: Float(furniture.position.z) + halfDepth
                )
                bounds = HorizontalBounds.union(bounds, itemBounds)
            }
            return bounds
        }

        private static func horizontalBounds(of root: SCNNode) -> HorizontalBounds? {
            var bounds: HorizontalBounds?

            func accumulate(_ node: SCNNode) {
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
                    ]

                    for corner in corners {
                        let world = node.convertPosition(corner, to: nil)
                        let pointBounds = HorizontalBounds(
                            minX: world.x,
                            maxX: world.x,
                            minZ: world.z,
                            maxZ: world.z
                        )
                        bounds = HorizontalBounds.union(bounds, pointBounds)
                    }
                }

                for child in node.childNodes {
                    accumulate(child)
                }
            }

            accumulate(root)
            return bounds
        }

        private func displayFurniture(for furniture: PlacedFurniture) -> PlacedFurniture {
            guard isScannedRoom else { return furniture }
            let scaleLimit = fittingScaleLimit(for: furniture, in: usableRoomBounds())
            guard scaleLimit < 1 else { return furniture }

            var adjusted = furniture
            adjusted.scale = .init(
                x: furniture.scale.x * Double(scaleLimit),
                y: furniture.scale.y * Double(scaleLimit),
                z: furniture.scale.z * Double(scaleLimit)
            )
            return adjusted
        }

        private func fittingScaleLimit(for furniture: PlacedFurniture, in bounds: HorizontalBounds) -> Float {
            let clearance: Float = 0.08
            let footprint = Self.rotatedFootprint(for: furniture)
            let widthLimit = max(bounds.width - clearance * 2, 0.1) / max(footprint.x * 2, 0.001)
            let depthLimit = max(bounds.depth - clearance * 2, 0.1) / max(footprint.z * 2, 0.001)
            return min(1, widthLimit, depthLimit)
        }

        private func usableRoomBounds() -> HorizontalBounds {
            // 벽 안쪽 여백 없음 — 가구가 벽에 딱 붙게 합니다. (벽 안으로 들어가는 건 벽 콜라이더가 막음)
            roomBounds
        }

        private static func rotatedFootprint(for furniture: PlacedFurniture) -> (x: Float, z: Float) {
            let halfWidth = Float(furniture.width ?? 0.8) * max(Float(furniture.scale.x), 0.001) / 2
            let halfDepth = Float(furniture.depth ?? 0.8) * max(Float(furniture.scale.z), 0.001) / 2
            let angle = Float(furniture.rotation.y)
            let cosY = abs(cosf(angle))
            let sinY = abs(sinf(angle))
            return (
                x: halfWidth * cosY + halfDepth * sinY,
                z: halfWidth * sinY + halfDepth * cosY
            )
        }

        /// 벽과 가구 사이에 남기는 접촉 간격(m). 웹 에디터의 WALL_MOVEMENT_MARGIN(1e-4)과 동일.
        /// 이동 차단과 밀어내기가 같은 값을 써야 벽에 붙은 가구가 이벤트마다 떨리지 않는다.
        private static let wallContactMargin: Float = 0.0001

        /// 교체/추가 직후 가구가 벽을 뚫고 있으면 방 안쪽으로 되밀어 넣는다.
        /// (웹 에디터 initializeWallConstraints → pushObjectOutOfWalls 대응)
        /// SwiftUI 뷰 업데이트 중에 @Published를 건드리면 안 되므로 다음 런루프에서 처리한다.
        func resolveWallPenetrationIfNeeded() {
            guard viewModel.pendingWallResolveItemID != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.resolveWallPenetrationNow()
            }
        }

        private func resolveWallPenetrationNow() {
            guard let itemID = viewModel.pendingWallResolveItemID else { return }
            viewModel.pendingWallResolveItemID = nil
            guard let item = viewModel.layout.furnitures.first(where: { $0.itemId == itemID }),
                  !Self.isDoorOrWindow(item),
                  let node = furnitureContainer.childNode(withName: "furniture-\(itemID)", recursively: false) else { return }

            let furniture = displayFurniture(for: item)
            let resolved = pushedOutOfWalls(for: furniture, position: node.position)
            let moved = simd_length(SIMD2(resolved.x - node.position.x, resolved.z - node.position.z))
            guard moved > 0.0005 else { return }

            node.position = resolved
            syncDecorContainer(forItemID: itemID)
            viewModel.commitTransform(
                itemID: itemID,
                transform: FurnitureTransform(
                    position: .init(x: Double(resolved.x), y: Double(resolved.y), z: Double(resolved.z)),
                    rotation: item.rotation,
                    scale: item.scale
                ),
                recordHistory: false
            )
        }

        /// 웹 pushObjectOutOfWalls 포팅: 벽 경계를 침투한 만큼 방 안쪽 normal 방향으로
        /// 밀어내기를 침투가 없어질 때까지(최대 10회) 반복한다.
        private func pushedOutOfWalls(for furniture: PlacedFurniture, position: SCNVector3) -> SCNVector3 {
            let colliders = wallColliders + infillColliders
            guard !colliders.isEmpty else { return position }
            let footprint = FurnitureFootprint(
                halfWidth: Float(furniture.width ?? 0.8) * max(Float(furniture.scale.x), 0.001) / 2,
                halfDepth: Float(furniture.depth ?? 0.8) * max(Float(furniture.scale.z), 0.001) / 2,
                rotationY: Float(furniture.rotation.y)
            )
            var position = position
            for _ in 0..<10 {
                var didPush = false
                for wall in colliders {
                    guard wall.overlapsSpan(center: position, footprint: footprint) else { continue }
                    let radius = footprint.projectionRadius(on: wall.normal)
                    let innerMost = position.dotXZ(wall.normal) - radius
                    let penetration = (wall.projection + Self.wallContactMargin) - innerMost
                    guard penetration > 0.0005 else { continue }
                    position.x += wall.normal.x * penetration
                    position.z += wall.normal.z * penetration
                    didPush = true
                }
                if !didPush { break }
            }
            return position
        }

        /// 웹 에디터 collision.js의 constrainedMovementBeforeWallCollision 포팅.
        /// 이동 벡터를 3cm 스텝으로 나눠 스윕하면서, 각 벽에 대해 "남은 여유(clearance)보다
        /// 더 파고드는 안쪽 성분"만 깎아낸다. 접선 성분은 그대로 남아 벽에 붙은 채 미끄러지고,
        /// 빠른 드래그로 벽을 건너뛰는 터널링도 스텝 분할로 막는다.
        private func wallConstrainedMovement(for furniture: PlacedFurniture, from start: SCNVector3, movement: SIMD2<Float>) -> SIMD2<Float> {
            let footprint = FurnitureFootprint(
                halfWidth: Float(furniture.width ?? 0.8) * max(Float(furniture.scale.x), 0.001) / 2,
                halfDepth: Float(furniture.depth ?? 0.8) * max(Float(furniture.scale.z), 0.001) / 2,
                rotationY: Float(furniture.rotation.y)
            )
            return wallConstrainedMovement(footprint: footprint, from: start, movement: movement)
        }

        /// 발자국(footprint)을 직접 받는 본체 — 가구 이동과 사람 뷰 카메라(몸통)가 공유한다.
        private func wallConstrainedMovement(footprint: FurnitureFootprint, from start: SCNVector3, movement: SIMD2<Float>) -> SIMD2<Float> {
            let colliders = wallColliders + infillColliders
            guard !colliders.isEmpty else { return movement }
            let totalDistance = simd_length(movement)
            guard totalDistance > 1e-6 else { return .zero }

            // 웹 설정의 실제 유효 스텝: max(0.005, min(sweepStep 0.03, colliderHalfThickness 0.005 × 2)) = 1cm
            let stepSize: Float = 0.01
            let stepCount = min(max(1, Int(ceilf(totalDistance / stepSize))), 240)
            let requestedStep = movement / Float(stepCount)
            var position = SIMD2(start.x, start.z)
            var constrained = SIMD2<Float>(0, 0)

            for _ in 0..<stepCount {
                var adjusted = requestedStep
                // 한 벽에서 깎은 결과가 다른 벽을 향할 수 있어(코너), 변화가 없을 때까지 몇 번 반복.
                for _ in 0..<4 {
                    var changed = false
                    for wall in colliders {
                        let normal = SIMD2(wall.normal.x, wall.normal.z)
                        let inward = simd_dot(adjusted, normal)
                        guard inward < -1e-6 else { continue } // 벽 쪽으로 향하는 이동만 검사
                        let moved = position + adjusted
                        guard wall.overlapsSpan(center: SCNVector3(moved.x, start.y, moved.y), footprint: footprint) else { continue }
                        let radius = footprint.projectionRadius(on: wall.normal)
                        let innerMost = simd_dot(position, normal) - radius
                        let clearance = innerMost - (wall.projection + Self.wallContactMargin)
                        let blocked = -inward - max(0, clearance)
                        if blocked > 1e-6 {
                            adjusted += normal * blocked
                            changed = true
                        }
                    }
                    if !changed { break }
                }
                if simd_length_squared(adjusted) <= 1e-10 { break }
                position += adjusted
                constrained += adjusted
            }
            return constrained
        }

        private static func makeWallColliders(from root: SCNNode, roomCenter: SCNVector3) -> [WallCollider] {
            var colliders: [WallCollider] = []

            func visit(_ node: SCNNode) {
                if isWallGeometryNode(node) {
                    // 프런트엔드의 worldWallFaceCollidersFromGeometry와 같은 경로:
                    // 스캔 벽의 각 삼각형 면을 따로 충돌 면으로 만든다. 특히 대각선 벽을
                    // 한 개의 축 정렬 bounding box로 처리하면, 벽 바깥의 넓은 삼각 영역이
                    // 막혀 버리므로 이 세분화가 필수다.
                    let faceColliders = WallCollider.faceColliders(node: node, roomCenter: roomCenter)
                    if faceColliders.isEmpty, let fallback = WallCollider(node: node, roomCenter: roomCenter) {
                        // geometry element를 읽을 수 없는 특수 USD mesh만 기존 OBB 추정으로 보완.
                        colliders.append(fallback)
                    } else {
                        colliders += faceColliders
                    }
                }
                node.childNodes.forEach(visit)
            }

            visit(root)
            return colliders
        }

        private func refreshViewFacingTransparencyTargets() {
            guard isScannedRoom else {
                wallFacingUpdater.setWalls([])
                return
            }
            wallFacingUpdater.setWalls(shellViewFacingSurfaces + furnitureDoorWindowViewFacingSurfaces())
        }

        private static func makeViewFacingSurfaces(from colliders: [WallCollider]) -> [WallFacingUpdater.Wall] {
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

        private static func makeDoorWindowViewFacingSurfaces(from root: SCNNode, roomCenter: SCNVector3) -> [WallFacingUpdater.Wall] {
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

        private func furnitureDoorWindowViewFacingSurfaces() -> [WallFacingUpdater.Wall] {
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

        private static func isWallGeometryNode(_ node: SCNNode) -> Bool {
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
        private static func isFloorGeometryNode(_ node: SCNNode) -> Bool {
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

        private static func isDoorWindowGeometryNode(_ node: SCNNode) -> Bool {
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

        private static func isDoorOrWindow(_ furniture: PlacedFurniture) -> Bool {
            isDoorOrWindowName(furniture.furnitureName) || isDoorOrWindowName(furniture.modelName)
        }

        private static func isDoorOrWindowName(_ name: String?) -> Bool {
            guard let name else { return false }
            return name.localizedCaseInsensitiveContains("door") ||
                name.localizedCaseInsensitiveContains("window") ||
                name.localizedCaseInsensitiveContains("문") ||
                name.localizedCaseInsensitiveContains("창문")
        }

        private static func measurementSegments(for bounds: HorizontalBounds) -> [MeasurementSegment] {
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

private struct MeasurementSegment {
    var center: SCNVector3
    var normal: SCNVector3
    var length: Float
}

private enum MeasurementLabelStyle {
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

private struct FurnitureFootprint {
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

private struct WallCollider {
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
    /// 벽 투명화 on/off. 스카이뷰(탑다운)에서는 꺼서 벽이 사라져 보이지 않게 합니다.
    var isEnabled = true

    func setWalls(_ newWalls: [Wall]) {
        lock.lock()
        // 교체 전에 더 이상 투명화 대상이 아닌 노드만 다시 불투명으로 복원합니다.
        let nextNodes = Set(newWalls.map { ObjectIdentifier($0.node) })
        for wall in walls where !nextNodes.contains(ObjectIdentifier(wall.node)) {
            wall.node.opacity = 1
        }
        walls = newWalls
        lock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pointOfView = renderer.pointOfView else { return }
        let cameraPosition = pointOfView.presentation.simdWorldPosition
        let cameraXZ = SIMD2<Float>(cameraPosition.x, cameraPosition.z)

        lock.lock()
        let snapshot = walls
        lock.unlock()

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

private struct HorizontalBounds {
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

private extension SCNVector3 {
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
