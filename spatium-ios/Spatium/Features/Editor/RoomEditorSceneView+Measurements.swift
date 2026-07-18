import SceneKit
import UIKit

// MARK: - 측정 모드 치수선·라벨 (프런트엔드 calculateRoomMeasurements/addRoomMeasurements 대응)

/// 방 폭·깊이·높이·면적과 표시용 외곽선/높이선. 프런트엔드 `calculateRoomMeasurements`의
/// 반환 구조를 그대로 옮겼다 — 바닥 mesh 폴리곤을 찾으면 실제 바닥 기준, 못 찾으면
/// 방 전체 bounding box 기준으로 계산한다.
struct RoomMeasurements {
    struct Segment {
        var start: SCNVector3
        var end: SCNVector3
        var length: Float
    }

    var width: Float
    var depth: Float
    var height: Float
    /// 실제 바닥 폴리곤 면적(m²). 바닥 mesh가 없으면 width × depth.
    var area: Float
    var center: SCNVector3
    var heightSegment: Segment
    var outlineSegments: [Segment]
}

extension RoomEditorSceneView.Coordinator {
    // 프런트엔드 roomMeasurements.js의 상수들.
    static let measurementMinTriangleArea: Float = 1e-6
    static let measurementPointPrecision: Float = 1000
    static let measurementOutlineMinLength: Float = 0.08
    static let measurementLineOffset: Float = 0.14
    static let measurementTickLength: Float = 0.18

    // MARK: - 방 치수 계산

    /// 프런트엔드 `calculateRoomMeasurements` 대응. 바닥 mesh 삼각형을 Y높이별로 그룹핑해
    /// 가장 넓은 그룹을 메인 바닥으로 선택하고, edge 사용 횟수가 1인 변을 바깥 테두리로 삼는다.
    static func calculateRoomMeasurements(from shell: SCNNode) -> RoomMeasurements? {
        guard let roomBox = worldBoundingBox(of: shell) else { return nil }

        let floorGroup = largestFloorGroup(in: shell)
        let hasFloorBounds = floorGroup?.bounds.isValid == true

        let width = hasFloorBounds
            ? floorGroup!.bounds.maxX - floorGroup!.bounds.minX
            : roomBox.max.x - roomBox.min.x
        let depth = hasFloorBounds
            ? floorGroup!.bounds.maxZ - floorGroup!.bounds.minZ
            : roomBox.max.z - roomBox.min.z
        let height = roomBox.max.y - roomBox.min.y
        let area = floorGroup.map(\.area) ?? width * depth
        let measurementY = hasFloorBounds
            ? floorGroup!.edges.values.first?.start.y ?? roomBox.min.y
            : roomBox.min.y
        let outlineBounds = hasFloorBounds
            ? floorGroup!.bounds
            : FloorBounds(
                minX: roomBox.min.x, maxX: roomBox.max.x,
                minZ: roomBox.min.z, maxZ: roomBox.max.z
            )

        let outlineSegments: [RoomMeasurements.Segment]
        if let floorGroup {
            outlineSegments = floorGroup.edges.values
                .filter { $0.count == 1 }
                .map { edge in
                    RoomMeasurements.Segment(
                        start: edge.start,
                        end: edge.end,
                        length: hypotf(edge.end.x - edge.start.x, edge.end.z - edge.start.z)
                    )
                }
                .filter { $0.length > measurementOutlineMinLength }
        } else {
            outlineSegments = rectangleOutlineSegments(bounds: outlineBounds, y: measurementY)
        }

        return RoomMeasurements(
            width: width,
            depth: depth,
            height: height,
            area: area > 0 ? area : width * depth,
            center: SCNVector3(
                (outlineBounds.minX + outlineBounds.maxX) / 2,
                measurementY,
                (outlineBounds.minZ + outlineBounds.maxZ) / 2
            ),
            heightSegment: RoomMeasurements.Segment(
                start: SCNVector3(outlineBounds.maxX + 0.18, roomBox.min.y, outlineBounds.minZ - 0.18),
                end: SCNVector3(outlineBounds.maxX + 0.18, roomBox.max.y, outlineBounds.minZ - 0.18),
                length: height
            ),
            outlineSegments: outlineSegments
        )
    }

