import OSLog
import SceneKit
import UIKit

// MARK: - 방 셸(스캔 USDZ/박스 방) 구성과 벽·바닥 색상

extension RoomEditorSceneView.Coordinator {
    // MARK: - Scene construction

    func buildScene(for layout: RoomLayout) -> SCNScene {
        let signposter = PerformanceSignposts.editor
        let loadInterval = signposter.beginInterval("editor.load", id: signposter.makeSignpostID())
        defer { signposter.endInterval("editor.load", loadInterval) }

        let scene = SCNScene()

        // These nodes are reused across rebuilds; detach from any previous scene first.
        floorNode.removeFromParentNode()
        furnitureContainer.removeFromParentNode()
        measurementContainer.removeFromParentNode()
        cameraNode.removeFromParentNode()

        // GLB(PBR) 재질이 납작/검게 나오지 않도록 이미지 기반 조명 환경.
        scene.lightingEnvironment.contents = UIColor(white: 0.85, alpha: 1)
        scene.lightingEnvironment.intensity = 1.2

        if let usdzURL = viewModel.usdzURL {
            buildScannedShell(into: scene, usdzURL: usdzURL, layout: layout)
        } else {
            buildBoxRoom(into: scene, layout: layout)
        }

        scene.rootNode.addChildNode(furnitureContainer)
        rebuildFurnitureNodes(for: layout)
        scene.rootNode.addChildNode(measurementContainer)
        rebuildMeasurementNodes()
        measurementContainer.isHidden = !viewModel.isMeasuring

        let camera = SCNCamera()
        camera.zFar = 300
        // 사람 뷰(방 안 1인칭)에서 1m 이내 벽/가구가 잘려 보이지 않도록 near plane을 당긴다.
        camera.zNear = 0.05
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 700
        directional.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(directional)

        return scene
    }

