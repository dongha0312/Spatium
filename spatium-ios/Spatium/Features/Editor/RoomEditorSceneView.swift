import OSLog
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
        /// 프런트엔드 calculateRoomMeasurements 대응 — 방 셸에서 계산한 폭·깊이·높이·면적과
        /// 표시용 외곽선/높이선. 씬을 만들 때 한 번 계산하고 측정 노드 재구성에 재사용한다.
        var roomMeasurements: RoomMeasurements?
        var roomHeight: Float = 2.4
        /// 방 바닥의 월드 Y. 스캔 메시는 AR 좌표계라 0이 아닐 수 있고,
        /// 측정 치수선을 이 높이에 붙여야 바닥에 깔린 도면처럼 보인다.
        var floorLevel: Float = 0
        var isScannedRoom = false
        /// 측정 모드 스카이뷰에서 외곽 치수선·라벨·높이선이 화면에 들어오도록 하는 여백.
        /// 프런트엔드식 외곽선(오프셋 0.14 + 라벨 0.12)에 맞춘 값 — 이전 0.8m 오프셋
        /// 레이아웃용이던 1.25는 도면이 지나치게 작게 잡힌다.
        let measurementCameraPadding: Float = 0.5
        /// 파싱한 USDZ 방 셸(가구 제거 완료)을 캐시. 재생성 때 매번 디스크에서 다시 파싱하지 않도록.
        var shellCache: [String: SCNNode] = [:]
        /// 현재 씬에 올라간 방 셸(벽 색 재적용용) 및 마지막으로 반영한 벽 색.
        weak var shellNode: SCNNode?
        var renderedWallColor: String?
        var renderedFloorColor: String?
        /// 프런트엔드 spatiumDefaultWallColor/spatiumDefaultFloorColor 대응.
        /// 첫 tint 전에 원본 diffuse를 기록해, 색 선택 해제(nil) 시 스캔 원본 재질로 복원한다.
        /// (셸 템플릿의 clone은 material을 공유하므로 캐시된 원본도 tint로 함께 바뀐다)
        var originalSurfaceDiffuse: [ObjectIdentifier: Any] = [:]
        /// 카메라를 향한(시야를 가리는) 벽을 반투명 처리하는 렌더 델리게이트. (프런트 updateViewFacingWalls 대응)
        let wallFacingUpdater = WallFacingUpdater()

        init(viewModel: RoomEditorViewModel, modelLoader: FurnitureModelLoader) {
            self.viewModel = viewModel
            self.modelLoader = modelLoader
        }
    }
}

private final class CameraFittingSceneView: SCNView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
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