    /// 바닥 mesh가 없는 박스 방/폴백 경로용. 프런트엔드의 bounding box fallback과 같은
    /// 직사각형 외곽선·높이선을 만든다.
    static func fallbackRoomMeasurements(
        bounds: HorizontalBounds,
        floorY: Float,
        height: Float
    ) -> RoomMeasurements {
        let floorBounds = FloorBounds(
            minX: bounds.minX, maxX: bounds.maxX,
            minZ: bounds.minZ, maxZ: bounds.maxZ
        )
        return RoomMeasurements(
            width: bounds.width,
            depth: bounds.depth,
            height: height,
            area: bounds.width * bounds.depth,
            center: SCNVector3(bounds.centerX, floorY, bounds.centerZ),
            heightSegment: RoomMeasurements.Segment(
                start: SCNVector3(bounds.maxX + 0.18, floorY, bounds.minZ - 0.18),
                end: SCNVector3(bounds.maxX + 0.18, floorY + height, bounds.minZ - 0.18),
                length: height
            ),
            outlineSegments: rectangleOutlineSegments(bounds: floorBounds, y: floorY)
        )
    }

    struct FloorBounds {
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude

        init() {}
        init(minX: Float, maxX: Float, minZ: Float, maxZ: Float) {
            self.minX = minX
            self.maxX = maxX
            self.minZ = minZ
            self.maxZ = maxZ
        }

        var isValid: Bool { minX <= maxX && minZ <= maxZ }

        mutating func insert(_ point: SCNVector3) {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
    }

    struct FloorEdge {
        var count: Int
        var start: SCNVector3
        var end: SCNVector3
    }

    struct FloorGroup {
        var area: Float = 0
        var bounds = FloorBounds()
        var edges: [String: FloorEdge] = [:]
    }

    /// 좌표를 반올림해 문자열 키로 만든다 — 부동소수점 오차로 같은 점이 다르게 판정되는 것을 막는다.
    private static func pointKey(_ point: SCNVector3) -> String {
        let precision = measurementPointPrecision
        return "\(Int((point.x * precision).rounded())):\(Int((point.z * precision).rounded()))"
    }

    /// 방향과 무관한 선분 키 — 같은 edge를 양쪽 삼각형에서 만나도 하나로 인식한다.
    private static func segmentKey(_ a: SCNVector3, _ b: SCNVector3) -> String {
        let aKey = pointKey(a)
        let bKey = pointKey(b)
        return aKey < bKey ? "\(aKey)|\(bKey)" : "\(bKey)|\(aKey)"
    }

    /// 바닥 mesh 삼각형을 Y높이별로 그룹핑해 면적·바운드·edge 사용 횟수를 누적하고,
    /// 면적이 가장 넓은 그룹(메인 바닥)을 반환한다. (단차·작은 조각은 무시)
    private static func largestFloorGroup(in shell: SCNNode) -> FloorGroup? {
        var groups: [Int: FloorGroup] = [:]

        func visit(_ node: SCNNode) {
            if isFloorGeometryNode(node) {
                for triangle in WallCollider.worldGeometryTriangles(of: node) {
                    accumulate(triangle: triangle, into: &groups)
                }
            }
            node.childNodes.forEach(visit)
        }

        visit(shell)
        return groups.values.max { $0.area < $1.area }
    }

    private static func accumulate(triangle: [SCNVector3], into groups: inout [Int: FloorGroup]) {
        guard triangle.count == 3 else { return }
        let a = triangle[0], b = triangle[1], c = triangle[2]

        // 수평에 가까운 면(법선 |y| ≥ 0.5)만 바닥으로 취급한다.
        let edgeA = SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)
        let edgeB = SIMD3<Float>(c.x - a.x, c.y - a.y, c.z - a.z)
        let normal = simd_cross(edgeA, edgeB)
        guard simd_length_squared(normal) >= measurementMinTriangleArea else { return }
        guard abs(simd_normalize(normal).y) >= 0.5 else { return }

