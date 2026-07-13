import Foundation
import simd

/// 원시 RoomPlan export JSON(objects/doors/windows + transform.columns) 파서.
/// 번들에 내장된 테스트 스캔을 CapturedRoom 없이 직접 편집기에 로드할 때 사용합니다.
struct RoomPlanExportJSON: Decodable {
    struct Dim: Decodable { let x: Float; let y: Float; let z: Float }
    struct Transform: Decodable { let columns: [[Float]] }
    struct Entry: Decodable {
        let category: String?
        let dimensions: Dim
        let transform: Transform
    }

    let objects: [Entry]
    let doors: [Entry]
    let windows: [Entry]
    /// 사용자가 편집기에서 확정한 객체(이동/회전/교체/추가/삭제 반영). 있으면 이걸 우선 사용한다.
    let editedObjects: [EditableScanItem]?
    /// 프런트엔드가 저장하는 선택 바닥색. 없으면 원본 USDZ 바닥 재질을 유지합니다.
    let floorColor: String?

    enum CodingKeys: String, CodingKey {
        case objects, doors, windows, editedObjects
        case floorColor = "_spatiumFloorColor"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objects = (try? c.decode([Entry].self, forKey: .objects)) ?? []
        doors = (try? c.decode([Entry].self, forKey: .doors)) ?? []
        windows = (try? c.decode([Entry].self, forKey: .windows)) ?? []
        editedObjects = try? c.decode([EditableScanItem].self, forKey: .editedObjects)
        floorColor = try? c.decode(String.self, forKey: .floorColor)
    }

    private static func matrix(_ transform: Transform) -> simd_float4x4 {
        func column(_ index: Int) -> SIMD4<Float> {
            let values = index < transform.columns.count ? transform.columns[index] : []
            func at(_ i: Int) -> Float { i < values.count ? values[i] : 0 }
            return SIMD4<Float>(at(0), at(1), at(2), at(3))
        }
        return simd_float4x4(columns: (column(0), column(1), column(2), column(3)))
    }

    private static func dim(_ dimension: Dim) -> SIMD3<Float> {
        SIMD3<Float>(dimension.x, dimension.y, dimension.z)
    }

    func items() -> [EditableScanItem] {
        // 편집 확정본이 있으면 그대로 사용해 편집 결과를 완벽히 복원한다.
        if let editedObjects, !editedObjects.isEmpty {
            return editedObjects
        }
        return EditableScanItem.makeItems(
            objects: objects.map { ($0.category ?? "object", Self.dim($0.dimensions), Self.matrix($0.transform)) },
            doors: doors.map { (Self.dim($0.dimensions), Self.matrix($0.transform)) },
            windows: windows.map { (Self.dim($0.dimensions), Self.matrix($0.transform)) }
        )
    }
}

/// 번들에 내장된 테스트 스캔 로더.
enum TestRoomData {
    struct AddedFurniture {
        let name: String
        let modelName: String
        let width: Double
        let height: Double
        let depth: Double
        let positionX: Double
        let positionY: Double
        let positionZ: Double
        var rotationY: Double = 0

        func makeItem() -> EditableScanItem {
            var item = EditableScanItem(
                userAddedNamed: name,
                width: width,
                height: height,
                depth: depth
            )
            item.detectedCategory = name
            item.positionX = positionX
            item.positionY = positionY
            item.positionZ = positionZ
            item.detectedRotationY = rotationY
            item.modelName = modelName
            item.editNote = "개발자 테스트 가구"
            return item
        }
    }

    struct Scan: Identifiable {
        let id: String
        let title: String
        let roomName: String
        let jsonResource: String
        let usdzResource: String
        let area: Double
        let ceilingHeight: Double
        var addedFurniture: [AddedFurniture] = []

        func load() -> (items: [EditableScanItem], usdzURL: URL?)? {
            guard var loaded = TestRoomData.load(jsonResource: jsonResource, usdzResource: usdzResource) else {
                return nil
            }
            loaded.items.append(contentsOf: addedFurniture.map { $0.makeItem() })
            return loaded
        }
    }

    static let scans: [Scan] = [
        Scan(
            id: "dormitory",
            title: "3D 에디터 (도미토리 내장 스캔)",
            roomName: "도미토리 테스트",
            jsonResource: "domitory_test",
            usdzResource: "domitory_test",
            area: 16,
            ceilingHeight: 2.4
        ),
        Scan(
            id: "other-room-1",
            title: "3D 에디터 (다른 방 스캔 1)",
            roomName: "다른 방 테스트 1",
            jsonResource: "room_scan_other_1",
            usdzResource: "room_scan_other_1",
            area: 16,
            ceilingHeight: 2.4
        ),
        Scan(
            id: "other-room-2",
            title: "3D 에디터 (다른 방 스캔 2)",
            roomName: "다른 방 테스트 2",
            jsonResource: "room_scan_other_2",
            usdzResource: "room_scan_other_2",
            area: 16,
            ceilingHeight: 2.4,
            addedFurniture: [
                AddedFurniture(
                    name: "사용자 생성 가구 테스트",
                    modelName: "usr_dfcb0a2619784c6faa11b2bfe17eb363",
                    width: 1.0,
                    height: 1.2,
                    depth: 0.8,
                    positionX: 0.3,
                    positionY: -0.524,
                    positionZ: -5.5
                )
            ]
        ),
        Scan(
            id: "other-room-3",
            title: "3D 에디터 (다른 방 스캔 3)",
            roomName: "다른 방 테스트 3",
            jsonResource: "room_scan_other_3",
            usdzResource: "room_scan_other_3",
            area: 16,
            ceilingHeight: 2.4
        )
    ]

    /// 도미토리 테스트 스캔 (usdz 메시 + 감지 객체 JSON).
    static func dormitory() -> (items: [EditableScanItem], usdzURL: URL?)? {
        load(jsonResource: "domitory_test", usdzResource: "domitory_test")
    }

    private static func load(jsonResource: String, usdzResource: String) -> (items: [EditableScanItem], usdzURL: URL?)? {
        guard let jsonURL = Bundle.main.url(forResource: jsonResource, withExtension: "json"),
              let data = try? Data(contentsOf: jsonURL),
              let export = try? JSONDecoder().decode(RoomPlanExportJSON.self, from: data) else {
            return nil
        }
        return (export.items(), Bundle.main.url(forResource: usdzResource, withExtension: "usdz"))
    }
}
