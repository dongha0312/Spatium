import Foundation
import SceneKit
import UIKit

// MARK: - 가구 노드 렌더링

extension RoomEditorSceneView.Coordinator {
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
    func furnitureRenderSignature(for furniture: PlacedFurniture, source: PlacedFurniture) -> String {
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
    func applyRenderTransform(
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
    func makeWallInfillNode(for furniture: PlacedFurniture) -> SCNNode {
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

}
