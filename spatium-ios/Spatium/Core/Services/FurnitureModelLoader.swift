import Foundation
import GLTFKit2
import SceneKit
import simd

protocol FurnitureModelLoader {
    func makeNode(for furniture: PlacedFurniture) -> SCNNode
    func makeNode(for item: EditableScanItem) -> SCNNode
}

struct TestDataFurnitureModelLoader: FurnitureModelLoader {
    private struct ModelBounds {
        let min: SCNVector3
        let max: SCNVector3
    }

    private struct ModelTemplate {
        let node: SCNNode
        let bounds: ModelBounds?
    }

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
        // RoomPlan 좌표(positionY)는 객체의 중심 높이인데 모델 pivot은 바닥이므로,
        // 절반 높이만큼 내려 바닥에 닿게 배치합니다.
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
        let fileName = preferredModel ?? FurnitureCatalog.defaultModelName(matching: "\(name) \(category)")
        // 감지 카테고리가 모호해도 선택된 GLB 파일명이 door/window이면 참조 모델로 처리한다.
        let isReferenceModel = isDoorOrWindow("\(category) \(preferredModel ?? "")")

        if let fileName,
           let modelURL = Bundle.main.url(forResource: fileName, withExtension: "glb")
                ?? UserFurnitureStore.modelURL(for: fileName),
           let modelTemplate = loadModelTemplate(from: modelURL) {
            let modelNode = modelTemplate.node.clone()
            prepareModelNode(
                modelNode,
                identifier: identifier,
                width: width,
                height: height,
                depth: depth,
                templateBounds: modelTemplate.bounds,
                makesMaterialsIndependent: isReferenceModel
            )
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

    /// 프런트엔드의 `loadModelTemplates() → clone(true)`와 같은 방식입니다.
    /// GLTFKit2 파싱과 인스턴스마다의 hierarchy bounds 순회를 한 번으로 제한합니다.
    private static var nodeCache: [String: ModelTemplate] = [:]

    private func loadModelTemplate(from url: URL) -> ModelTemplate? {
        let key = url.path
        if let template = Self.nodeCache[key] { return template }

        guard let asset = try? GLTFAsset(url: url, options: [:]) else { return nil }
        let scene = SCNScene(gltfAsset: asset)
        guard !scene.rootNode.childNodes.isEmpty else { return nil }

        let container = containerNode(from: scene)
        let template = ModelTemplate(node: container, bounds: hierarchyBoundingBox(container))
        Self.nodeCache[key] = template
        return template
    }

    private func containerNode(from scene: SCNScene) -> SCNNode {
        let container = SCNNode()
        for child in scene.rootNode.childNodes {
            container.addChildNode(child.clone())
        }
        removeModelArtifacts(from: container)
        return container
    }

    /// 프런트엔드 `removeReferenceModelArtifacts()`와 같은 GLB 부산물 제거.
    /// 넓은 키워드 매칭 대신 번들에 실제 존재하는 UI-kit 잔여물만 지워 모델 본체를 보존합니다.
    private func removeModelArtifacts(from node: SCNNode) {
        for child in node.childNodes {
            if isModelArtifact(child) {
                child.removeFromParentNode()
            } else {
                removeModelArtifacts(from: child)
            }
        }
    }

    private func isModelArtifact(_ node: SCNNode) -> Bool {
        let nodeName = node.name ?? ""
        let isArtifactName = nodeName.localizedCaseInsensitiveContains("Blender Bros Sci-Fi UI Pack") ||
            nodeName.caseInsensitiveCompare("Solid 25") == .orderedSame
        let hasArtifactMaterial = (node.geometry?.materials ?? []).contains { material in
            let name = material.name?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
            return name.localizedCaseInsensitiveContains("Blender Bros Sci-Fi UI Pack") ||
                name.caseInsensitiveCompare("Black plastic PL") == .orderedSame ||
                name.caseInsensitiveCompare("Monitor Screen") == .orderedSame
        }
        return isArtifactName || hasArtifactMaterial
    }

    private func prepareModelNode(
        _ node: SCNNode,
        identifier: String,
        width: Double,
        height: Double,
        depth: Double,
        templateBounds: ModelBounds?,
        makesMaterialsIndependent: Bool
    ) {
        setInteractionName(identifier, on: node)
        if makesMaterialsIndependent {
            // 문/창문은 유리 투명도처럼 인스턴스 상태가 바뀔 수 있어 재질을 독립화합니다.
            // 일반 가구는 템플릿 geometry/material을 공유해 메모리와 복제 비용을 줄입니다.
            makeMaterialsIndependent(on: node)
            applyGlassTransparency(on: node)
        }

        let size = normalizeOriginAndReturnSize(node, templateBounds: templateBounds)
        let target = SCNVector3(max(width, 0.04), max(height, 0.04), max(depth, 0.04))
        node.scale = modelScale(current: size, target: target)
    }

    private func normalizeOriginAndReturnSize(_ node: SCNNode, templateBounds: ModelBounds?) -> SCNVector3 {
        // geometry 없는 GLB 컨테이너에서도 템플릿 생성 시 계산해 둔 실제 bounds를 사용합니다.
        guard let bounds = templateBounds ?? hierarchyBoundingBox(node) else {
            return SCNVector3(0, 0, 0)
        }
        let size = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )
        node.pivot = SCNMatrix4MakeTranslation(
            (bounds.min.x + bounds.max.x) / 2,
            bounds.min.y,
            (bounds.min.z + bounds.max.z) / 2
        )
        return size
    }

