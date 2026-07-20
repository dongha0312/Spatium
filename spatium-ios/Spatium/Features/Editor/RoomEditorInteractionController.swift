import Foundation
import QuartzCore
import SceneKit
import simd
import UIKit

// MARK: - 터치 / 드래그 / 1인칭 탭 이동

extension RoomEditorSceneView.Coordinator {
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

    func movePersonCameraToTappedFloor(_ gesture: UITapGestureRecognizer) {
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

    func floorPoint(from screenPoint: CGPoint, in sceneView: SCNView) -> SIMD2<Float>? {
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
    func walkPersonCamera(toward target: SIMD2<Float>) {
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

    func startPersonComfortMotion() {
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

    @objc func advancePersonComfortMotion(_ displayLink: CADisplayLink) {
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

    static func shortestAngle(from: Float, to: Float) -> Float {
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

        let didFinishDrag = gesture.state == .ended || gesture.state == .cancelled
        rebuildMeasurementsDuringInteraction(force: didFinishDrag)

        if didFinishDrag {
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
    func handleDecorPan(
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
        ) {
            wrapper.position = SCNVector3(
                Float(candidate.x),
                Float(candidate.y),
                Float(candidate.z)
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

    func decorDragPosition(
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
        // 월드 수평면 교차점을 목표로 삼되, 실제 책장 mesh를 아래로 탐색하며 현재
        // 지지면이 이어지는 곳까지만 2cm 단위로 이동한다.
        let currentWorld = container.convertPosition(current, to: nil)
        let near = sceneView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
        let far = sceneView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
        let direction = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        guard abs(direction.y) > 1e-6 else { return nil }
        let distance = (currentWorld.y - near.y) / direction.y
        guard distance >= 0 else { return nil }
        let requestedWorld = SIMD3<Float>(
            near.x + direction.x * distance,
            currentWorld.y,
            near.z + direction.z * distance
        )
        guard let furnitureNode = furnitureContainer.childNode(
            withName: "furniture-\(decoratingID)",
            recursively: false
        ) else { return nil }

        let constrainedWorld = RoomEditorSceneView.constrainedDecorSupportPoint(
            from: SIMD3(currentWorld.x, currentWorld.y, currentWorld.z),
            toward: requestedWorld
        ) { [weak self, weak furnitureNode] x, z, nearY in
            guard let self, let furnitureNode else { return nil }
            return self.decorSupportHeight(
                in: furnitureNode,
                worldX: x,
                worldZ: z,
                nearY: nearY
            )
        }
        let local = container.convertPosition(
            SCNVector3(constrainedWorld.x, constrainedWorld.y, constrainedWorld.z),
            from: nil
        )
        return .init(x: Double(local.x), y: Double(local.y), z: Double(local.z))
    }

    /// 웹 `supportHeightAt`과 같은 10cm 위 → 6cm 아래의 짧은 down-raycast다.
    /// 낮은 다음 선반이나 책장 바닥은 같은 층으로 인정하지 않아 가장자리에서 멈춘다.
    func decorSupportHeight(
        in furnitureNode: SCNNode,
        worldX: Float,
        worldZ: Float,
        nearY: Float
    ) -> Float? {
        let startWorld = SCNVector3(worldX, nearY + 0.10, worldZ)
        let endWorld = SCNVector3(worldX, nearY - 0.06, worldZ)
        let startLocal = furnitureNode.convertPosition(startWorld, from: nil)
        let endLocal = furnitureNode.convertPosition(endWorld, from: nil)
        let hits = furnitureNode.hitTestWithSegment(
            from: startLocal,
            to: endLocal,
            options: [
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.backFaceCulling.rawValue: false,
                SCNHitTestOption.ignoreHiddenNodes.rawValue: true
            ]
        )
        return hits.first(where: { hit in
            RoomEditorSceneView.isDecorSupportNormal(hit.worldNormal)
                && hit.worldCoordinates.y >= nearY - 0.061
                && hit.worldCoordinates.y <= nearY + 0.101
        })?.worldCoordinates.y
    }

    static func furnitureID(fromNodeOrAncestors node: SCNNode) -> Int? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, name.hasPrefix("furniture-") {
                return Int(name.dropFirst("furniture-".count))
            }
            current = candidate.parent
        }
        return nil
    }

    static func localHierarchyBounds(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var found = false
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        func accumulate(_ node: SCNNode, _ transform: simd_float4x4) {
            if node.name == "__selection_highlight" || node.name == "__measurement_label" { return }
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
                accumulate(child, transform * child.simdTransform)
            }
        }

        // 반환값은 root 자체의 position/rotation/scale을 제외한 root 로컬 bounds다.
        // root geometry는 identity로, 하위 geometry는 각 child transform부터 누적한다.
        if root.geometry != nil {
            accumulate(root, matrix_identity_float4x4)
        }
        for child in root.childNodes {
            accumulate(child, child.simdTransform)
        }

        guard found else { return nil }
        return (SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, hi.y, hi.z))
    }

    static func horizontalBounds(of furnitures: [PlacedFurniture]) -> HorizontalBounds? {
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

    static func horizontalBounds(of root: SCNNode) -> HorizontalBounds? {
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

}
