import SceneKit

/// 책장 모델을 수직으로 샘플링해 피규어를 올릴 수 있는 실제 위쪽 면의 높이를 찾는다.
enum RoomEditorShelfDetector {
    static func detectHeights(in furnitureNode: SCNNode, relativeTo container: SCNNode) -> [Double] {
        // 가구 노드를 씬에 추가한 직후 꾸미기 모드로 진입할 수 있다. 이때 아직
        // SceneKit 트랜잭션이 반영되지 않았다면 segment hit-test가 빈 결과를 돌려주므로
        // 현재 노드 변환과 geometry를 먼저 presentation tree에 확정한다.
        SCNTransaction.flush()
        guard let bounds = RoomEditorSceneView.Coordinator.localHierarchyBounds(of: furnitureNode) else {
            return []
        }
        let centerX = (bounds.min.x + bounds.max.x) / 2
        let centerZ = (bounds.min.z + bounds.max.z) / 2
        let width = bounds.max.x - bounds.min.x
        let depth = bounds.max.z - bounds.min.z
        let xOffsets: [Float] = [-0.28, 0, 0.28]
        let zOffsets: [Float] = [-0.22, 0, 0.22]
        var heights: [Double] = []

        for xOffset in xOffsets {
            for zOffset in zOffsets {
                let start = SCNVector3(
                    centerX + width * xOffset,
                    bounds.max.y + 0.1,
                    centerZ + depth * zOffset
                )
                let end = SCNVector3(
                    centerX + width * xOffset,
                    bounds.min.y - 0.1,
                    centerZ + depth * zOffset
                )
                let hits = furnitureNode.hitTestWithSegment(
                    from: start,
                    to: end,
                    options: [
                        SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                        SCNHitTestOption.ignoreHiddenNodes.rawValue: true
                    ]
                )
                for hit in hits where RoomEditorSceneView.isDecorSupportNormal(hit.worldNormal) {
                    let local = container.convertPosition(hit.worldCoordinates, from: nil)
                    guard local.y.isFinite, local.y >= -0.01 else { continue }
                    heights.append(Double(local.y))
                }
            }
        }
        return heights
    }
}
