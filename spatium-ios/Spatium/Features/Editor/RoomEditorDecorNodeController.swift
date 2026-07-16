import Foundation
import SceneKit
import simd
import UIKit

// MARK: - 피규어 노드 / 선반 배치

extension RoomEditorSceneView.Coordinator {
    // MARK: - 책장 꾸미기 (피규어) 렌더링

    /// 피규어들은 가구 노드의 "자식"이 아니라 나란히 놓인 전용 컨테이너에 담는다.
    /// 가구 노드는 GLB 맞춤 스케일(비균일)이 걸려 있어 자식으로 붙이면 피규어가 찌그러지므로,
    /// 스케일 없는 컨테이너를 가구와 같은 위치/회전으로 동기화해 부모 역할을 시킨다.
    func updateDecorContainer(for furniture: PlacedFurniture, furnitureNode: SCNNode) {
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

    func syncDecorContainerTransform(container: SCNNode, furnitureNode: SCNNode) {
        container.position = furnitureNode.position
        container.eulerAngles = SCNVector3(0, furnitureNode.eulerAngles.y, 0)
    }

    /// 가구 노드가 직접 움직였을 때(드래그/슬라이더/벽 되밀기) 피규어 컨테이너를 따라 붙인다.
    func syncDecorContainer(forItemID itemID: Int) {
        guard let node = furnitureContainer.childNode(withName: "furniture-\(itemID)", recursively: false),
              let container = furnitureContainer.childNode(withName: "decorbox-\(itemID)", recursively: false) else { return }
        syncDecorContainerTransform(container: container, furnitureNode: node)
    }

    static func decorContainerItemID(_ node: SCNNode) -> Int? {
        guard let name = node.name, name.hasPrefix("decorbox-") else { return nil }
        return Int(name.dropFirst("decorbox-".count))
    }

    /// "decor-<가구ID>-<피규어ID>" 이름을 노드 또는 조상에서 찾아 해석한다.
    /// 가구ID는 로컬 아이템일 때 음수라서("decor--2-1"), 마지막 "-"를 기준으로 나눈다.
    static func decorID(fromNodeOrAncestors node: SCNNode) -> (itemID: Int, decorID: Int)? {
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
            let container = furnitureContainer.childNode(
                withName: "decorbox-\(target)",
                recursively: false
            ) ?? makeDecorContainerIfMissing(for: target)
            if let container {
                let heights = RoomEditorShelfDetector.detectHeights(in: node, relativeTo: container)
                if !heights.isEmpty {
                    // SwiftUI updateUIView 안에서 @Published를 바로 변경하지 않고 다음 run loop에 반영한다.
                    DispatchQueue.main.async { [weak viewModel] in
                        guard viewModel?.decoratingItemID == target else { return }
                        viewModel?.updateDecorShelfHeights(heights)
                    }
                }
            }
        } else {
            decorCameraItemID = nil
            applyCamera(mode: viewModel.viewMode, animated: true)
        }
    }

    /// 웹 computeDecorView 대응: 책장의 열린 선반 정면에서 25도 위로 내려다보는
    /// 근접 시점. 선반 안쪽 바닥이 보여 피규어를 올릴 자리를 탭하기 좋다.
    func applyDecorCamera(to node: SCNNode) {
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
    func handleDecorTap(at point: CGPoint, in sceneView: SCNView, decoratingID: Int) {
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
    func makeDecorContainerIfMissing(for itemID: Int) -> SCNNode? {
        guard let node = furnitureContainer.childNode(withName: "furniture-\(itemID)", recursively: false) else {
            return nil
        }
        let container = SCNNode()
        container.name = "decorbox-\(itemID)"
        syncDecorContainerTransform(container: container, furnitureNode: node)
        furnitureContainer.addChildNode(container)
        return container
    }

}
