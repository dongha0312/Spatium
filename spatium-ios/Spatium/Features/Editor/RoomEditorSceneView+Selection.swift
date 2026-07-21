import SceneKit
import UIKit

// MARK: - 선택 하이라이트와 선택 가구 상태 동기화

extension RoomEditorSceneView.Coordinator {
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
        let selectionChanged = renderedSelectedItemID != itemID
        renderedSelectedItemID = itemID
        // 프런트엔드처럼 측정 모드에서는 선택된 가구의 치수 라벨을 함께 보여주므로,
        // 선택이 바뀌면 측정 노드를 다시 만든다.
        if selectionChanged, viewModel.isMeasuring {
            rebuildMeasurementNodes()
        }

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
}