        // 바닥 평면(XZ) 투영 면적.
        let area = abs(a.x * (b.z - c.z) + b.x * (c.z - a.z) + c.x * (a.z - b.z)) / 2
        guard area >= measurementMinTriangleArea else { return }

        let averageY = (a.y + b.y + c.y) / 3
        let key = Int((averageY * measurementPointPrecision).rounded())
        var group = groups[key] ?? FloorGroup()
        group.area += area
        group.bounds.insert(a)
        group.bounds.insert(b)
        group.bounds.insert(c)
        for (start, end) in [(a, b), (b, c), (c, a)] {
            let edgeKey = segmentKey(start, end)
            if var existing = group.edges[edgeKey] {
                existing.count += 1
                group.edges[edgeKey] = existing
            } else {
                group.edges[edgeKey] = FloorEdge(count: 1, start: start, end: end)
            }
        }
        groups[key] = group
    }

    private static func rectangleOutlineSegments(bounds: FloorBounds, y: Float) -> [RoomMeasurements.Segment] {
        let width = bounds.maxX - bounds.minX
        let depth = bounds.maxZ - bounds.minZ
        return [
            RoomMeasurements.Segment(
                start: SCNVector3(bounds.minX, y, bounds.minZ),
                end: SCNVector3(bounds.maxX, y, bounds.minZ),
                length: width
            ),
            RoomMeasurements.Segment(
                start: SCNVector3(bounds.maxX, y, bounds.minZ),
                end: SCNVector3(bounds.maxX, y, bounds.maxZ),
                length: depth
            ),
            RoomMeasurements.Segment(
                start: SCNVector3(bounds.maxX, y, bounds.maxZ),
                end: SCNVector3(bounds.minX, y, bounds.maxZ),
                length: width
            ),
            RoomMeasurements.Segment(
                start: SCNVector3(bounds.minX, y, bounds.maxZ),
                end: SCNVector3(bounds.minX, y, bounds.minZ),
                length: depth
            )
        ]
    }

    /// 셸 전체(geometry 노드 계층)의 월드 bounding box.
    static func worldBoundingBox(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minBounds: SCNVector3?
        var maxBounds: SCNVector3?

        func visit(_ node: SCNNode) {
            if node.geometry != nil {
                let (localMin, localMax) = node.boundingBox
                for corner in [
                    SCNVector3(localMin.x, localMin.y, localMin.z),
                    SCNVector3(localMax.x, localMin.y, localMin.z),
                    SCNVector3(localMin.x, localMax.y, localMin.z),
                    SCNVector3(localMax.x, localMax.y, localMin.z),
                    SCNVector3(localMin.x, localMin.y, localMax.z),
                    SCNVector3(localMax.x, localMin.y, localMax.z),
                    SCNVector3(localMin.x, localMax.y, localMax.z),
                    SCNVector3(localMax.x, localMax.y, localMax.z)
                ].map({ node.convertPosition($0, to: nil) }) {
                    minBounds = SCNVector3(
                        min(minBounds?.x ?? corner.x, corner.x),
                        min(minBounds?.y ?? corner.y, corner.y),
                        min(minBounds?.z ?? corner.z, corner.z)
                    )
                    maxBounds = SCNVector3(
                        max(maxBounds?.x ?? corner.x, corner.x),
                        max(maxBounds?.y ?? corner.y, corner.y),
                        max(maxBounds?.z ?? corner.z, corner.z)
                    )
                }
            }
            node.childNodes.forEach(visit)
        }

        visit(root)
        guard let minBounds, let maxBounds else { return nil }
        return (minBounds, maxBounds)
    }

    // MARK: - 표시 제어

    func setMeasurementVisible(_ isVisible: Bool) {
        let didChange = measurementContainer.isHidden == isVisible
        guard didChange else { return }
        if isVisible {
            rebuildMeasurementNodes()
        }
        measurementContainer.isHidden = !isVisible
        if didChange, viewModel.viewMode == .skyView {
            applyCamera(mode: viewModel.viewMode, animated: true)
        }
    }

