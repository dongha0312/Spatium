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

    static func makeViewFacingSurfaces(
        from colliders: [WallCollider],
        kind: WallFacingUpdater.Wall.Kind = .wall
    ) -> [WallFacingUpdater.Wall] {
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
                normalXZ: SIMD2(collider.normal.x, collider.normal.z),
                kind: kind
            )
        }
    }

    static func makeDoorWindowViewFacingSurfaces(from root: SCNNode, roomCenter: SCNVector3) -> [WallFacingUpdater.Wall] {
        var surfaces: [WallFacingUpdater.Wall] = []

        func visit(_ node: SCNNode) {
            if isDoorWindowGeometryNode(node), let collider = WallCollider(node: node, roomCenter: roomCenter) {
                surfaces += makeViewFacingSurfaces(from: [collider], kind: .reference)
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
                normalXZ: SIMD2(normal.x, normal.z),
                kind: .reference
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
        enum Kind {
            case wall
            case reference
        }

        let node: SCNNode
        let centerXZ: SIMD2<Float>
        let normalXZ: SIMD2<Float>   // 방 안쪽(room-facing) 방향
        let kind: Kind
    }

    private struct MaterialSnapshot {
        let material: SCNMaterial
        let blendMode: SCNBlendMode
        let transparencyMode: SCNTransparencyMode
        let writesToDepthBuffer: Bool
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
    /// 방향 계산은 30Hz로 제한하되 실제 표면 전환은 SceneKit action이 별도로 보간한다.
    /// 마지막 목표를 기억해 같은 action을 매 평가마다 다시 시작하지 않는다.
    private let fadeActionKey = "spatium.view-facing-fade"
    private let fadeDuration: TimeInterval = 0.22
    private var targetOpacityByNode: [ObjectIdentifier: CGFloat] = [:]
    private var materialSnapshotsByNode: [ObjectIdentifier: [MaterialSnapshot]] = [:]
    private var fadedNodesByIdentifier: [ObjectIdentifier: SCNNode] = [:]
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

        reconcileRemovedSurfaces(with: snapshot)

        for wall in snapshot {
            let target: CGFloat
            if isEnabled {
                let toCamera = cameraXZ - wall.centerXZ
                let length = simd_length(toCamera)
                guard length > 0.0001 else { continue }
                let dot = simd_dot(toCamera / length, wall.normalXZ)
                target = Self.previewOpacity(for: dot, kind: wall.kind)
            } else {
                // 스카이뷰 등 투명화가 꺼진 모드에서는 모든 표면을 원래 상태로 복원한다.
                target = 1
            }
            updateOpacity(of: wall, to: target)
        }
    }

    /// 프런트엔드 wallVisibility/referenceVisibility와 같은 기준.
    /// 벽은 거의 사라지는 0.04, 문·창문은 위치를 희미하게 알 수 있는 0.08을 사용한다.
    static func previewOpacity(for dot: Float, kind: Wall.Kind) -> CGFloat {
        switch kind {
        case .wall:
            dot < -0.2 ? 0.04 : 1
        case .reference:
            dot < 0 ? 0.08 : 1
        }
    }

    private func updateOpacity(of wall: Wall, to target: CGFloat) {
        let identifier = ObjectIdentifier(wall.node)
        guard abs((targetOpacityByNode[identifier] ?? 1) - target) > 0.001 else { return }
        targetOpacityByNode[identifier] = target
        fadedNodesByIdentifier[identifier] = wall.node

        let snapshots = materialSnapshots(for: wall.node)
        if target < 1 {
            // 반투명 메시가 불투명 메시처럼 깊이를 먼저 기록하면 뒤쪽 색을 가려 어두운
            // 판처럼 보인다. 페이드가 진행되는 동안 alpha blend만 하고 depth write는 끈다.
            Self.applyPreviewRendering(to: snapshots)
        }

        wall.node.removeAction(forKey: fadeActionKey)
        let fade = SCNAction.fadeOpacity(to: target, duration: fadeDuration)
        fade.timingMode = .easeInEaseOut

        if target >= 1 {
            // 완전히 불투명해진 뒤에만 원래 depth/blend 상태를 복원한다. 전환 도중
            // 복원하면 문과 벽이 다시 깊이를 기록해 어두운 실루엣이 잠깐 나타난다.
            let restore = SCNAction.run { _ in
                Self.restoreMaterials(from: snapshots)
            }
            wall.node.runAction(.sequence([fade, restore]), forKey: fadeActionKey)
        } else {
            wall.node.runAction(fade, forKey: fadeActionKey)
        }
    }

    private func reconcileRemovedSurfaces(with walls: [Wall]) {
        let currentNodeIDs = Set(walls.map { ObjectIdentifier($0.node) })
        let removed = Set(targetOpacityByNode.keys).subtracting(currentNodeIDs)
        for identifier in removed {
            if let node = fadedNodesByIdentifier.removeValue(forKey: identifier) {
                node.removeAction(forKey: fadeActionKey)
                node.opacity = 1
            }
            if let snapshots = materialSnapshotsByNode.removeValue(forKey: identifier) {
                Self.restoreMaterials(from: snapshots)
            }
            targetOpacityByNode.removeValue(forKey: identifier)
        }
    }

    private func materialSnapshots(for node: SCNNode) -> [MaterialSnapshot] {
        let identifier = ObjectIdentifier(node)
        if let existing = materialSnapshotsByNode[identifier] {
            return existing
        }

        var seenMaterials = Set<ObjectIdentifier>()
        var snapshots: [MaterialSnapshot] = []
        func visit(_ candidate: SCNNode) {
            // USDZ의 여러 벽이 같은 material 인스턴스를 공유할 수 있다. 투명 벽 하나의
            // depth 설정이 인접한 불투명 벽에 번지지 않도록 geometry의 가벼운 복사본과
            // 독립 material을 이 표면에만 설치한다. vertex/index buffer는 SceneKit이 공유한다.
            if let geometry = candidate.geometry,
               let isolatedGeometry = geometry.copy() as? SCNGeometry {
                isolatedGeometry.materials = geometry.materials.map { material in
                    (material.copy() as? SCNMaterial) ?? material
                }
                candidate.geometry = isolatedGeometry
            }

            candidate.geometry?.materials.forEach { material in
                guard seenMaterials.insert(ObjectIdentifier(material)).inserted else { return }
                snapshots.append(MaterialSnapshot(
                    material: material,
                    blendMode: material.blendMode,
                    transparencyMode: material.transparencyMode,
                    writesToDepthBuffer: material.writesToDepthBuffer
                ))
            }
            candidate.childNodes.forEach(visit)
        }
        visit(node)
        materialSnapshotsByNode[identifier] = snapshots
        return snapshots
    }

    private static func applyPreviewRendering(to snapshots: [MaterialSnapshot]) {
        for snapshot in snapshots {
            snapshot.material.blendMode = .alpha
            snapshot.material.transparencyMode = .aOne
            snapshot.material.writesToDepthBuffer = false
        }
    }

    private static func restoreMaterials(from snapshots: [MaterialSnapshot]) {
        for snapshot in snapshots {
            snapshot.material.blendMode = snapshot.blendMode
            snapshot.material.transparencyMode = snapshot.transparencyMode
            snapshot.material.writesToDepthBuffer = snapshot.writesToDepthBuffer
        }
    }
}
