import Foundation
import GLTFKit2
import SceneKit
import simd

protocol FurnitureModelLoader {
    func makeNode(for furniture: PlacedFurniture) -> SCNNode
    func makeNode(for item: EditableScanItem) -> SCNNode
}

struct TestDataFurnitureModelLoader: FurnitureModelLoader {
    private static let palette: [UIColor] = [
        UIColor(red: 0.77, green: 0.58, blue: 0.42, alpha: 1),
        UIColor(red: 0.55, green: 0.41, blue: 0.25, alpha: 1),
        UIColor(red: 0.48, green: 0.62, blue: 0.76, alpha: 1),
        UIColor(red: 0.36, green: 0.24, blue: 0.18, alpha: 1)
    ]

    func makeNode(for furniture: PlacedFurniture) -> SCNNode {
        let width = furniture.width ?? 0.8
        let height = furniture.height ?? 0.8
        let depth = furniture.depth ?? 0.8
        let node = makeRenderableNode(
            identifier: "furniture-\(furniture.itemId)",
            name: furniture.furnitureName,
            category: furniture.furnitureName,
            width: width,
            height: height,
            depth: depth,
            paletteIndex: furniture.furnitureId,
            preferredModel: furniture.modelName
        )
        node.position = SCNVector3(furniture.position.x, furniture.position.y, furniture.position.z)
        node.eulerAngles = SCNVector3(furniture.rotation.x, furniture.rotation.y, furniture.rotation.z)
        let fittedScale = node.scale
        node.scale = SCNVector3(
            fittedScale.x * Float(furniture.scale.x),
            fittedScale.y * Float(furniture.scale.y),
            fittedScale.z * Float(furniture.scale.z)
        )
        return node
    }

    func makeNode(for item: EditableScanItem) -> SCNNode {
        let node = makeRenderableNode(
            identifier: "scanitem-\(item.id.uuidString)",
            name: item.displayName,
            category: [item.detectedCategory, item.sourceType].joined(separator: " "),
            width: item.width,
            height: item.height,
            depth: item.depth,
            paletteIndex: item.displayName.hashValue,
            preferredModel: item.modelName
        )
        // RoomPlan 좌표(positionY)는 객체의 '중심' 높이인데 모델 pivot은 바닥이므로,
        // 절반 높이만큼 내려 바닥에 닿게 배치합니다. (그러지 않으면 공중에 떠 보임)
        node.position = SCNVector3(item.positionX, item.positionY - item.height / 2, item.positionZ)
        node.eulerAngles.y = Float(item.detectedRotationY + item.rotationY)
        return node
    }

    private func makeRenderableNode(
        identifier: String,
        name: String,
        category: String,
        width: Double,
        height: Double,
        depth: Double,
        paletteIndex: Int,
        preferredModel: String?
    ) -> SCNNode {
        // 사용자가 고른 모델이 있으면 그것을, 없으면 카테고리 기본 모델(default_3d_models)을 씁니다.
        let fileName = preferredModel ?? FurnitureCatalog.defaultModelName(matching: "\(name) \(category)")

        if let fileName,
           let modelURL = Bundle.main.url(forResource: fileName, withExtension: "glb"),
           let modelNode = loadModelNode(from: modelURL) {
            prepareModelNode(modelNode, identifier: identifier, width: width, height: height, depth: depth)
            return modelNode
        }

        return makePlaceholderNode(
            identifier: identifier,
            width: width,
            height: height,
            depth: depth,
            paletteIndex: paletteIndex
        )
    }

    /// 한 번 로드한 GLB는 노드 템플릿으로 캐시하고, 사용할 때 clone합니다.
    /// (GLTFKit2 파싱이 무거워, 씬 재생성마다 다시 로드하면 삭제/추가가 매우 느려짐)
    private static var nodeCache: [String: SCNNode] = [:]

