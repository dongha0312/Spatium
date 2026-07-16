import Foundation
import QuartzCore
import SceneKit
import simd
import UIKit

// MARK: - 카메라 / 1인칭 이동

extension RoomEditorSceneView.Coordinator {
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
    func movePersonCamera(forward: Float, strafe: Float) {
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
    func personIntersectsFurniture(at point: SIMD2<Float>) -> Bool {
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

    func personIntersectsWall(at point: SIMD2<Float>) -> Bool {
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

    func safePersonStartPosition(preferred: SIMD2<Float>) -> SIMD2<Float> {
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

    func isSafePersonPosition(_ point: SIMD2<Float>) -> Bool {
        !personIntersectsFurniture(at: point) && !personIntersectsWall(at: point)
    }

    /// 사람 뷰 시작 방향: 눈 위치에서 ±X/±Z 네 방향으로 벽까지의 거리를 재서
    /// 가장 멀리까지 트여 있는 방향을 고른다. 벽 콜라이더가 없으면 -Z(기존 기본값).
    func openestViewDirection(from eye: SCNVector3) -> SIMD2<Float> {
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

    func skyViewScale() -> Float {
        let padding: Float = isScannedRoom ? 1.04 : 1.15
        let measurementPadding = viewModel.isMeasuring ? measurementCameraPadding * 2 : 0
        let verticalFit = sceneBounds.depth + measurementPadding
        let measuredAspect = Float((sceneView?.bounds.width ?? 0) / max(sceneView?.bounds.height ?? 1, 1))
        let aspect = isScannedRoom ? max(measuredAspect, 0.56) : measuredAspect
        let horizontalFit = aspect > 0 ? (sceneBounds.width + measurementPadding) / aspect : sceneBounds.width + measurementPadding
        return max(verticalFit, horizontalFit, 2.5) * padding
    }

    func scannedRoomPerspectiveCameraPosition(radius: Float) -> SCNVector3 {
        let x = sceneCenter.x + radius * 0.7
        let z = sceneCenter.z + radius * 0.85
        let y = max(radius * 1.25, 4)
        return SCNVector3(x, y, z)
    }

    func scannedRoomPerspectiveScale() -> Float {
        max(sceneBounds.width, sceneBounds.depth, 3) * 1.05
    }

    /// 회전·높이 슬라이더 조작을 전체 리빌드 없이 선택 노드에 즉시 반영합니다.
}
