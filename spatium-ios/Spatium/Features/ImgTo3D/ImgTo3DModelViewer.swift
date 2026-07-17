import GLTFKit2
import OSLog
import SceneKit
import simd
import SwiftUI
import UIKit

struct ImgTo3DModelViewer: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var transform: ImgTo3DModelTransform
    let mode: ImgTo3DViewerMode
    let activeAxis: ImgTo3DTransformAxis
    let floorSnap: Bool
    let modelURL: URL?
    let cameraPreset: ImgTo3DCameraPreset
    let cameraResetToken: Int
    let autoAlignToken: Int
    let onInteractionBegan: () -> Void
    let onModelLoaded: (ImgTo3DModelSize, String?) -> Void
    let onModelBoundsChanged: (ImgTo3DModelSize) -> Void
    let onAutoAlignment: (ImgTo3DModelTransform) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor { traits in
            UIColor(hexString: traits.userInterfaceStyle == .dark ? "#212A2B" : "#F2EEE6")
        }
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.isPlaying = false
        view.scene = context.coordinator.makeScene()
        view.pointOfView = context.coordinator.cameraNode
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.target = SCNVector3(0, 0.45, 0)
        lockCameraRoll(view)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
        context.coordinator.adjustmentPan = pan
        context.coordinator.sceneView = view
        context.coordinator.updateAppearance(colorScheme: colorScheme)
        context.coordinator.apply(transform: transform, floorSnap: floorSnap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.loadModelIfNeeded(from: modelURL)
        coordinator.autoAlignIfNeeded(token: autoAlignToken, transform: transform)
        coordinator.resetCameraIfNeeded(token: cameraResetToken, preset: cameraPreset)
        coordinator.apply(transform: transform, floorSnap: floorSnap)
        coordinator.updateGizmo(mode: mode, axis: activeAxis)
        coordinator.updateAppearance(colorScheme: colorScheme)

        let adjustsModel = mode != .orbit
        coordinator.adjustmentPan?.isEnabled = adjustsModel
        view.allowsCameraControl = !adjustsModel
        view.defaultCameraController.interactionMode = .orbitTurntable
        lockCameraRoll(view)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.releaseSceneResources(from: view)
    }

    /// SceneKit 기본 카메라 컨트롤의 두 손가락 비틀기(roll) 제스처를 끕니다.
    /// 턴테이블 모드도 이 제스처는 허용해서, 시점을 돌리다 보면 지평선이 옆으로 누운 채 누적됩니다.
    private func lockCameraRoll(_ view: SCNView) {
        view.gestureRecognizers?
            .compactMap { $0 as? UIRotationGestureRecognizer }
            .forEach { $0.isEnabled = false }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ImgTo3DModelViewer
        weak var sceneView: SCNView?
        var adjustmentPan: UIPanGestureRecognizer?
        let cameraNode = SCNNode()

        private let modelContainer = SCNNode()
        private let gizmoNode = SCNNode()
        /// 로드 시점에 캐시한 모델의 컨테이너 로컬 AABB. 드래그 중 매 프레임 전체 노드를 순회하지 않기 위함.
        private var modelLocalBounds: (min: SCNVector3, max: SCNVector3)?
        /// 자동 정렬·노이즈 내성 접지에 사용하는 실제 메시 정점의 컨테이너 로컬 좌표 샘플.
        private var modelLocalSamples: [SIMD3<Float>] = []
        private var renderedModelURL: String?
        private var renderedCameraResetToken = 0
        private var renderedAutoAlignToken = 0
        private var renderedCameraPreset: ImgTo3DCameraPreset = .perspective
        private var renderedColorScheme: ColorScheme?
        private var reportedWorldSize: ImgTo3DModelSize?
        private var panStart = ImgTo3DModelTransform.initial
        private var panLatest = ImgTo3DModelTransform.initial

        init(parent: ImgTo3DModelViewer) {
            self.parent = parent
        }

        var retainedModelNodeCountForTesting: Int {
            modelContainer.childNodes.count
        }

        var cachedModelSampleCountForTesting: Int {
            modelLocalSamples.count
        }

        func makeScene() -> SCNScene {
            let scene = SCNScene()
            scene.rootNode.addChildNode(makeFloor())
            scene.rootNode.addChildNode(makeGrid())
            scene.rootNode.addChildNode(modelContainer)
            scene.rootNode.addChildNode(gizmoNode)
            buildTransformGizmo()
            installPlaceholder()

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 500
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 1_000
            key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
            scene.rootNode.addChildNode(key)

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.zNear = 0.01
            cameraNode.camera?.zFar = 100
            cameraNode.position = SCNVector3(2.4, 1.8, 2.8)
            aimCameraAtTarget()
            scene.rootNode.addChildNode(cameraNode)
            return scene
        }

        /// SwiftUI가 보정 뷰를 제거할 때 SCNView와 Coordinator 양쪽의 강한 참조를 끊습니다.
        /// scene만 nil로 바꾸면 Coordinator가 모델 컨테이너·지오메트리·정점 샘플을 계속 보관합니다.
        func releaseSceneResources(from view: SCNView) {
            view.isPlaying = false
            view.rendersContinuously = false
            view.allowsCameraControl = false
            view.defaultCameraController.inertiaEnabled = false
            view.delegate = nil

            if let adjustmentPan {
                adjustmentPan.isEnabled = false
                view.removeGestureRecognizer(adjustmentPan)
                self.adjustmentPan = nil
            }

            view.pointOfView = nil
            if let rootNode = view.scene?.rootNode {
                discardResources(in: rootNode)
            }
            view.scene = nil
            sceneView = nil

            modelContainer.childNodes.forEach { $0.removeFromParentNode() }
            gizmoNode.childNodes.forEach { $0.removeFromParentNode() }
            cameraNode.removeFromParentNode()
            cameraNode.camera = nil
            modelLocalBounds = nil
            modelLocalSamples.removeAll(keepingCapacity: false)
            renderedModelURL = nil
            renderedCameraResetToken = 0
            renderedAutoAlignToken = 0
            renderedCameraPreset = .perspective
            renderedColorScheme = nil
            reportedWorldSize = nil
            panStart = .initial
            panLatest = .initial
        }

        /// 모델 텍스처가 SCNMaterialProperty.contents를 통해 남지 않도록 씬 계층을 재귀 정리합니다.
        private func discardResources(in node: SCNNode) {
            node.removeAllActions()
            node.animationKeys.forEach { node.removeAnimation(forKey: $0) }
            node.childNodes.forEach { discardResources(in: $0) }
            node.geometry?.materials.forEach { material in
                material.diffuse.contents = nil
                material.ambient.contents = nil
                material.specular.contents = nil
                material.emission.contents = nil
                material.transparent.contents = nil
                material.reflective.contents = nil
                material.multiply.contents = nil
                material.normal.contents = nil
                material.displacement.contents = nil
                material.metalness.contents = nil
                material.roughness.contents = nil
                material.ambientOcclusion.contents = nil
            }
            node.geometry = nil
            node.light = nil
            node.camera = nil
            node.childNodes.forEach { $0.removeFromParentNode() }
        }

        func apply(transform: ImgTo3DModelTransform, floorSnap: Bool) {
            modelContainer.eulerAngles = SCNVector3(
                Float(transform.xDegrees * .pi / 180),
                Float(transform.yDegrees * .pi / 180),
                Float(transform.zDegrees * .pi / 180)
            )
            modelContainer.position = SCNVector3(
                Float(transform.xPosition),
                floorSnap ? 0 : Float(transform.yPosition),
                Float(transform.zPosition)
            )
            let scale = Float(transform.scale)
            modelContainer.scale = SCNVector3(scale, scale, scale)

            // 모델 중심은 로드 시점(회전 전) 기준이라 회전하면 어긋난다.
            // 현재 회전·스케일이 반영된 월드 AABB로 수평 중심을 유지한다.
            if let bounds = worldModelBounds() {
                modelContainer.position.x += Float(transform.xPosition) - (bounds.min.x + bounds.max.x) / 2
                modelContainer.position.z += Float(transform.zPosition) - (bounds.min.z + bounds.max.z) / 2
            }
            // 메시의 고립된 노이즈 정점 때문에 가구가 떠 보이지 않도록 최저점 대신 하위 1%를 접지한다.
            if floorSnap, let floorY = sampledWorldYPercentile(0.01) {
                modelContainer.position.y -= floorY
            }
            gizmoNode.position = modelContainer.position
            reportWorldSizeIfNeeded()
        }

        func updateGizmo(mode: ImgTo3DViewerMode, axis: ImgTo3DTransformAxis) {
            gizmoNode.isHidden = mode == .orbit
            for child in gizmoNode.childNodes {
                guard let name = child.name else { continue }
                child.opacity = axis == .free || axis.rawValue == name ? 1 : 0.22
            }
        }

        func resetCameraIfNeeded(token: Int, preset: ImgTo3DCameraPreset) {
            guard token != renderedCameraResetToken || preset != renderedCameraPreset else { return }
            renderedCameraResetToken = token
            renderedCameraPreset = preset
            // 카메라 컨트롤이 pointOfView를 바꿔놨어도 초기화가 항상 원래 카메라로 복구되도록.
            sceneView?.pointOfView = cameraNode
            switch preset {
            case .perspective: cameraNode.position = SCNVector3(2.4, 1.8, 2.8)
            case .front: cameraNode.position = SCNVector3(0, 0.8, 3.4)
            case .side: cameraNode.position = SCNVector3(3.4, 0.8, 0)
            case .top: cameraNode.position = SCNVector3(0, 4, 0.001)
            }
            aimCameraAtTarget()
            sceneView?.defaultCameraController.target = SCNVector3(0, 0.45, 0)
        }

        /// look(at:)은 현재 방향에서 최단 회전만 해서 기존 기울기(roll)를 그대로 유지한다.
        /// up 벡터를 명시해 시점 프리셋·초기화가 항상 수평이 맞는 화면으로 복구되게 한다.
        private func aimCameraAtTarget() {
            cameraNode.look(at: SCNVector3(0, 0.45, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }

        func loadModelIfNeeded(from url: URL?) {
            let key = url?.standardizedFileURL.path
            guard key != renderedModelURL else { return }
            renderedModelURL = key

            guard let url else {
                installPlaceholder()
                reportModelLoaded(size: .init(), name: nil)
                return
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let signposter = PerformanceSignposts.imgTo3D
                let parseInterval = signposter.beginInterval("imgTo3D.model.parse", id: signposter.makeSignpostID())
                defer { signposter.endInterval("imgTo3D.model.parse", parseInterval) }
                let asset = try GLTFAsset(url: url, options: [:])
                let scene = SCNScene(gltfAsset: asset)
                let root = SCNNode()
                scene.rootNode.childNodes.forEach { root.addChildNode($0.clone()) }
                guard let bounds = hierarchyBounds(of: root, relativeTo: root) else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                let rawSize = SCNVector3(
                    bounds.max.x - bounds.min.x,
                    bounds.max.y - bounds.min.y,
                    bounds.max.z - bounds.min.z
                )
                let maxDimension = max(rawSize.x, rawSize.y, rawSize.z)
                let fitScale: Float = maxDimension > 0 ? 1.2 / maxDimension : 1
                let centerX = (bounds.min.x + bounds.max.x) / 2
                let centerZ = (bounds.min.z + bounds.max.z) / 2
                root.position = SCNVector3(-centerX, -bounds.min.y, -centerZ)
                root.scale = SCNVector3(fitScale, fitScale, fitScale)

                replaceModel(with: root)
                reportModelLoaded(
                    size: .init(
                        width: Double(rawSize.x * fitScale),
                        height: Double(rawSize.y * fitScale),
                        depth: Double(rawSize.z * fitScale)
                    ),
                    name: url.lastPathComponent
                )
            } catch {
                installPlaceholder()
                reportModelLoaded(size: .init(), name: nil)
            }
        }

        /// 웹 뷰어와 같은 정점 기반 자동 정렬을 한 번 실행합니다.
        /// 현재 yaw/scale이 포함된 방향에서 X/Z 보정 회전을 앞에 곱해 AABB 부피를 최소화합니다.
        func autoAlignIfNeeded(token: Int, transform: ImgTo3DModelTransform) {
            guard token != renderedAutoAlignToken, !modelLocalSamples.isEmpty else { return }
            renderedAutoAlignToken = token

            let signposter = PerformanceSignposts.imgTo3D
            let alignInterval = signposter.beginInterval("imgTo3D.autoAlign", id: signposter.makeSignpostID())
            defer { signposter.endInterval("imgTo3D.autoAlign", alignInterval) }

            let scale = Float(transform.scale)
            let currentOrientation = modelContainer.simdOrientation
            let oriented = modelLocalSamples.map { currentOrientation.act($0 * scale) }

            func correctionQuaternion(xDegrees: Int, zDegrees: Int) -> simd_quatf {
                let node = SCNNode()
                node.eulerAngles = SCNVector3(
                    Float(xDegrees) * .pi / 180,
                    0,
                    Float(zDegrees) * .pi / 180
                )
                return node.simdOrientation
            }

            func volume(after correction: simd_quatf) -> Float {
                var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                for point in oriented {
                    let value = correction.act(point)
                    lower = simd_min(lower, value)
                    upper = simd_max(upper, value)
                }
                let size = upper - lower
                return size.x * size.y * size.z
            }

            var bestX = 0
            var bestZ = 0
            var bestVolume = volume(after: correctionQuaternion(xDegrees: 0, zDegrees: 0))

            func search(centerX: Int, centerZ: Int, range: Int, step: Int) {
                for x in stride(from: centerX - range, through: centerX + range, by: step) {
                    for z in stride(from: centerZ - range, through: centerZ + range, by: step) {
                        let candidate = correctionQuaternion(xDegrees: x, zDegrees: z)
                        let candidateVolume = volume(after: candidate)
                        if candidateVolume < bestVolume {
                            bestX = x
                            bestZ = z
                            bestVolume = candidateVolume
                        }
                    }
                }
            }

            // 웹과 동일한 코스(5°) → 파인(1°) 2단계 탐색.
            search(centerX: 0, centerZ: 0, range: 25, step: 5)
            search(centerX: bestX, centerZ: bestZ, range: 4, step: 1)

            let correction = correctionQuaternion(xDegrees: bestX, zDegrees: bestZ)
            let alignedOrientation = correction * currentOrientation
            let alignedPoints = modelLocalSamples.map { alignedOrientation.act($0 * scale) }
            guard let alignment = alignmentMetrics(for: alignedPoints) else { return }

            let eulerNode = SCNNode()
            eulerNode.simdOrientation = alignedOrientation
            let euler = eulerNode.eulerAngles

            var aligned = transform
            aligned.xDegrees = Double(euler.x * 180 / .pi)
            aligned.yDegrees = Double(euler.y * 180 / .pi)
            aligned.zDegrees = Double(euler.z * 180 / .pi)
            // apply(transform:)이 AABB 중심을 transform.x/z로 맞추므로, 그 보정을 고려해
            // 최종 바닥 발자국 중심이 월드 원점에 오도록 목표 중심을 역산한다.
            aligned.xPosition = Double(alignment.boundsCenter.x - alignment.footprintCenter.x)
            aligned.yPosition = 0
            aligned.zPosition = Double(alignment.boundsCenter.y - alignment.footprintCenter.y)

            Task { @MainActor [weak self] in
                await Task.yield()
                self?.parent.onAutoAlignment(aligned)
            }
        }

        func updateAppearance(colorScheme: ColorScheme) {
            guard renderedColorScheme != colorScheme else { return }
            renderedColorScheme = colorScheme
            let isDark = colorScheme == .dark
            sceneView?.backgroundColor = UIColor(hexString: isDark ? "#212A2B" : "#F2EEE6")
            sceneView?.scene?.rootNode.enumerateChildNodes { node, _ in
                node.geometry?.materials.forEach { material in
                    switch material.name {
                    case "imgTo3DFloor":
                        material.diffuse.contents = UIColor(hexString: isDark ? "#2A3436" : "#F2EDE6")
                    case "imgTo3DGridMinor":
                        material.diffuse.contents = isDark
                            ? UIColor(hexString: "#93A19D").withAlphaComponent(0.22)
                            : UIColor(red: 0.60, green: 0.48, blue: 0.36, alpha: 0.20)
                    case "imgTo3DGridMajor":
                        material.diffuse.contents = isDark
                            ? UIColor(hexString: "#93A19D").withAlphaComponent(0.42)
                            : UIColor(red: 0.52, green: 0.40, blue: 0.28, alpha: 0.40)
                    case "imgTo3DOrigin":
                        material.diffuse.contents = UIColor(hexString: isDark ? "#F3EDE3" : "#5C3D2E")
                    default:
                        break
                    }
                }
            }
        }

        /// `updateUIView` 도중 SwiftUI 상태를 즉시 바꾸지 않도록 다음 메인 액터 턴에 결과를 전달합니다.
        private func reportModelLoaded(size: ImgTo3DModelSize, name: String?) {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.parent.onModelLoaded(size, name)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = sceneView else { return }
            switch gesture.state {
            case .began:
                parent.onInteractionBegan()
                panStart = parent.transform
                panLatest = parent.transform
                Haptics.selection()
            case .changed:
                let translation = gesture.translation(in: view)
                var next = panStart
                switch parent.mode {
                case .orbit:
                    return
                case .move:
                    // 현재 카메라의 화면 오른쪽/앞쪽 벡터를 바닥면에 투영해,
                    // 카메라를 돌린 뒤에도 손가락이 움직인 화면 방향 그대로 모델이 따라가게 합니다.
                    let camera = cameraNode.presentation.worldTransform
                    var rightX = Double(camera.m11)
                    var rightZ = Double(camera.m13)
                    var forwardX = Double(-camera.m31)
                    var forwardZ = Double(-camera.m33)
                    let rightLength = max(0.001, hypot(rightX, rightZ))
                    let forwardLength = max(0.001, hypot(forwardX, forwardZ))
                    rightX /= rightLength
                    rightZ /= rightLength
                    forwardX /= forwardLength
                    forwardZ /= forwardLength
                    let horizontal = Double(translation.x / 180)
                    let vertical = Double(translation.y / 180)
                    switch parent.activeAxis {
                    case .free:
                        next.xPosition += horizontal * rightX + vertical * forwardX
                        next.zPosition += horizontal * rightZ + vertical * forwardZ
                    case .x:
                        next.xPosition += horizontal
                    case .y:
                        next.yPosition = max(0, panStart.yPosition - vertical)
                    case .z:
                        next.zPosition += vertical
                    }
                case .rotate:
                    let amount = Double(translation.x - translation.y) * 0.45
                    switch parent.activeAxis {
                    case .free:
                        next.yDegrees += Double(translation.x) * 0.55
                        next.xDegrees -= Double(translation.y) * 0.25
                    case .x: next.xDegrees += amount
                    case .y: next.yDegrees += amount
                    case .z: next.zDegrees += amount
                    }
                case .scale:
                    next.scale = min(2, max(0.5, panStart.scale - Double(translation.y / 220)))
                }
                panLatest = next
                parent.transform = next
            case .ended:
                var snapped = panLatest
                switch parent.mode {
                case .orbit: return
                case .move:
                    snapped.xPosition = snapped.xPosition.snapped(to: 0.1)
                    snapped.yPosition = snapped.yPosition.snapped(to: 0.1)
                    snapped.zPosition = snapped.zPosition.snapped(to: 0.1)
                case .rotate:
                    snapped.xDegrees = snapped.xDegrees.snapped(to: 15)
                    snapped.yDegrees = snapped.yDegrees.snapped(to: 15)
                    snapped.zDegrees = snapped.zDegrees.snapped(to: 15)
                case .scale:
                    snapped.scale = snapped.scale.snapped(to: 0.05)
                }
                parent.transform = snapped
                Haptics.selection()
            default:
                break
            }
        }

        private func installPlaceholder() {
            let geometry = SCNBox(width: 1, height: 0.8, length: 0.6, chamferRadius: 0.04)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.77, green: 0.58, blue: 0.42, alpha: 1)
            material.roughness.contents = 0.55
            geometry.materials = [material]
            let box = SCNNode(geometry: geometry)
            box.position.y = 0.4
            replaceModel(with: box)
        }

        private func buildTransformGizmo() {
            gizmoNode.addChildNode(axisGuide(axis: "X", color: .systemRed))
            gizmoNode.addChildNode(axisGuide(axis: "Y", color: .systemGreen))
            gizmoNode.addChildNode(axisGuide(axis: "Z", color: .systemBlue))
            let center = SCNSphere(radius: 0.035)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.readsFromDepthBuffer = false
            center.materials = [material]
            let centerNode = SCNNode(geometry: center)
            centerNode.renderingOrder = 100
            gizmoNode.addChildNode(centerNode)
        }

        private func axisGuide(axis: String, color: UIColor) -> SCNNode {
            let root = SCNNode()
            root.name = axis
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.35)
            material.readsFromDepthBuffer = false

            let shaft = SCNCylinder(radius: 0.012, height: 0.52)
            shaft.materials = [material]
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position.y = 0.26

            let tip = SCNCone(topRadius: 0, bottomRadius: 0.045, height: 0.12)
            tip.materials = [material]
            let tipNode = SCNNode(geometry: tip)
            tipNode.position.y = 0.58

            root.addChildNode(shaftNode)
            root.addChildNode(tipNode)
            root.renderingOrder = 100
            switch axis {
            case "X": root.eulerAngles.z = -Float.pi / 2
            case "Z": root.eulerAngles.x = Float.pi / 2
            default: break
            }
            return root
        }

        private func replaceModel(with node: SCNNode) {
            modelContainer.childNodes.forEach { $0.removeFromParentNode() }
            modelContainer.addChildNode(node)
            modelLocalBounds = hierarchyBounds(of: modelContainer, relativeTo: modelContainer)
            modelLocalSamples = collectLocalSamples(of: modelContainer)
            reportedWorldSize = nil
        }

        private func sampledWorldYPercentile(_ percentile: Float) -> Float? {
            guard !modelLocalSamples.isEmpty else { return nil }
            let matrix = modelContainer.simdWorldTransform
            let ys = modelLocalSamples.map { point -> Float in
                let world = matrix * SIMD4<Float>(point, 1)
                return world.y
            }.sorted()
            let index = min(ys.count - 1, max(0, Int(Float(ys.count) * percentile)))
            return ys[index]
        }

        private func alignmentMetrics(for points: [SIMD3<Float>]) -> (
            boundsCenter: SIMD2<Float>, footprintCenter: SIMD2<Float>
        )? {
            guard !points.isEmpty else { return nil }
            var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for point in points {
                lower = simd_min(lower, point)
                upper = simd_max(upper, point)
            }
            let bandTop = lower.y + (upper.y - lower.y) * 0.05
            var footprintSum = SIMD2<Float>(repeating: 0)
            var footprintCount: Float = 0
            for point in points where point.y <= bandTop {
                footprintSum += SIMD2(point.x, point.z)
                footprintCount += 1
            }
            guard footprintCount > 0 else { return nil }
            return (
                SIMD2((lower.x + upper.x) / 2, (lower.z + upper.z) / 2),
                footprintSum / footprintCount
            )
        }

        private func reportWorldSizeIfNeeded() {
            guard let bounds = worldModelBounds() else { return }
            let size = ImgTo3DModelSize(
                width: Double(bounds.max.x - bounds.min.x),
                height: Double(bounds.max.y - bounds.min.y),
                depth: Double(bounds.max.z - bounds.min.z)
            )
            guard reportedWorldSize != size else { return }
            reportedWorldSize = size
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.parent.onModelBoundsChanged(size)
            }
        }

        /// 지오메트리별 정점 버퍼를 최대 2,000개까지 균일 샘플링한 뒤 컨테이너 로컬 좌표로 변환합니다.
        private func collectLocalSamples(of root: SCNNode) -> [SIMD3<Float>] {
            var sources: [(node: SCNNode, source: SCNGeometrySource)] = []
            var totalVertices = 0
            root.enumerateChildNodes { node, _ in
                guard let source = node.geometry?.sources(for: .vertex).first else { return }
                sources.append((node, source))
                totalVertices += source.vectorCount
            }
            guard totalVertices > 0 else { return [] }
            let sampleStride = max(1, Int(ceil(Double(totalVertices) / 2_000)))
            var samples: [SIMD3<Float>] = []
            samples.reserveCapacity(min(totalVertices, 2_000 + sources.count))

            for item in sources {
                let source = item.source
                guard source.usesFloatComponents,
                      source.componentsPerVector >= 3,
                      source.bytesPerComponent == MemoryLayout<Float>.size else { continue }
                source.data.withUnsafeBytes { rawBuffer in
                    for index in Swift.stride(from: 0, to: source.vectorCount, by: sampleStride) {
                        let base = source.dataOffset + index * source.dataStride
                        guard base + source.bytesPerComponent * 3 <= rawBuffer.count else { continue }
                        let x = rawBuffer.loadUnaligned(fromByteOffset: base, as: Float.self)
                        let y = rawBuffer.loadUnaligned(fromByteOffset: base + source.bytesPerComponent, as: Float.self)
                        let z = rawBuffer.loadUnaligned(fromByteOffset: base + source.bytesPerComponent * 2, as: Float.self)
                        let point = item.node.convertPosition(SCNVector3(x, y, z), to: modelContainer)
                        samples.append(SIMD3(point.x, point.y, point.z))
                    }
                }
            }
            return samples
        }

        /// 캐시한 로컬 AABB의 8개 꼭짓점을 현재 컨테이너 변환(회전·스케일·위치)으로 월드에 투영한 AABB.
        private func worldModelBounds() -> (min: SCNVector3, max: SCNVector3)? {
            guard let local = modelLocalBounds else { return nil }
            var lower = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var upper = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
            for x in [local.min.x, local.max.x] {
                for y in [local.min.y, local.max.y] {
                    for z in [local.min.z, local.max.z] {
                        let point = modelContainer.convertPosition(SCNVector3(x, y, z), to: nil)
                        lower.x = min(lower.x, point.x)
                        lower.y = min(lower.y, point.y)
                        lower.z = min(lower.z, point.z)
                        upper.x = max(upper.x, point.x)
                        upper.y = max(upper.y, point.y)
                        upper.z = max(upper.z, point.z)
                    }
                }
            }
            return (lower, upper)
        }

        private func makeFloor() -> SCNNode {
            // SCNFloor는 반사 패스를 항상 구성해 reflectivity 0이면
            // "Pass FloorPass is not linked to the rendering graph" 콘솔 경고를 남긴다.
            // 반사를 쓰지 않으므로 넓은 평면으로 대체한다. (경고 제거 + 렌더 비용 절감)
            let plane = SCNPlane(width: 80, height: 80)
            let material = SCNMaterial()
            material.name = "imgTo3DFloor"
            material.diffuse.contents = UIColor { traits in
                UIColor(hexString: traits.userInterfaceStyle == .dark ? "#2A3436" : "#F2EDE6")
            }
            material.roughness.contents = 1
            material.isDoubleSided = true
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -Float.pi / 2
            return node
        }

        private func makeGrid() -> SCNNode {
            let node = SCNNode()
            // 고정 브라운 톤은 다크 모드 바닥(#2A3436) 위에서 거의 보이지 않아 모드별로 나눈다.
            // 1m 주요선은 진하게, 0.5m 보조선은 연하게 구분해 바닥 스케일이 읽히게 한다.
            let minor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hexString: "#93A19D").withAlphaComponent(0.22)
                    : UIColor(red: 0.60, green: 0.48, blue: 0.36, alpha: 0.20)
            }
            let major = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hexString: "#93A19D").withAlphaComponent(0.42)
                    : UIColor(red: 0.52, green: 0.40, blue: 0.28, alpha: 0.40)
            }
            let halfExtent: Float = 8
            for index in -16...16 where index != 0 {
                let value = Float(index) * 0.5
                let color = index.isMultiple(of: 2) ? major : minor
                let materialName = index.isMultiple(of: 2) ? "imgTo3DGridMajor" : "imgTo3DGridMinor"
                node.addChildNode(line(from: SCNVector3(value, 0.002, -halfExtent), to: SCNVector3(value, 0.002, halfExtent), color: color, materialName: materialName))
                node.addChildNode(line(from: SCNVector3(-halfExtent, 0.002, value), to: SCNVector3(halfExtent, 0.002, value), color: color, materialName: materialName))
            }

            // 원점(0,0,0)이 어디인지 보이도록: X축(빨강)·Z축(파랑) 중심선 + 원점 마커.
            node.addChildNode(axisFloorLine(alongX: true, length: halfExtent * 2, color: UIColor.systemRed.withAlphaComponent(0.55)))
            node.addChildNode(axisFloorLine(alongX: false, length: halfExtent * 2, color: UIColor.systemBlue.withAlphaComponent(0.55)))
            node.addChildNode(originMarker())
            return node
        }

        /// 바닥 위 원점을 지나는 축 표시선. 1px 라인보다 잘 보이도록 얇은 박스로 그린다.
        private func axisFloorLine(alongX: Bool, length: Float, color: UIColor) -> SCNNode {
            let box = SCNBox(
                width: alongX ? CGFloat(length) : 0.012,
                height: 0.002,
                length: alongX ? 0.012 : CGFloat(length),
                chamferRadius: 0
            )
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .constant
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(0, 0.003, 0)
            return node
        }

        private func originMarker() -> SCNNode {
            let disc = SCNCylinder(radius: 0.045, height: 0.006)
            let material = SCNMaterial()
            material.name = "imgTo3DOrigin"
            material.diffuse.contents = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hexString: "#F3EDE3")
                    : UIColor(hexString: "#5C3D2E")
            }
            material.lightingModel = .constant
            disc.materials = [material]
            let node = SCNNode(geometry: disc)
            node.position = SCNVector3(0, 0.004, 0)
            return node
        }

        private func line(
            from start: SCNVector3,
            to end: SCNVector3,
            color: UIColor,
            materialName: String? = nil
        ) -> SCNNode {
            let source = SCNGeometrySource(vertices: [start, end])
            let data = Data([0, 1])
            let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: 1)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.name = materialName
            material.diffuse.contents = color
            // 라인은 법선이 없어 조명을 받으면 검게 묻힌다. 지정한 색 그대로 그리도록 조명을 끈다.
            material.lightingModel = .constant
            geometry.materials = [material]
            return SCNNode(geometry: geometry)
        }

        /// root 하위 지오메트리들의 AABB를 frame 좌표계 기준으로 계산합니다. frame이 nil이면 월드 좌표계.
        private func hierarchyBounds(of root: SCNNode, relativeTo frame: SCNNode?) -> (min: SCNVector3, max: SCNVector3)? {
            var lower = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var upper = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
            var found = false

            root.enumerateChildNodes { node, _ in
                guard node.geometry != nil else { return }
                let (minimum, maximum) = node.boundingBox
                let corners = [
                    SCNVector3(minimum.x, minimum.y, minimum.z), SCNVector3(maximum.x, minimum.y, minimum.z),
                    SCNVector3(minimum.x, maximum.y, minimum.z), SCNVector3(maximum.x, maximum.y, minimum.z),
                    SCNVector3(minimum.x, minimum.y, maximum.z), SCNVector3(maximum.x, minimum.y, maximum.z),
                    SCNVector3(minimum.x, maximum.y, maximum.z), SCNVector3(maximum.x, maximum.y, maximum.z)
                ]
                for corner in corners {
                    let point = node.convertPosition(corner, to: frame)
                    lower.x = min(lower.x, point.x)
                    lower.y = min(lower.y, point.y)
                    lower.z = min(lower.z, point.z)
                    upper.x = max(upper.x, point.x)
                    upper.y = max(upper.y, point.y)
                    upper.z = max(upper.z, point.z)
                    found = true
                }
            }
            return found ? (lower, upper) : nil
        }
    }
}

private extension Double {
    func snapped(to increment: Double) -> Double {
        (self / increment).rounded() * increment
    }
}