    private func loadModelNode(from url: URL) -> SCNNode? {
        let key = url.path
        if let template = Self.nodeCache[key] {
            return template.clone()
        }
        if let asset = try? GLTFAsset(url: url, options: [:]) {
            let scene = SCNScene(gltfAsset: asset)
            if !scene.rootNode.childNodes.isEmpty {
                let container = containerNode(from: scene)
                Self.nodeCache[key] = container
                return container.clone()
            }
        }
        return nil
    }

    private func containerNode(from scene: SCNScene) -> SCNNode {
        let container = SCNNode()
        for child in scene.rootNode.childNodes {
            container.addChildNode(child.clone())
        }
        removeHelperGeometry(from: container)
        return container
    }

    /// 일부 GLB에는 실제 가구가 아닌 축/가이드/프리뷰 UI 메시가 같이 들어 있다.
    /// 이 노드들은 화면에 보이면 안 되고 bounding box도 왜곡하므로, 원본 노드명을 덮기 전에 제거한다.
    private func removeHelperGeometry(from node: SCNNode) {
        for child in node.childNodes {
            if shouldRemoveHelperBranch(child) {
                child.removeFromParentNode()
            } else {
                removeHelperGeometry(from: child)
            }
        }
    }

    private func shouldRemoveHelperBranch(_ node: SCNNode) -> Bool {
        if isHelperGeometryNode(node) { return true }
        // 예: ikea_desk.glb의 "Solid 25"는 실제 가구가 아니라 Sci-Fi UI 패널들의
        // 검은/회색 받침 메시다. 자식에 helper 마커가 있으면 이런 일반 컨테이너도 같이 제거한다.
        return containsHelperMarker(in: node) && isGenericHelperContainer(node)
    }

    private func isHelperGeometryNode(_ node: SCNNode) -> Bool {
        let name = (node.name ?? "").lowercased()
        let materialNames = (node.geometry?.materials ?? [])
            .compactMap { $0.name?.lowercased() }
            .joined(separator: " ")
        let text = "\(name) \(materialNames)"

        let helperKeywords = [
            "axis",
            "gizmo",
            "helper",
            "guide",
            "debug",
            "blueprint",
            "blender bros sci-fi ui pack"
        ]

        return helperKeywords.contains { text.contains($0) }
    }

    private func containsHelperMarker(in node: SCNNode) -> Bool {
        if isHelperGeometryNode(node) { return true }
        return node.childNodes.contains { containsHelperMarker(in: $0) }
    }

    private func isGenericHelperContainer(_ node: SCNNode) -> Bool {
        let name = (node.name ?? "").lowercased()
        let genericNames = ["solid", "panel", "screen", "display", "ui", "hologram"]
        return genericNames.contains { name.contains($0) }
    }

    private func prepareModelNode(_ node: SCNNode, identifier: String, width: Double, height: Double, depth: Double) {
        node.name = identifier
        setInteractionName(identifier, on: node)
        makeGeometryAndMaterialsUnique(on: node)

        let size = normalizeOriginAndReturnSize(node)
        // 두께가 0에 가까우면(문/창문 등) 모델이 납작해져 앞/뒷면이 z-fighting 하므로 최소 두께를 보장.
        let target = SCNVector3(max(width, 0.03), max(height, 0.03), max(depth, 0.03))
        let scale = modelScale(current: size, target: target)
        node.scale = scale
    }

    private func normalizeOriginAndReturnSize(_ node: SCNNode) -> SCNVector3 {
        // GLB는 geometry 없는 컨테이너 노드라 node.boundingBox / flattenedClone 모두
        // (0,0,0)을 돌려줄 수 있습니다. 자식 지오메트리들의 boundingBox를 각자 transform으로
        // 변환해 직접 합쳐 실제 크기를 구합니다.
        guard let (minBounds, maxBounds) = hierarchyBoundingBox(node) else {
            return SCNVector3(0, 0, 0)
        }
        let size = SCNVector3(
            maxBounds.x - minBounds.x,
            maxBounds.y - minBounds.y,
            maxBounds.z - minBounds.z
        )
        let centerX = (minBounds.x + maxBounds.x) / 2
        let centerZ = (minBounds.z + maxBounds.z) / 2
        node.pivot = SCNMatrix4MakeTranslation(centerX, minBounds.y, centerZ)
        return size
    }

