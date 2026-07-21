import Foundation
import QuartzCore
import SceneKit
import simd
import UIKit

struct DecorCameraState {
    let position: SCNVector3
    let orientation: SCNQuaternion
    let target: SCNVector3
    let usesOrthographicProjection: Bool
    let orthographicScale: Double
    let fieldOfView: CGFloat
    let zNear: Double
    let zFar: Double
    let interactionMode: SCNInteractionMode
    let automaticTarget: Bool
    let inertiaEnabled: Bool
    let inertiaFriction: Float
    let worldUp: SCNVector3
    let minimumVerticalAngle: Float
    let maximumVerticalAngle: Float
    let minimumHorizontalAngle: Float
    let maximumHorizontalAngle: Float
}

struct DecorCameraView {
    let target: SIMD3<Float>
    let front: SIMD3<Float>
    let right: SIMD3<Float>
    let minimumDistance: Float
    let maximumDistance: Float
    let minimumElevation: Float
    let maximumElevation: Float
    let maximumAzimuth: Float
    var distance: Float
    var elevation: Float
    var azimuth: Float

    var position: SIMD3<Float> {
        let horizontalDirection = simd_normalize(
            front * cosf(azimuth) + right * sinf(azimuth)
        )
        let horizontalDistance = distance * cosf(elevation)
        return target
            + horizontalDirection * horizontalDistance
            + SIMD3<Float>(0, distance * sinf(elevation), 0)
    }
}

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
            savedDecorCameraState = captureDecorCameraState()
            decorCameraItemID = target
            applyDecorCamera(to: node, animated: true)
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
            restoreDecorCamera(animated: true)
        }
    }

    func captureDecorCameraState() -> DecorCameraState? {
        guard let camera = cameraNode.camera,
              let controller = sceneView?.defaultCameraController else { return nil }
        controller.stopInertia()
        let presented = cameraNode.presentation
        return DecorCameraState(
            position: presented.position,
            orientation: presented.orientation,
            target: controller.target,
            usesOrthographicProjection: camera.usesOrthographicProjection,
            orthographicScale: camera.orthographicScale,
            fieldOfView: camera.fieldOfView,
            zNear: camera.zNear,
            zFar: camera.zFar,
            interactionMode: controller.interactionMode,
            automaticTarget: controller.automaticTarget,
            inertiaEnabled: controller.inertiaEnabled,
            inertiaFriction: controller.inertiaFriction,
            worldUp: controller.worldUp,
            minimumVerticalAngle: controller.minimumVerticalAngle,
            maximumVerticalAngle: controller.maximumVerticalAngle,
            minimumHorizontalAngle: controller.minimumHorizontalAngle,
            maximumHorizontalAngle: controller.maximumHorizontalAngle
        )
    }

    /// 웹 computeDecorView 대응: 책장 OBB를 정면 카메라의 가로·세로·깊이 축으로
    /// 투영해 휴대폰 화면 비율에서도 전체 책장이 1.2배 여백 안에 들어오게 한다.
    func makeDecorCameraView(for node: SCNNode) -> DecorCameraView? {
        guard let bounds = Self.localHierarchyBounds(of: node) else { return nil }
        let center = node.convertPosition(SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        ), to: nil)
        let target = SIMD3(center.x, center.y, center.z)

        let frontWorld = node.convertVector(SCNVector3(0, 0, 1), to: nil)
        // 앱 GLB의 열린 선반 면인 로컬 +Z를 가구 회전만 반영해 사용한다.
        // 방 중심 기준으로 다시 뒤집으면 실제 모델의 뒤판을 바라보게 된다.
        let frontXZ = RoomEditorSceneView.decorFrontDirection(from: frontWorld)
        let front = SIMD3(frontXZ.x, 0, frontXZ.y)
        let right = simd_normalize(SIMD3(-front.z, 0, front.x))
        let up = SIMD3<Float>(0, 1, 0)

        let localCorners = [
            SCNVector3(bounds.min.x, bounds.min.y, bounds.min.z),
            SCNVector3(bounds.max.x, bounds.min.y, bounds.min.z),
            SCNVector3(bounds.min.x, bounds.max.y, bounds.min.z),
            SCNVector3(bounds.max.x, bounds.max.y, bounds.min.z),
            SCNVector3(bounds.min.x, bounds.min.y, bounds.max.z),
            SCNVector3(bounds.max.x, bounds.min.y, bounds.max.z),
            SCNVector3(bounds.min.x, bounds.max.y, bounds.max.z),
            SCNVector3(bounds.max.x, bounds.max.y, bounds.max.z)
        ]
        var halfWidth: Float = 0
        var halfHeight: Float = 0
        var halfDepth: Float = 0
        for corner in localCorners {
            let world = node.convertPosition(corner, to: nil)
            let relative = SIMD3(world.x, world.y, world.z) - target
            halfWidth = max(halfWidth, abs(simd_dot(relative, right)))
            halfHeight = max(halfHeight, abs(simd_dot(relative, up)))
            halfDepth = max(halfDepth, abs(simd_dot(relative, front)))
        }

        let boundsSize = sceneView?.bounds.size ?? .zero
        let aspect = boundsSize.height > 0
            ? Float(boundsSize.width / boundsSize.height)
            : 1
        let distance = RoomEditorSceneView.decorCameraDistance(
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            halfDepth: halfDepth,
            verticalFieldOfViewDegrees: 50,
            aspectRatio: aspect
        )
        let elevation = Float(25 * Double.pi / 180)

        return DecorCameraView(
            target: target,
            front: front,
            right: right,
            minimumDistance: distance * 0.35,
            maximumDistance: distance * 1.8,
            minimumElevation: 0,
            maximumElevation: Float(55 * Double.pi / 180),
            maximumAzimuth: Float(50 * Double.pi / 180),
            distance: distance,
            elevation: elevation,
            azimuth: 0
        )
    }

    /// 1.3초 ease-in-out 전환, 정면 ±50°/상하 ±30° orbit, 0.35~1.8배 줌까지
    /// 프런트엔드 decorCamera와 같은 값으로 적용한다.
    func applyDecorCamera(to node: SCNNode, animated: Bool) {
        guard let view = makeDecorCameraView(for: node) else { return }
        decorCameraView = view
        decorCameraTransitionRevision &+= 1
        let revision = decorCameraTransitionRevision
        isDecorCameraTransitioning = animated
        sceneView?.allowsCameraControl = false
        decorCameraOrbitGesture?.isEnabled = false
        decorCameraZoomGesture?.isEnabled = false

        if let controller = sceneView?.defaultCameraController {
            controller.stopInertia()
            controller.interactionMode = .orbitTurntable
            controller.target = SCNVector3(view.target.x, view.target.y, view.target.z)
            controller.automaticTarget = false
            controller.inertiaEnabled = true
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 1.3 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      self.decorCameraTransitionRevision == revision,
                      self.viewModel.decoratingItemID == self.decorCameraItemID else { return }
                self.isDecorCameraTransitioning = false
                self.decorCameraOrbitGesture?.isEnabled = true
                self.decorCameraZoomGesture?.isEnabled = true
            }
        }
        cameraNode.camera?.usesOrthographicProjection = false
        cameraNode.camera?.fieldOfView = 50
        cameraNode.camera?.zNear = Double(max(view.distance / 1_000, 0.01))
        applyDecorCameraTransform(view)
        SCNTransaction.commit()
        sceneView?.pointOfView = cameraNode

        if !animated {
            isDecorCameraTransitioning = false
            decorCameraOrbitGesture?.isEnabled = true
            decorCameraZoomGesture?.isEnabled = true
        }
    }

    func restoreDecorCamera(animated: Bool) {
        decorCameraTransitionRevision &+= 1
        let revision = decorCameraTransitionRevision
        decorCameraView = nil
        decorCameraOrbitGesture?.isEnabled = false
        decorCameraZoomGesture?.isEnabled = false

        guard let state = savedDecorCameraState else {
            isDecorCameraTransitioning = false
            applyCamera(mode: viewModel.viewMode, animated: animated)
            return
        }
        savedDecorCameraState = nil
        isDecorCameraTransitioning = animated
        sceneView?.allowsCameraControl = false
        sceneView?.defaultCameraController.stopInertia()
        sceneView?.defaultCameraController.target = state.target

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 1.3 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.decorCameraTransitionRevision == revision else { return }
                if let controller = self.sceneView?.defaultCameraController {
                    controller.interactionMode = state.interactionMode
                    controller.target = state.target
                    controller.automaticTarget = state.automaticTarget
                    controller.inertiaEnabled = state.inertiaEnabled
                    controller.inertiaFriction = state.inertiaFriction
                    controller.worldUp = state.worldUp
                    controller.minimumVerticalAngle = state.minimumVerticalAngle
                    controller.maximumVerticalAngle = state.maximumVerticalAngle
                    controller.minimumHorizontalAngle = state.minimumHorizontalAngle
                    controller.maximumHorizontalAngle = state.maximumHorizontalAngle
                }
                self.isDecorCameraTransitioning = false
                self.sceneView?.allowsCameraControl = self.viewModel.viewMode != .person
            }
        }
        cameraNode.camera?.usesOrthographicProjection = state.usesOrthographicProjection
        cameraNode.camera?.orthographicScale = state.orthographicScale
        cameraNode.camera?.fieldOfView = state.fieldOfView
        cameraNode.camera?.zNear = state.zNear
        cameraNode.camera?.zFar = state.zFar
        cameraNode.position = state.position
        cameraNode.orientation = state.orientation
        SCNTransaction.commit()

        if !animated {
            isDecorCameraTransitioning = false
            sceneView?.allowsCameraControl = viewModel.viewMode != .person
        }
    }

    func applyDecorCameraTransform(_ view: DecorCameraView) {
        cameraNode.simdPosition = view.position
        cameraNode.look(
            at: SCNVector3(view.target.x, view.target.y, view.target.z),
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )
        sceneView?.defaultCameraController.target = SCNVector3(
            view.target.x,
            view.target.y,
            view.target.z
        )
    }

    /// 화면 회전/크기 변경 중에도 웹의 OBB 맞춤 여백을 다시 계산한다. 꾸미기 진입 전
    /// 카메라 스냅샷은 건드리지 않아 완료 시 원래 시점으로 정확히 복귀한다.
    func refitDecorCameraForCurrentLayout() -> Bool {
        guard !isDecorCameraTransitioning,
              let itemID = viewModel.decoratingItemID,
              let node = furnitureContainer.childNode(
                withName: "furniture-\(itemID)",
                recursively: false
              ) else { return false }
        applyDecorCamera(to: node, animated: false)
        return true
    }

    @objc func handleDecorCameraOrbit(_ gesture: UIPanGestureRecognizer) {
        guard let sceneView, var view = decorCameraView, !isDecorCameraTransitioning else { return }
        if gesture.state == .began { lastDecorCameraOrbitTranslation = .zero }
        let translation = gesture.translation(in: sceneView)
        let deltaX = Float(translation.x - lastDecorCameraOrbitTranslation.x)
        let deltaY = Float(translation.y - lastDecorCameraOrbitTranslation.y)
        lastDecorCameraOrbitTranslation = translation
        let viewportHeight = Float(max(sceneView.bounds.height, 1))

        view.azimuth = min(
            max(view.azimuth - deltaX / viewportHeight * .pi * 2, -view.maximumAzimuth),
            view.maximumAzimuth
        )
        view.elevation = min(
            max(view.elevation + deltaY / viewportHeight * .pi * 2, view.minimumElevation),
            view.maximumElevation
        )
        decorCameraView = view
        applyDecorCameraTransform(view)

        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            lastDecorCameraOrbitTranslation = .zero
        }
    }

    @objc func handleDecorCameraZoom(_ gesture: UIPinchGestureRecognizer) {
        guard var view = decorCameraView, !isDecorCameraTransitioning else { return }
        let scale = Float(gesture.scale)
        guard scale.isFinite, scale > 0.001 else { return }
        view.distance = min(max(view.distance / scale, view.minimumDistance), view.maximumDistance)
        gesture.scale = 1
        decorCameraView = view
        applyDecorCameraTransform(view)
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
