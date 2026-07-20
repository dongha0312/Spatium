import Foundation
import OSLog
import SceneKit
import simd
import UIKit

// MARK: - 시야를 가리는 벽 투명화 대상과 메시 분류

extension RoomEditorSceneView.Coordinator {
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
    /// 에디터 첫 프레임 signpost(1회). 렌더 콜백은 SceneKit 렌더 스레드 한 곳에서만 오므로 락 불필요.
    private var didEmitFirstFrameSignpost = false
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
        if !didEmitFirstFrameSignpost {
            didEmitFirstFrameSignpost = true
            PerformanceSignposts.editor.emitEvent("editor.firstFrame")
        }
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
