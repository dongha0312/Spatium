import Foundation

private struct SaveLayoutRequest: Encodable {
    struct FurnitureEntry: Encodable {
        var itemId: Int?
        var furnitureId: Int
        var position: FurnitureTransform.Vector3
        var rotation: FurnitureTransform.Vector3
        var scale: FurnitureTransform.Vector3
    }
    struct SpaceEntry: Encodable {
        var name: String
        var area: Double
        var ceilingHeight: Double
        var wallColor: String
    }
    var space: SpaceEntry?
    var furnitures: [FurnitureEntry]
}

private struct ViewModeRequest: Encodable {
    var viewMode: String
}

private struct SpacePatchRequest: Encodable {
    var name: String?
    var area: Double?
    var ceilingHeight: Double?
    var wallColor: String?
}

private struct PlaceFurnitureRequest: Encodable {
    var furnitureId: Int
    var position: FurnitureTransform.Vector3
    var rotation: FurnitureTransform.Vector3
    var scale: FurnitureTransform.Vector3
}

private struct TransformRequest: Encodable {
    var position: FurnitureTransform.Vector3
    var rotation: FurnitureTransform.Vector3
    var scale: FurnitureTransform.Vector3
}

private struct ReplaceRequest: Encodable {
    var newFurnitureId: Int
}

struct RoomEditorService {
    func fetchLayout(roomID: String) async throws -> RoomLayout {
        throw URLError(.unsupportedURL)
    }

    func saveLayout(roomID: String, layout: RoomLayout) async throws {
    }

    func updateViewMode(roomID: String, mode: RoomViewMode) async throws {
    }

    func updateSpace(spaceID: String, name: String?, area: Double?, ceilingHeight: Double?, wallColor: String?) async throws {
    }

    func placeFurniture(roomID: String, furnitureID: Int, transform: FurnitureTransform) async throws -> PlacedFurniture {
        throw URLError(.unsupportedURL)
    }

    func updateTransform(itemID: Int, transform: FurnitureTransform) async throws {
    }

    func replaceFurniture(itemID: Int, newFurnitureID: Int) async throws {
    }

    func deleteFurniture(itemID: Int) async throws {
    }
}
