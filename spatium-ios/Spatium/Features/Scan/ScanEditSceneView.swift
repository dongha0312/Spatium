import SceneKit
import SwiftUI

/// 스캔 편집기의 SceneKit 표면. 스캔된 방 메시(USDZ)를 그대로 배경으로 깔고,
/// 감지된 객체들을 반투명 컬러 박스로 겹쳐 그립니다.
/// 아무것도 선택하지 않았을 때는 카메라 궤도 조작, 객체 선택 시에는 드래그 이동으로 전환됩니다.
struct ScanEditSceneView: UIViewRepresentable {
    @Binding var items: [EditableScanItem]
    @Binding var selectedItemID: UUID?
    var sceneRevision: Int
    var usdzURL: URL?

    private let modelLoader: FurnitureModelLoader = TestDataFurnitureModelLoader()

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor { traits in
            UIColor(hexString: traits.userInterfaceStyle == .dark ? "#2A3436" : "#F2EEE6")
        }
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.buildScene(items: items, usdzURL: usdzURL)
        view.allowsCameraControl = true
        view.pointOfView = context.coordinator.cameraNode

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
        context.coordinator.movePanGesture = pan
        context.coordinator.sceneView = view

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.renderedRevision != sceneRevision {
            coordinator.rebuildItemNodes(items: items)
            coordinator.renderedRevision = sceneRevision
        }

        coordinator.applySelection(itemID: selectedItemID)
        let hasSelection = selectedItemID != nil
        view.allowsCameraControl = !hasSelection
        coordinator.movePanGesture?.isEnabled = hasSelection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, modelLoader: modelLoader)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScanEditSceneView
        let modelLoader: FurnitureModelLoader

        weak var sceneView: SCNView?
        var movePanGesture: UIPanGestureRecognizer?
        var renderedRevision = 0

        let cameraNode = SCNNode()
        private let itemsContainer = SCNNode()

        init(parent: ScanEditSceneView, modelLoader: FurnitureModelLoader) {
            self.parent = parent
            self.modelLoader = modelLoader
        }

        // MARK: - Scene 구성

        func buildScene(items: [EditableScanItem], usdzURL: URL?) -> SCNScene {
            let scene = SCNScene()

            // PBR(GLTFKit2) 재질이 납작하게/검게 나오지 않도록 이미지 기반 조명 환경을 깝니다.
            scene.lightingEnvironment.contents = UIColor(white: 0.85, alpha: 1)
            scene.lightingEnvironment.intensity = 1.2

            // 스캔된 방 메시에서 벽/바닥(Arch_grp)만 배경으로 남기고,
            // RoomPlan이 만든 가구 박스(Object_grp)는 제거합니다. 가구는 아래에서 실물 GLB로 대체합니다.
            if let usdzURL, let roomScene = try? SCNScene(url: usdzURL) {
                let shell = SCNNode()
                shell.name = "room-shell"
                for child in roomScene.rootNode.childNodes {
                    shell.addChildNode(child)
                }
                while let furnitureGroup = shell.childNode(withName: "Object_grp", recursively: true) {
                    furnitureGroup.removeFromParentNode()
                }
                scene.rootNode.addChildNode(shell)
            }

            // 드래그 이동의 기준면 (거의 투명한 대형 바닥판).
            let dragFloor = SCNBox(width: 40, height: 0.01, length: 40, chamferRadius: 0)
            let floorMaterial = SCNMaterial()
            floorMaterial.diffuse.contents = UIColor(white: 0.8, alpha: 1)
            floorMaterial.transparency = 0.02
            dragFloor.materials = [floorMaterial]
            let floorNode = SCNNode(geometry: dragFloor)
            floorNode.name = "floor"
            floorNode.position = SCNVector3(0, -0.005, 0)
            scene.rootNode.addChildNode(floorNode)

            scene.rootNode.addChildNode(itemsContainer)
            rebuildItemNodes(items: items)

            let camera = SCNCamera()
            camera.zFar = 300
            cameraNode.camera = camera
            let extent = Self.horizontalExtent(of: items)
            cameraNode.position = SCNVector3(extent * 0.9, extent * 0.85, extent * 1.25)
            cameraNode.look(at: SCNVector3(0, 0.5, 0))
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 600
            scene.rootNode.addChildNode(ambient)

            let directional = SCNNode()
            directional.light = SCNLight()
            directional.light?.type = .directional
            directional.light?.intensity = 650
            directional.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
            scene.rootNode.addChildNode(directional)

            return scene
        }

        func rebuildItemNodes(items: [EditableScanItem]) {
            itemsContainer.childNodes.forEach { $0.removeFromParentNode() }
            for item in items {
                itemsContainer.addChildNode(modelLoader.makeNode(for: item))
            }
            applySelection(itemID: parent.selectedItemID)
        }

        private static func horizontalExtent(of items: [EditableScanItem]) -> Float {
            let maxDistance = items
                .map { Float(max(abs($0.positionX), abs($0.positionZ))) }
                .max() ?? 0
            return max(maxDistance * 2 + 1.5, 4)
        }

        func applySelection(itemID: UUID?) {
            let selectedName = itemID.map { "scanitem-\($0.uuidString)" }
            for node in itemsContainer.childNodes {
                let isSelected = node.name == selectedName
                Self.setEmission(
                    on: node,
                    color: isSelected ? UIColor(red: 0.77, green: 0.58, blue: 0.42, alpha: 0.6) : .black
                )
            }
        }

        // MARK: - 제스처

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let point = gesture.location(in: sceneView)
            let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

            for hit in hits {
                if let itemID = Self.itemID(fromNodeOrAncestors: hit.node) {
                    if parent.selectedItemID != itemID { Haptics.selection() }
                    parent.selectedItemID = itemID
                    return
                }
            }
            parent.selectedItemID = nil
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView,
                  let selectedID = parent.selectedItemID,
                  let node = itemsContainer.childNode(withName: "scanitem-\(selectedID.uuidString)", recursively: false) else { return }

            let point = gesture.location(in: sceneView)
            let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            guard let floorHit = hits.first(where: { $0.node.name == "floor" }) else { return }

            let limit: Float = 19
            let x = min(max(floorHit.worldCoordinates.x, -limit), limit)
            let z = min(max(floorHit.worldCoordinates.z, -limit), limit)
            node.position.x = x
            node.position.z = z

            if gesture.state == .ended || gesture.state == .cancelled {
                guard let index = parent.items.firstIndex(where: { $0.id == selectedID }) else { return }
                parent.items[index].positionX = Double(x)
                parent.items[index].positionZ = Double(z)
            }
        }

        private static func itemID(fromNodeOrAncestors node: SCNNode) -> UUID? {
            var current: SCNNode? = node
            while let candidate = current {
                if let name = candidate.name, name.hasPrefix("scanitem-") {
                    return UUID(uuidString: String(name.dropFirst("scanitem-".count)))
                }
                current = candidate.parent
            }
            return nil
        }

        private static func setEmission(on node: SCNNode, color: UIColor) {
            node.geometry?.materials.forEach { $0.emission.contents = color }
            for child in node.childNodes {
                setEmission(on: child, color: color)
            }
        }
    }
}
