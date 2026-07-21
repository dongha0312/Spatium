import SceneKit

// MARK: - 에디터 씬의 수평 지오메트리 타입(footprint·벽 콜라이더·수평 경계)

struct FurnitureFootprint {
    var halfWidth: Float
    var halfDepth: Float
    var rotationY: Float

    private var xAxis: SCNVector3 {
        SCNVector3(cosf(rotationY), 0, -sinf(rotationY))
    }

    private var zAxis: SCNVector3 {
        SCNVector3(sinf(rotationY), 0, cosf(rotationY))
    }

    func projectionRadius(on axis: SCNVector3) -> Float {
        abs(axis.dotXZ(xAxis)) * halfWidth + abs(axis.dotXZ(zAxis)) * halfDepth
    }

    func contains(point: SIMD2<Float>, center: SIMD2<Float>, padding: Float = 0) -> Bool {
        let relative = SCNVector3(point.x - center.x, 0, point.y - center.y)
        let localX = relative.dotXZ(xAxis)
        let localZ = relative.dotXZ(zAxis)
        return abs(localX) < halfWidth + padding && abs(localZ) < halfDepth + padding
    }
}

struct WallCollider {
    var normal: SCNVector3
    var projection: Float
    var lengthAxis: SCNVector3
    var lengthCenter: Float
    var halfLength: Float
    /// 벽 메시 노드(카메라 방향에 따라 반투명 처리용) 및 수평 중심.
    weak var node: SCNNode?
    var center: SCNVector3

    init?(node: SCNNode, roomCenter: SCNVector3) {
        // 축 정렬 bounding box의 8개 꼭짓점만 쓰면 대각선 벽이 실제보다 넓은 사각형
        // 충돌 영역으로 부풀어 난다. 프런트엔드 wallColliders처럼 실제 geometry 정점을
        // 월드 좌표로 변환해 벽의 길이·두께·방향을 계산한다.
        let points = Self.worldGeometryPoints(of: node)
        guard points.count >= 3,
              let lengthAxis = Self.dominantHorizontalAxis(points) else { return nil }

        let candidateNormal = SCNVector3(-lengthAxis.z, 0, lengthAxis.x).normalizedXZ
        guard candidateNormal.lengthXZ > 0 else { return nil }

        let normalRange = Self.projectionRange(points, axis: candidateNormal)
        let lengthRange = Self.projectionRange(points, axis: lengthAxis)
        guard normalRange.max > normalRange.min,
              lengthRange.max - lengthRange.min > 0.05 else { return nil }

        let roomSide: Float = roomCenter.dotXZ(candidateNormal) >= (normalRange.min + normalRange.max) / 2 ? 1 : -1
        normal = SCNVector3(candidateNormal.x * roomSide, 0, candidateNormal.z * roomSide).normalizedXZ
        projection = roomSide > 0 ? normalRange.max : -normalRange.min
        self.lengthAxis = lengthAxis
        lengthCenter = (lengthRange.min + lengthRange.max) / 2
        halfLength = (lengthRange.max - lengthRange.min) / 2
        self.node = node
        let sumX = points.reduce(Float(0)) { $0 + $1.x }
        let sumZ = points.reduce(Float(0)) { $0 + $1.z }
        center = SCNVector3(sumX / Float(points.count), 0, sumZ / Float(points.count))
    }

    /// 스캔된 벽의 실제 삼각형 face마다 만든 콜라이더.
    ///
    /// 하나의 Wall mesh에는 서로 다른 방향의 대각선/ㄱ자 면이 섞일 수 있다. 전체 정점으로
    /// 한 축을 추정하면 그 면들이 만든 빈 공간까지 벽으로 취급하게 된다. 웹의
    /// `worldWallFaceCollidersFromGeometry`와 동일하게 수직에 가까운 각 triangle만 사용해
    /// 벽의 실제 면과 같은 방향·길이의 충돌 영역을 만든다.
    static func faceColliders(node: SCNNode, roomCenter: SCNVector3) -> [WallCollider] {
        worldGeometryTriangles(of: node).compactMap { triangle in
            WallCollider(node: node, facePoints: triangle, roomCenter: roomCenter)
        }
    }