    /// 가구 드래그 중 실시간 치수 표시를 유지하되, 매 터치 샘플마다 텍스트/선 geometry를
    /// 전부 재생성하지 않는다. 종료 이벤트는 force로 최종 위치를 빠짐없이 반영한다.
    func rebuildMeasurementsDuringInteraction(
        at timestamp: CFTimeInterval = CACurrentMediaTime(),
        force: Bool = false
    ) {
        guard viewModel.isMeasuring else { return }
        guard force
                || timestamp - lastInteractiveMeasurementRefreshTime >= interactiveMeasurementRefreshInterval else {
            return
        }
        lastInteractiveMeasurementRefreshTime = timestamp
        rebuildMeasurementNodes()
    }

    // MARK: - 노드 구성 (프런트엔드 addRoomMeasurements 대응)

    /// 방 외곽선(edge별 선 + 양끝 눈금 + cm 라벨), 높이선, 선택 가구 치수 라벨을 만든다.
    /// 프런트엔드와 동일하게 뷰 모드와 무관하게 같은 구성을 사용한다.
    func rebuildMeasurementNodes() {
        measurementContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard let measurements = roomMeasurements else { return }

        let offsetDistance = Self.measurementLineOffset
        let tickLength = Self.measurementTickLength
        let center = measurements.center

        for segment in measurements.outlineSegments {
            let start = segment.start
            let end = segment.end
            let midpoint = SCNVector3(
                (start.x + end.x) / 2,
                (start.y + end.y) / 2,
                (start.z + end.z) / 2
            )
            // 방 중심에서 바깥쪽으로 밀어낸다. 중심과 겹치면 선분에 수직인 방향을 쓴다.
            var outward = SCNVector3(midpoint.x - center.x, 0, midpoint.z - center.z)
            if outward.lengthXZ * outward.lengthXZ < 0.0001 {
                outward = SCNVector3(end.z - start.z, 0, -(end.x - start.x))
            }
            outward = outward.normalizedXZ
            let direction = SCNVector3(end.x - start.x, 0, end.z - start.z).normalizedXZ

            let lineStart = SCNVector3(
                start.x + outward.x * offsetDistance,
                start.y + 0.06,
                start.z + outward.z * offsetDistance
            )
            let lineEnd = SCNVector3(
                end.x + outward.x * offsetDistance,
                end.y + 0.06,
                end.z + outward.z * offsetDistance
            )
            let tickAxis = SCNVector3(-direction.z, 0, direction.x)

            measurementContainer.addChildNode(Self.makeMeasurementStroke(from: lineStart, to: lineEnd))
            for point in [lineStart, lineEnd] {
                measurementContainer.addChildNode(Self.makeMeasurementStroke(
                    from: SCNVector3(
                        point.x + tickAxis.x * tickLength / 2,
                        point.y,
                        point.z + tickAxis.z * tickLength / 2
                    ),
                    to: SCNVector3(
                        point.x - tickAxis.x * tickLength / 2,
                        point.y,
                        point.z - tickAxis.z * tickLength / 2
                    )
                ))
            }

            let label = Self.makeRoomDimensionLabel(text: Self.formatCentimeters(segment.length))
            label.position = SCNVector3(
                midpoint.x + outward.x * (offsetDistance + 0.12),
                midpoint.y + 0.12,
                midpoint.z + outward.z * (offsetDistance + 0.12)
            )
            measurementContainer.addChildNode(label)
        }

        // 높이선: 바닥 테두리 바깥 모서리에서 수직으로. 눈금은 X축 방향.
        let heightStart = measurements.heightSegment.start
        let heightEnd = measurements.heightSegment.end
        measurementContainer.addChildNode(Self.makeMeasurementStroke(from: heightStart, to: heightEnd))
        for point in [heightStart, heightEnd] {
            measurementContainer.addChildNode(Self.makeMeasurementStroke(
                from: SCNVector3(point.x + tickLength / 2, point.y, point.z),
                to: SCNVector3(point.x - tickLength / 2, point.y, point.z)
            ))
        }
        let heightLabel = Self.makeRoomDimensionLabel(
            text: Self.formatCentimeters(measurements.heightSegment.length)
        )
        heightLabel.position = SCNVector3(
            (heightStart.x + heightEnd.x) / 2 + 0.16,
            (heightStart.y + heightEnd.y) / 2,
            (heightStart.z + heightEnd.z) / 2
        )
        measurementContainer.addChildNode(heightLabel)

        addSelectedFurnitureDimensionLabels()
    }