    /// 노드 로컬 좌표계 기준으로 모든 하위 지오메트리를 감싸는 bounding box.
    /// (node 자신의 transform은 아직 설정 전이므로 제외하고 로컬 기준으로 계산합니다.)
    private func hierarchyBoundingBox(_ root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var found = false
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        func accumulate(_ node: SCNNode, _ parent: simd_float4x4) {
            let world = parent * node.simdTransform
            if node.geometry != nil {
                let (bMin, bMax) = node.boundingBox
                let corners: [SIMD4<Float>] = [
                    .init(bMin.x, bMin.y, bMin.z, 1), .init(bMax.x, bMin.y, bMin.z, 1),
                    .init(bMin.x, bMax.y, bMin.z, 1), .init(bMax.x, bMax.y, bMin.z, 1),
                    .init(bMin.x, bMin.y, bMax.z, 1), .init(bMax.x, bMin.y, bMax.z, 1),
                    .init(bMin.x, bMax.y, bMax.z, 1), .init(bMax.x, bMax.y, bMax.z, 1)
                ]
                for corner in corners {
                    let p = world * corner
                    lo = simd_min(lo, SIMD3(p.x, p.y, p.z))
                    hi = simd_max(hi, SIMD3(p.x, p.y, p.z))
                    found = true
                }
            }
            for child in node.childNodes {
                accumulate(child, world)
            }
        }

        // root 자신의 transform은 무시(로컬 기준)하고, 자식부터 누적.
        if root.geometry != nil {
            accumulate(root, matrix_identity_float4x4)
        } else {
            for child in root.childNodes {
                accumulate(child, matrix_identity_float4x4)
            }
        }

        guard found else { return nil }
        return (SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, hi.y, hi.z))
    }

    private func modelScale(current: SCNVector3, target: SCNVector3) -> SCNVector3 {
        SCNVector3(
            current.x > 0 ? max(target.x / current.x, 0.001) : 1,
            current.y > 0 ? max(target.y / current.y, 0.001) : 1,
            current.z > 0 ? max(target.z / current.z, 0.001) : 1
        )
    }

    private func setInteractionName(_ name: String, on node: SCNNode) {
        node.name = name
        for child in node.childNodes {
            setInteractionName(name, on: child)
        }
    }

    private func makeGeometryAndMaterialsUnique(on node: SCNNode) {
        if let geometry = node.geometry?.copy() as? SCNGeometry {
            geometry.materials = geometry.materials.map { material in
                (material.copy() as? SCNMaterial) ?? material
            }
            node.geometry = geometry
        }

        for child in node.childNodes {
            makeGeometryAndMaterialsUnique(on: child)
        }
    }

    private func makePlaceholderNode(
        identifier: String,
        width: Double,
        height: Double,
        depth: Double,
        paletteIndex: Int
    ) -> SCNNode {
        // 최소 두께 보장: 납작한 폴백 박스가 앞/뒷면 z-fighting을 일으키지 않게 함.
        let box = SCNBox(width: CGFloat(max(width, 0.03)), height: CGFloat(max(height, 0.03)), length: CGFloat(max(depth, 0.03)), chamferRadius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = Self.palette[Self.paletteIndex(from: paletteIndex)]
        material.locksAmbientWithDiffuse = true
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.name = identifier
        node.pivot = SCNMatrix4MakeTranslation(0, Float(-height / 2), 0)
        return node
    }

    private static func paletteIndex(from value: Int) -> Int {
        let magnitude = value == Int.min ? Int.max : abs(value)
        return magnitude % palette.count
    }
}

private extension SCNVector3 {
    init(_ x: Double, _ y: Double, _ z: Double) {
        self.init(Float(x), Float(y), Float(z))
    }
}