    private init?(node: SCNNode, facePoints points: [SCNVector3], roomCenter: SCNVector3) {
        guard points.count == 3 else { return nil }

        let edgeA = SCNVector3(
            points[1].x - points[0].x,
            points[1].y - points[0].y,
            points[1].z - points[0].z
        )
        let edgeB = SCNVector3(
            points[2].x - points[0].x,
            points[2].y - points[0].y,
            points[2].z - points[0].z
        )
        let faceNormal = SCNVector3(
            edgeA.y * edgeB.z - edgeA.z * edgeB.y,
            edgeA.z * edgeB.x - edgeA.x * edgeB.z,
            edgeA.x * edgeB.y - edgeA.y * edgeB.x
        )
        let faceAreaTwice = sqrtf(
            faceNormal.x * faceNormal.x +
                faceNormal.y * faceNormal.y +
                faceNormal.z * faceNormal.z
        )
        // 퇴화한 면과 바닥/천장에 가까운 면은 벽 충돌 대상이 아니다.
        guard faceAreaTwice > 0.000002,
              abs(faceNormal.y / faceAreaTwice) <= 0.25 else { return nil }

        let candidateNormal = SCNVector3(faceNormal.x, 0, faceNormal.z).normalizedXZ
        guard candidateNormal.lengthXZ > 0 else { return nil }

        let candidateProjection = points.reduce(Float(0)) { $0 + $1.dotXZ(candidateNormal) } / Float(points.count)
        let roomSide: Float = roomCenter.dotXZ(candidateNormal) >= candidateProjection ? 1 : -1
        normal = SCNVector3(
            candidateNormal.x * roomSide,
            0,
            candidateNormal.z * roomSide
        ).normalizedXZ
        projection = candidateProjection * roomSide
        lengthAxis = SCNVector3(-normal.z, 0, normal.x).normalizedXZ

        let lengthRange = Self.projectionRange(points, axis: lengthAxis)
        let heightRange = Self.verticalRange(points)
        let faceLength = lengthRange.max - lengthRange.min
        let faceHeight = heightRange.max - heightRange.min
        // 웹과 같은 최소 크기. 창/문 개구부의 아주 작은 찌꺼기 triangle은 충돌면이 되지 않는다.
        guard faceLength >= 0.05, faceHeight >= 0.05 else { return nil }

        lengthCenter = (lengthRange.min + lengthRange.max) / 2
        halfLength = faceLength / 2
        self.node = node
        let centerY = (heightRange.min + heightRange.max) / 2
        center = SCNVector3(
            normal.x * projection + lengthAxis.x * lengthCenter,
            centerY,
            normal.z * projection + lengthAxis.z * lengthCenter
        )
    }

    func overlapsSpan(center: SCNVector3, footprint: FurnitureFootprint) -> Bool {
        let radius = footprint.projectionRadius(on: lengthAxis)
        let projected = center.dotXZ(lengthAxis)
        return abs(projected - lengthCenter) <= halfLength + radius + 0.04
    }

    var length: Float {
        halfLength * 2
    }

    private static func worldBoxCorners(of node: SCNNode) -> [SCNVector3] {
        let (minBounds, maxBounds) = node.boundingBox
        return [
            SCNVector3(minBounds.x, minBounds.y, minBounds.z),
            SCNVector3(maxBounds.x, minBounds.y, minBounds.z),
            SCNVector3(minBounds.x, maxBounds.y, minBounds.z),
            SCNVector3(maxBounds.x, maxBounds.y, minBounds.z),
            SCNVector3(minBounds.x, minBounds.y, maxBounds.z),
            SCNVector3(maxBounds.x, minBounds.y, maxBounds.z),
            SCNVector3(minBounds.x, maxBounds.y, maxBounds.z),
            SCNVector3(maxBounds.x, maxBounds.y, maxBounds.z)
        ].map { node.convertPosition($0, to: nil) }
    }

    private static func worldGeometryPoints(of node: SCNNode) -> [SCNVector3] {
        guard let source = node.geometry?.sources(for: .vertex).first,
              source.usesFloatComponents,
              source.componentsPerVector >= 3,
              source.bytesPerComponent == MemoryLayout<Float>.size,
              source.dataStride >= source.bytesPerComponent * source.componentsPerVector else {
            return worldBoxCorners(of: node)
        }

        var points: [SCNVector3] = []
        points.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { rawBuffer in
            for index in 0..<source.vectorCount {
                let offset = index * source.dataStride + source.dataOffset
                guard offset + MemoryLayout<Float>.size * 3 <= rawBuffer.count else { continue }
                let x = rawBuffer.loadUnaligned(fromByteOffset: offset, as: Float.self)
                let y = rawBuffer.loadUnaligned(
                    fromByteOffset: offset + MemoryLayout<Float>.size,
                    as: Float.self
                )
                let z = rawBuffer.loadUnaligned(
                    fromByteOffset: offset + MemoryLayout<Float>.size * 2,
                    as: Float.self
                )
                points.append(node.convertPosition(SCNVector3(x, y, z), to: nil))
            }
        }
        return points.isEmpty ? worldBoxCorners(of: node) : points
    }