    /// 면적 기반의 단순 박스 방(벽 2면 + 바닥). 서버/저장된 방 편집용.
    func buildBoxRoom(into scene: SCNScene, layout: RoomLayout) {
        isScannedRoom = false
        wallColliders = []
        shellViewFacingSurfaces = []
        wallFacingUpdater.setWalls([])
        sceneCenter = SCNVector3(0, 0.4, 0)
        let side = CGFloat((layout.space?.area ?? 16).squareRoot())
        floorSide = max(side, 2)
        sceneRadius = Float(floorSide) * 0.7
        sceneBounds = HorizontalBounds(
            minX: -Float(floorSide) / 2,
            maxX: Float(floorSide) / 2,
            minZ: -Float(floorSide) / 2,
            maxZ: Float(floorSide) / 2
        )
        roomBounds = sceneBounds
        floorLevel = 0
        let wallHeight = CGFloat(layout.space?.ceilingHeight ?? 2.4)
        roomHeight = Float(wallHeight)
        // 바닥 mesh가 없는 박스 방은 프런트엔드의 bounding box fallback과 같은 직사각형 치수.
        roomMeasurements = Self.fallbackRoomMeasurements(
            bounds: roomBounds,
            floorY: 0,
            height: roomHeight
        )
        publishRoomArea()
        let wallColor = UIColor(hexString: layout.space?.wallColor ?? "#F2EDE5")

        let floor = SCNBox(width: floorSide, height: 0.05, length: floorSide, chamferRadius: 0)
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = UIColor(hexString: layout.space?.floorColor ?? "#DECCB3")
        floor.materials = [floorMaterial]
        floorNode.geometry = floor
        floorNode.name = "floor"
        floorNode.categoryBitMask = Self.floorHitCategory
        floorNode.position = SCNVector3(0, -0.025, 0)
        scene.rootNode.addChildNode(floorNode)

        for (position, rotationY) in [
            (SCNVector3(0, Float(wallHeight / 2), Float(-floorSide / 2)), Float(0)),
            (SCNVector3(Float(-floorSide / 2), Float(wallHeight / 2), 0), Float.pi / 2)
        ] {
            let wall = SCNBox(width: floorSide, height: wallHeight, length: 0.04, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = wallColor
            wall.materials = [material]
            let node = SCNNode(geometry: wall)
            node.position = position
            node.eulerAngles.y = rotationY
            scene.rootNode.addChildNode(node)
        }
    }

    /// 실제 스캔 방 메시(USDZ)에서 벽/바닥(Arch_grp)만 남기고 가구(Object_grp)는 제거,
    /// 그 위에서 실물 GLB 가구를 편집합니다. 드래그 이동용 투명 바닥판을 함께 깝니다.
    func buildScannedShell(into scene: SCNScene, usdzURL: URL, layout: RoomLayout) {
        isScannedRoom = true
        shellViewFacingSurfaces = []
        roomHeight = Float(layout.space?.ceilingHeight ?? 2.4)
        // 프런트엔드와 동일하게, 사용자가 벽/바닥 색을 고르지 않았으면(nil)
        // 스캔 원본 재질을 그대로 유지한다. 이전에 tint된 캐시 템플릿이면 원본으로 복원한다.
        let wallColor = layout.space?.wallColor
        let floorColor = layout.space?.floorColor
        var scannedBounds: HorizontalBounds?
        var meshFloorY: Float?

        if let template = shellTemplate(for: usdzURL) {
            let shell = template.clone()
            tintWalls(in: shell, color: wallColor.map { UIColor(hexString: $0) })
            tintFloors(in: shell, color: floorColor.map { UIColor(hexString: $0) })
            scene.rootNode.addChildNode(shell)
            shellNode = shell
            renderedWallColor = wallColor
            renderedFloorColor = floorColor
            scannedBounds = Self.horizontalBounds(of: shell)
            meshFloorY = Self.shellFloorY(of: shell)
            let center = scannedBounds.map { SCNVector3($0.centerX, 0, $0.centerZ) } ?? SCNVector3(0, 0, 0)
            wallColliders = Self.makeWallColliders(from: shell, roomCenter: center)
            // 프런트엔드 calculateRoomMeasurements 대응 — 바닥 폴리곤 기준 치수·면적·외곽선.
            roomMeasurements = Self.calculateRoomMeasurements(from: shell)
            shellViewFacingSurfaces = Self.makeViewFacingSurfaces(from: wallColliders)
            shellViewFacingSurfaces += Self.makeDoorWindowViewFacingSurfaces(from: shell, roomCenter: center)
            refreshViewFacingTransparencyTargets()
        } else {
            roomMeasurements = nil
        }

        roomBounds = scannedBounds ?? .defaultRoom
        sceneBounds = roomBounds
        sceneBounds.expand(by: 0.35)

        sceneCenter = SCNVector3(sceneBounds.centerX, 0.4, sceneBounds.centerZ)
        sceneRadius = max(sceneBounds.radius, 1.5)
        floorSide = CGFloat(max(sceneBounds.width, sceneBounds.depth) + 1.5)

        let dragFloor = SCNBox(width: floorSide * 3, height: 0.01, length: floorSide * 3, chamferRadius: 0)
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = UIColor.clear
        floorMaterial.transparency = 0.001
        floorMaterial.writesToDepthBuffer = false
        floorMaterial.readsFromDepthBuffer = false
        dragFloor.materials = [floorMaterial]
        floorNode.geometry = dragFloor
        floorNode.name = "floor"
        floorNode.categoryBitMask = Self.floorHitCategory
        // 바닥 높이는 방 메시(Floor mesh)에서 찾는 것을 우선한다. 가구 최저 Y로만 잡으면
        // 모든 가구를 띄워 저장한 방에서 그 높이가 새 바닥으로 굳어(F12) 슬라이더 0점,
        // 새 가구 배치, 드래그 평면, 사람 뷰 눈높이가 전부 떠 버린다.
        // 가구 바닥과 메시 바닥이 거의 같으면(정상 배치) 가구 값을 유지해 기존 저장분의
        // 높이 슬라이더가 0에서 흔들리지 않게 한다.
        let furnitureFloorY = layout.furnitures.map { Float($0.position.y) }.min()
        let floorLevel: Float
        if let meshFloorY {
            if let furnitureFloorY, abs(furnitureFloorY - meshFloorY) < 0.1 {
                floorLevel = furnitureFloorY
            } else {
                floorLevel = meshFloorY
            }
        } else {
            floorLevel = furnitureFloorY ?? -0.005
        }
        self.floorLevel = floorLevel
        viewModel.adoptFloorY(Double(floorLevel))
        floorNode.position = SCNVector3(sceneCenter.x, floorLevel, sceneCenter.z)
        scene.rootNode.addChildNode(floorNode)

        // 셸 파싱에 실패한 폴백도 프런트엔드처럼 bounding box 직사각형 치수를 보여준다.
        if roomMeasurements == nil {
            roomMeasurements = Self.fallbackRoomMeasurements(
                bounds: roomBounds,
                floorY: floorLevel,
                height: roomHeight
            )
        }
        publishRoomArea()
    }

    /// 측정 모드 면적 배지(프런트엔드 room-area 배지 대응)용 값 게시.
    /// 씬 빌드는 SwiftUI 뷰 업데이트 중에 실행되므로 다음 런루프에서 반영한다.
    func publishRoomArea() {
        let area = roomMeasurements.map { Double($0.area) }
        let viewModel = viewModel
        DispatchQueue.main.async {
            viewModel.adoptRoomArea(area)
        }
    }

    /// 스캔 셸에서 실제 바닥 높이(월드 Y)를 찾는다. Floor/Ground/Slab mesh의 윗면을
    /// 우선 쓰고, 없으면 셸 전체의 최저점으로 근사한다. (RoomPlan 좌표계는 바닥이
    /// y=0이 아닐 수 있어, 가구 최저 Y 추정만으로는 띄운 가구가 바닥을 끌어올린다)
    static func shellFloorY(of root: SCNNode) -> Float? {
        var floorTop: Float?
        var overallMin: Float?

        func visit(_ node: SCNNode) {
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
                ].map { node.convertPosition($0, to: nil) }
                if let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max() {
                    overallMin = min(overallMin ?? minY, minY)
                    if isFloorGeometryNode(node) {
                        floorTop = max(floorTop ?? maxY, maxY)
                    }
                }
            }
            node.childNodes.forEach(visit)
        }

