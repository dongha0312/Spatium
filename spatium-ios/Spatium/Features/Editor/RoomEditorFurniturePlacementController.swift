import Foundation
import SceneKit
import simd
import UIKit

// MARK: - 가구 배치 경계 / 벽 충돌

extension RoomEditorSceneView.Coordinator {
    func displayFurniture(for furniture: PlacedFurniture) -> PlacedFurniture {
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

    func fittingScaleLimit(for furniture: PlacedFurniture, in bounds: HorizontalBounds) -> Float {
        let clearance: Float = 0.08
        let footprint = Self.rotatedFootprint(for: furniture)
        let widthLimit = max(bounds.width - clearance * 2, 0.1) / max(footprint.x * 2, 0.001)
        let depthLimit = max(bounds.depth - clearance * 2, 0.1) / max(footprint.z * 2, 0.001)
        return min(1, widthLimit, depthLimit)
    }

    func usableRoomBounds() -> HorizontalBounds {
        // 벽 안쪽 여백 없음 — 가구가 벽에 딱 붙게 합니다. (벽 안으로 들어가는 건 벽 콜라이더가 막음)
        roomBounds
    }

    static func rotatedFootprint(for furniture: PlacedFurniture) -> (x: Float, z: Float) {
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
    static let wallContactMargin: Float = 0.0001

    /// 교체/추가 직후 가구가 벽을 뚫고 있으면 방 안쪽으로 되밀어 넣는다.
    /// (웹 에디터 initializeWallConstraints → pushObjectOutOfWalls 대응)
    /// SwiftUI 뷰 업데이트 중에 @Published를 건드리면 안 되므로 다음 런루프에서 처리한다.
    func resolveWallPenetrationIfNeeded() {
        guard viewModel.pendingWallResolveItemID != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.resolveWallPenetrationNow()
        }
    }

    func resolveWallPenetrationNow() {
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
    func pushedOutOfWalls(for furniture: PlacedFurniture, position: SCNVector3) -> SCNVector3 {
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
    func wallConstrainedMovement(for furniture: PlacedFurniture, from start: SCNVector3, movement: SIMD2<Float>) -> SIMD2<Float> {
        let footprint = FurnitureFootprint(
            halfWidth: Float(furniture.width ?? 0.8) * max(Float(furniture.scale.x), 0.001) / 2,
            halfDepth: Float(furniture.depth ?? 0.8) * max(Float(furniture.scale.z), 0.001) / 2,
            rotationY: Float(furniture.rotation.y)
        )
        return wallConstrainedMovement(footprint: footprint, from: start, movement: movement)
    }

    /// 발자국(footprint)을 직접 받는 본체 — 가구 이동과 사람 뷰 카메라(몸통)가 공유한다.
    func wallConstrainedMovement(footprint: FurnitureFootprint, from start: SCNVector3, movement: SIMD2<Float>) -> SIMD2<Float> {
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

    static func makeWallColliders(from root: SCNNode, roomCenter: SCNVector3) -> [WallCollider] {
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

}