    /// 프런트엔드 dimension-label 대응 — 측정 모드에서 선택된 가구의 가로/세로/높이 라벨.
    /// 값은 드래그·회전 중에도 흔들리지 않도록 저장된 기준 치수(metadata dimensions)를 쓴다.
    func addSelectedFurnitureDimensionLabels() {
        guard let selectedID = viewModel.selectedItemID,
              let furniture = viewModel.layout.furnitures.first(where: { $0.itemId == selectedID }),
              let node = furnitureContainer.childNode(withName: "furniture-\(selectedID)", recursively: false),
              let localBounds = Self.localHierarchyBounds(of: node) else { return }

        // 노드 로컬 bounds를 월드로 변환해 라벨 위치를 정한다.
        var worldBounds: (min: SCNVector3, max: SCNVector3)?
        for corner in [
            SCNVector3(localBounds.min.x, localBounds.min.y, localBounds.min.z),
            SCNVector3(localBounds.max.x, localBounds.min.y, localBounds.min.z),
            SCNVector3(localBounds.min.x, localBounds.max.y, localBounds.min.z),
            SCNVector3(localBounds.max.x, localBounds.max.y, localBounds.min.z),
            SCNVector3(localBounds.min.x, localBounds.min.y, localBounds.max.z),
            SCNVector3(localBounds.max.x, localBounds.min.y, localBounds.max.z),
            SCNVector3(localBounds.min.x, localBounds.max.y, localBounds.max.z),
            SCNVector3(localBounds.max.x, localBounds.max.y, localBounds.max.z)
        ].map({ node.convertPosition($0, to: nil) }) {
            worldBounds = (
                SCNVector3(
                    min(worldBounds?.min.x ?? corner.x, corner.x),
                    min(worldBounds?.min.y ?? corner.y, corner.y),
                    min(worldBounds?.min.z ?? corner.z, corner.z)
                ),
                SCNVector3(
                    max(worldBounds?.max.x ?? corner.x, corner.x),
                    max(worldBounds?.max.y ?? corner.y, corner.y),
                    max(worldBounds?.max.z ?? corner.z, corner.z)
                )
            )
        }
        guard let bounds = worldBounds else { return }

        let display = displayFurniture(for: furniture)
        let labelY = bounds.min.y + 0.08
        let entries: [(text: String, position: SCNVector3)] = [
            (
                Self.formatCentimeters(Float(display.width ?? 0)),
                SCNVector3((bounds.min.x + bounds.max.x) / 2, labelY, bounds.max.z + 0.12)
            ),
            (
                Self.formatCentimeters(Float(display.depth ?? 0)),
                SCNVector3(bounds.max.x + 0.12, labelY, (bounds.min.z + bounds.max.z) / 2)
            ),
            (
                Self.formatCentimeters(Float(display.height ?? 0)),
                SCNVector3(bounds.max.x + 0.12, (bounds.min.y + bounds.max.y) / 2, bounds.min.z - 0.12)
            )
        ]
        for entry in entries {
            let label = Self.makeFurnitureDimensionLabel(text: entry.text)
            label.position = entry.position
            measurementContainer.addChildNode(label)
        }
    }

    // MARK: - 선/라벨 프리미티브