    /// 측정 모드의 바닥 폴리곤 계산(프런트 calculateRoomMeasurements 대응)도 같은 삼각형
    /// 추출을 재사용하므로 internal로 공개한다.
    static func worldGeometryTriangles(of node: SCNNode) -> [[SCNVector3]] {
        guard let geometry = node.geometry else { return [] }
        guard let source = geometry.sources(for: .vertex).first,
              source.usesFloatComponents,
              source.componentsPerVector >= 3,
              source.bytesPerComponent == MemoryLayout<Float>.size,
              source.dataStride >= source.bytesPerComponent * source.componentsPerVector,
              // `worldGeometryPoints`가 source를 읽지 못하면 bounding box를 반환한다. face index가
              // 그 fallback 점에 적용되면 잘못된 면이 생기므로, 지원하는 실제 source만 허용한다.
              source.vectorCount > 0 else { return [] }
        let vertices = worldGeometryPoints(of: node)
        guard
              source.vectorCount == vertices.count else { return [] }

        var triangles: [[SCNVector3]] = []
        for element in geometry.elements where element.primitiveType == .triangles {
            let indices = Self.indices(in: element)
            guard !indices.isEmpty else { continue }
            for offset in stride(from: 0, to: indices.count - 2, by: 3) {
                let a = indices[offset]
                let b = indices[offset + 1]
                let c = indices[offset + 2]
                guard vertices.indices.contains(a), vertices.indices.contains(b), vertices.indices.contains(c) else { continue }
                triangles.append([vertices[a], vertices[b], vertices[c]])
            }
        }
        return triangles
    }

    private static func indices(in element: SCNGeometryElement) -> [Int] {
        guard element.bytesPerIndex > 0 else { return [] }
        let indexCount = element.primitiveCount * 3
        guard indexCount > 0 else { return [] }

        var indices: [Int] = []
        indices.reserveCapacity(indexCount)
        element.data.withUnsafeBytes { rawBuffer in
            for index in 0..<indexCount {
                let offset = index * element.bytesPerIndex
                guard offset + element.bytesPerIndex <= rawBuffer.count else { break }
                let value: Int
                switch element.bytesPerIndex {
                case 1:
                    value = Int(rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                case 2:
                    value = Int(rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                case 4:
                    value = Int(rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                default:
                    return
                }
                indices.append(value)
            }
        }
        return indices
    }

    private static func dominantHorizontalAxis(_ points: [SCNVector3]) -> SCNVector3? {
        var bestLength: Float = 0
        var best = SCNVector3(0, 0, 0)

        for a in points.indices {
            for b in points.indices where b > a {
                let dx = points[b].x - points[a].x
                let dz = points[b].z - points[a].z
                let length = dx * dx + dz * dz
                if length > bestLength {
                    bestLength = length
                    best = SCNVector3(dx, 0, dz)
                }
            }
        }

        guard bestLength > 1e-8 else { return nil }
        return best.normalizedXZ
    }

    private static func projectionRange(_ points: [SCNVector3], axis: SCNVector3) -> (min: Float, max: Float) {
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        for point in points {
            let projected = point.dotXZ(axis)
            minValue = min(minValue, projected)
            maxValue = max(maxValue, projected)
        }
        return (minValue, maxValue)
    }

    private static func verticalRange(_ points: [SCNVector3]) -> (min: Float, max: Float) {
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        for point in points {
            minValue = min(minValue, point.y)
            maxValue = max(maxValue, point.y)
        }
        return (minValue, maxValue)
    }
}

struct HorizontalBounds {
    var minX: Float
    var maxX: Float
    var minZ: Float
    var maxZ: Float

    static let defaultRoom = HorizontalBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)

    var width: Float { max(maxX - minX, 0.1) }
    var depth: Float { max(maxZ - minZ, 0.1) }
    var centerX: Float { (minX + maxX) / 2 }
    var centerZ: Float { (minZ + maxZ) / 2 }
    var radius: Float { hypotf(width, depth) / 2 }

    mutating func expand(by padding: Float) {
        minX -= padding
        maxX += padding
        minZ -= padding
        maxZ += padding
    }

    func inset(by padding: Float) -> HorizontalBounds {
        guard width > padding * 2, depth > padding * 2 else { return self }
        return HorizontalBounds(
            minX: minX + padding,
            maxX: maxX - padding,
            minZ: minZ + padding,
            maxZ: maxZ - padding
        )
    }

    func clampedX(_ value: Float, inset: Float) -> Float {
        let lower = minX + inset
        let upper = maxX - inset
        guard lower <= upper else { return centerX }
        return min(max(value, lower), upper)
    }

    func clampedZ(_ value: Float, inset: Float) -> Float {
        let lower = minZ + inset
        let upper = maxZ - inset
        guard lower <= upper else { return centerZ }
        return min(max(value, lower), upper)
    }

    static func union(_ lhs: HorizontalBounds?, _ rhs: HorizontalBounds?) -> HorizontalBounds? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return HorizontalBounds(
                minX: min(lhs.minX, rhs.minX),
                maxX: max(lhs.maxX, rhs.maxX),
                minZ: min(lhs.minZ, rhs.minZ),
                maxZ: max(lhs.maxZ, rhs.maxZ)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