        visit(root)
        return floorTop ?? overallMin
    }

    /// 가구(Object_grp)를 제거한 방 셸 템플릿. 처음 한 번만 파싱하고 캐시합니다.
    func shellTemplate(for usdzURL: URL) -> SCNNode? {
        let key = usdzURL.path
        if let cached = shellCache[key] { return cached }
        // 콜드 캐시 파싱만 계측한다. 캐시 적중은 위에서 이미 반환됐다.
        let signposter = PerformanceSignposts.editor
        let parseInterval = signposter.beginInterval("editor.shell.parse", id: signposter.makeSignpostID())
        defer { signposter.endInterval("editor.shell.parse", parseInterval) }
        guard let roomScene = try? SCNScene(url: usdzURL) else { return nil }
        let template = SCNNode()
        template.name = "room-shell"
        for child in roomScene.rootNode.childNodes {
            template.addChildNode(child)
        }
        while let furnitureGroup = template.childNode(withName: "Object_grp", recursively: true) {
            furnitureGroup.removeFromParentNode()
        }
        shellCache[key] = template
        return template
    }

    /// 벽 색이 바뀐 경우에만 현재 셸 벽을 다시 칠합니다. (전체 씬 재생성 없이)
    /// nil이면 처음 기록해둔 스캔 원본 재질로 복원합니다. (프런트엔드 applyRoomWallColor 대응)
    func retintWallsIfNeeded(to hex: String?) {
        guard hex != renderedWallColor else { return }
        renderedWallColor = hex
        if let shellNode {
            tintWalls(in: shellNode, color: hex.map { UIColor(hexString: $0) })
        }
    }

    /// 프런트엔드 applyRoomFloorColor 대응. 바닥색을 지정하지 않은 스캔은
    /// 원본 USDZ 재질을 보존하고, 사용자가 선택한 경우에만 Floor/Ground/Slab mesh를 tint합니다.
    /// 선택을 해제(nil)하면 처음 기록해둔 원본 재질로 복원합니다.
    func retintFloorsIfNeeded(to hex: String?) {
        guard hex != renderedFloorColor else { return }
        renderedFloorColor = hex
        guard let shellNode else { return }
        tintFloors(in: shellNode, color: hex.map { UIColor(hexString: $0) })
    }

    /// 스캔 벽 메시(이름에 "Wall" 포함)의 diffuse를 선택한 벽 색으로 덮습니다.
    /// color가 nil이면 기록해둔 원본 diffuse로 되돌립니다.
    func tintWalls(in node: SCNNode, color: UIColor?) {
        if let name = node.name, name.localizedCaseInsensitiveContains("wall"), let geometry = node.geometry {
            geometry.materials.forEach { applySurfaceTint(color, to: $0) }
        }
        node.childNodes.forEach { tintWalls(in: $0, color: color) }
    }

    func tintFloors(in node: SCNNode, color: UIColor?) {
        if Self.isFloorGeometryNode(node), let geometry = node.geometry {
            geometry.materials.forEach { applySurfaceTint(color, to: $0) }
        }
        node.childNodes.forEach { tintFloors(in: $0, color: color) }
    }

    /// tint 적용/복원의 공통 지점. 첫 tint 직전의 diffuse(색 또는 텍스처)를 기록해두고,
    /// color가 nil이면 그 원본으로 되돌린다. 한 번도 tint하지 않은 재질은 건드리지 않는다.
    func applySurfaceTint(_ color: UIColor?, to material: SCNMaterial) {
        let key = ObjectIdentifier(material)
        if let color {
            if originalSurfaceDiffuse[key] == nil {
                originalSurfaceDiffuse[key] = material.diffuse.contents ?? NSNull()
            }
            material.diffuse.contents = color
        } else if let original = originalSurfaceDiffuse[key] {
            material.diffuse.contents = original is NSNull ? nil : original
        }
    }
}