    /// 두 점을 잇는 가는 측정선. 프런트엔드 LineBasicMaterial(0x8b8f94, opacity 0.78,
    /// depthTest off, renderOrder 40) 대응.
    static func makeMeasurementStroke(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let delta = SIMD3<Float>(end.x - start.x, end.y - start.y, end.z - start.z)
        let length = simd_length(delta)
        let box = SCNBox(width: CGFloat(max(length, 0.01)), height: 0.012, length: 0.012, chamferRadius: 0)
        box.materials = [measurementLineMaterial()]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        if length > 0.0001 {
            let direction = delta / length
            let xAxis = SIMD3<Float>(1, 0, 0)
            // 반대 방향(-X)은 사원수가 정의되지 않으므로 Y축 180도 회전으로 처리한다.
            if simd_dot(direction, xAxis) < -0.9999 {
                node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
            } else {
                node.simdOrientation = simd_quatf(from: xAxis, to: direction)
            }
        }
        node.renderingOrder = 40
        return node
    }

    static func measurementLineMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        // 라이트: 프런트엔드 선 색(0x8b8f94)·투명도(0.78). 다크: 흰색으로 가독성 유지.
        let color = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.9)
                : UIColor(hexString: "#8B8F94").withAlphaComponent(0.78)
        }
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        // 프런트엔드처럼 벽/가구에 가려지지 않고 항상 보이도록 깊이 테스트를 끈다.
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        return material
    }

    /// 방 치수 라벨 — 프런트엔드 `.room-dimension-label`(회색 굵은 글씨 + 흰 후광) 대응.
    static func makeRoomDimensionLabel(text: String) -> SCNNode {
        makeBillboardLabel(
            text: text,
            font: UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .bold),
            textColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? .white
                    : UIColor(red: 104 / 255, green: 109 / 255, blue: 115 / 255, alpha: 0.9)
            },
            haloColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.02, alpha: 0.82)
                    : UIColor.white.withAlphaComponent(0.9)
            },
            backgroundColor: nil,
            worldHeight: 0.15
        )
    }

    /// 선택 가구 치수 라벨 — 프런트엔드 `.dimension-label`(어두운 알약 배경 + 흰 글씨) 대응.
    static func makeFurnitureDimensionLabel(text: String) -> SCNNode {
        makeBillboardLabel(
            text: text,
            font: UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .bold),
            textColor: .white,
            haloColor: nil,
            backgroundColor: UIColor(white: 28 / 255, alpha: 0.92),
            worldHeight: 0.12
        )
    }

    private static func makeBillboardLabel(
        text: String,
        font: UIFont,
        textColor: UIColor,
        haloColor: UIColor?,
        backgroundColor: UIColor?,
        worldHeight: CGFloat
    ) -> SCNNode {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        if let haloColor {
            attributes[.strokeColor] = haloColor
            attributes[.strokeWidth] = -3.0
        }
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padX: CGFloat = backgroundColor == nil ? 22 : 26
        let padY: CGFloat = backgroundColor == nil ? 14 : 16
        let size = CGSize(
            width: max(textSize.width + padX * 2, 1),
            height: max(textSize.height + padY * 2, 1)
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.clear(CGRect(origin: .zero, size: size))
            if let backgroundColor {
                backgroundColor.setFill()
                UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerRadius: size.height * 0.28
                ).fill()
            }
            (text as NSString).draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: padY),
                withAttributes: attributes
            )
        }

        let aspect = size.width / max(size.height, 1)
        let plane = SCNPlane(width: worldHeight * aspect, height: worldHeight)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.emission.contents = image
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.renderingOrder = 41
        return node
    }

    // MARK: - 포맷터 (프런트엔드 measurementLabels.js 대응)

    /// 프런트엔드와 동일하게 치수를 cm 정수로 표기합니다. (예: 3.5m → "350 cm")
    static func formatCentimeters(_ value: Float) -> String {
        "\(max(Int((value * 100).rounded()), 1)) cm"
    }

    static func formatSquareMeters(_ value: Double) -> String {
        value.isFinite ? String(format: "%.2f m²", value) : "-"
    }

    static func formatPyung(_ value: Double) -> String {
        value.isFinite ? String(format: "%.1f 평", value) : "-"
    }
}
