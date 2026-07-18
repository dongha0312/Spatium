import Foundation
import GLTFKit2
import OSLog
import SceneKit
import simd
import UIKit

protocol FurnitureModelLoader {
    func makeNode(for furniture: PlacedFurniture) -> SCNNode
    func makeNode(for item: EditableScanItem) -> SCNNode
    /// 책장 꾸미기용 피규어 노드. identifier가 서브트리 전체 이름으로 들어가 탭 판정에 쓰인다.
    func makeDecorNode(identifier: String, decoration: PlacedDecoration) -> SCNNode
}

/// SceneKit 모델처럼 생성 비용이 큰 값을 최근 사용 순서로 제한해 보관합니다.
/// 파일 크기는 실제 파싱 메모리와 같지 않지만, 크기가 크게 다른 GLB 사이에서
/// 개수 제한만 적용할 때보다 예측 가능한 캐시 예산을 제공하는 기준으로 사용합니다.
struct BoundedLRUCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
    }

    let countLimit: Int
    let totalCostLimit: Int

    private var entries: [Key: Entry] = [:]
    private var accessOrder: [Key] = []
    private(set) var totalCost = 0

    var count: Int { entries.count }
    var keysInLeastRecentlyUsedOrder: [Key] { accessOrder }

    init(countLimit: Int, totalCostLimit: Int) {
        precondition(countLimit > 0)
        precondition(totalCostLimit > 0)
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
    }

    mutating func value(forKey key: Key) -> Value? {
        guard let value = entries[key]?.value else { return nil }
        markAsMostRecentlyUsed(key)
        return value
    }

    mutating func insert(_ value: Value, forKey key: Key, cost: Int) {
        let normalizedCost = max(cost, 0)
        if let previous = entries[key] {
            totalCost -= previous.cost
        }
        entries[key] = Entry(value: value, cost: normalizedCost)
        totalCost += normalizedCost
        markAsMostRecentlyUsed(key)
        trimToLimits()
    }

    mutating func removeAll() {
        entries.removeAll()
        accessOrder.removeAll()
        totalCost = 0
    }

    private mutating func markAsMostRecentlyUsed(_ key: Key) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
    }

    private mutating func trimToLimits() {
        while entries.count > countLimit || totalCost > totalCostLimit {
            // 한 모델 자체가 예산보다 크더라도 가장 최근 모델 하나는 유지합니다.
            // 캐시를 완전히 비우면 같은 대형 가구를 여러 개 배치할 때 매번 GLB를
            // 다시 파싱해 오히려 메모리와 지연이 증가할 수 있습니다.
            guard accessOrder.count > 1 else { return }
            let key = accessOrder.removeFirst()
            if let removed = entries.removeValue(forKey: key) {
                totalCost -= removed.cost
            }
        }
    }
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

    /// 기준 치수로 맞춤(fit)된 피규어 모델만 만든다. 배치 transform(위치/회전/균일 크기)은
    /// 씬 쪽 래퍼 노드가 담당한다 — 크기 슬라이더가 맞춤 스케일을 건드리지 않게 분리.
    func makeDecorNode(identifier: String, decoration: PlacedDecoration) -> SCNNode {
        makeRenderableNode(
            identifier: identifier,
            name: decoration.name,
            category: "figure",
            width: decoration.width,
            height: decoration.height,
            depth: decoration.depth,
            paletteIndex: decoration.decorId,
            preferredModel: decoration.modelName
        )
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
    /// GLTFKit2 파싱과 인스턴스마다의 hierarchy bounds 순회를 한 번으로 제한하되,
    /// 여러 방과 사용자 모델을 탐색해도 파싱된 템플릿이 세션 내내 누적되지 않게 합니다.
    static let modelTemplateCacheCountLimit = 8
    static let modelTemplateCacheSourceByteLimit = 64 * 1_024 * 1_024
    private static var nodeCache = BoundedLRUCache<String, ModelTemplate>(
        countLimit: modelTemplateCacheCountLimit,
        totalCostLimit: modelTemplateCacheSourceByteLimit
    )

    /// 큰 GLB(침대 등)는 파싱 후 수백 MB를 차지할 수 있고 캐시는 세션 내내 쌓인다.
    /// 스캔+에디터가 겹치는 메모리 피크에서 jetsam으로 죽지 않도록, 시스템 메모리 경고가
    /// 오면 템플릿 캐시를 비운다. (다음 렌더 때 필요한 모델만 다시 파싱된다)
    private static let memoryWarningObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: .main
    ) { _ in
        nodeCache.removeAll()
    }

    private func loadModelTemplate(from url: URL) -> ModelTemplate? {
        _ = Self.memoryWarningObserver // 첫 로드 때 옵저버 등록을 보장한다(lazy static).
        let key = url.path
        if let template = Self.nodeCache.value(forKey: key) { return template }

        // 콜드 캐시 GLB 파싱만 계측한다. LRU 적중은 위에서 이미 반환됐다.
        let signposter = PerformanceSignposts.editor
        let parseInterval = signposter.beginInterval("editor.furniture.template.parse", id: signposter.makeSignpostID())
        defer { signposter.endInterval("editor.furniture.template.parse", parseInterval) }

        guard let asset = try? GLTFAsset(url: url, options: [:]) else { return nil }
        let scene = SCNScene(gltfAsset: asset)
        guard !scene.rootNode.childNodes.isEmpty else { return nil }

        let container = containerNode(from: scene)
        let template = ModelTemplate(node: container, bounds: hierarchyBoundingBox(container))
        let sourceBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        Self.nodeCache.insert(template, forKey: key, cost: sourceBytes)
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