    /// 노드 로컬 좌표계 기준으로 모든 하위 geometry를 감싸는 bounding box.
    private func hierarchyBoundingBox(_ root: SCNNode) -> ModelBounds? {
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
                    let point = world * corner
                    lo = simd_min(lo, SIMD3(point.x, point.y, point.z))
                    hi = simd_max(hi, SIMD3(point.x, point.y, point.z))
                    found = true
                }
            }
            node.childNodes.forEach { accumulate($0, world) }
        }

        if root.geometry != nil {
            accumulate(root, matrix_identity_float4x4)
        } else {
            root.childNodes.forEach { accumulate($0, matrix_identity_float4x4) }
        }

        guard found else { return nil }
        return ModelBounds(
            min: SCNVector3(lo.x, lo.y, lo.z),
            max: SCNVector3(hi.x, hi.y, hi.z)
        )
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
        node.childNodes.forEach { setInteractionName(name, on: $0) }
    }

    /// SceneKit은 material assignment가 geometry 객체를 통해 이뤄지므로, 재질 상태를 바꿀
    /// 노드에서만 geometry/material을 함께 복제합니다.
    private func makeMaterialsIndependent(on node: SCNNode) {
        if let geometry = node.geometry?.copy() as? SCNGeometry {
            geometry.materials = geometry.materials.map { (material) in
                (material.copy() as? SCNMaterial) ?? material
            }
            node.geometry = geometry
        }
        node.childNodes.forEach { makeMaterialsIndependent(on: $0) }
    }

    /// GLB가 OPAQUE로 내보낸 창 유리 재질을 프런트엔드와 같은 투명도로 보정합니다.
    private func applyGlassTransparency(on node: SCNNode) {
        node.geometry?.materials.forEach { material in
            guard material.name?.localizedCaseInsensitiveContains("glass") == true else { return }
            material.transparency = 0.1
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
        }
        node.childNodes.forEach { applyGlassTransparency(on: $0) }
    }

    private func isDoorOrWindow(_ category: String) -> Bool {
        category.localizedCaseInsensitiveContains("door") ||
            category.localizedCaseInsensitiveContains("window") ||
            category.localizedCaseInsensitiveContains("문") ||
            category.localizedCaseInsensitiveContains("창문")
    }

    private func makePlaceholderNode(
        identifier: String,
        width: Double,
        height: Double,
        depth: Double,
        paletteIndex: Int
    ) -> SCNNode {
        let resolvedWidth = max(width, 0.04)
        let resolvedHeight = max(height, 0.04)
        let resolvedDepth = max(depth, 0.04)
        let box = SCNBox(
            width: CGFloat(resolvedWidth),
            height: CGFloat(resolvedHeight),
            length: CGFloat(resolvedDepth),
            chamferRadius: 0.02
        )
        let material = SCNMaterial()
        material.diffuse.contents = Self.palette[Self.paletteIndex(from: paletteIndex)]
        material.locksAmbientWithDiffuse = true
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.name = identifier
        node.pivot = SCNMatrix4MakeTranslation(0, Float(-resolvedHeight / 2), 0)
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
