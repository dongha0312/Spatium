import Foundation
import SceneKit

enum GLBTransformBaker {
    private static let jsonChunkType: UInt32 = 0x4E4F534A

    static func bake(data: Data, transform: ImgTo3DModelTransform) throws -> Data {
        guard data.count >= 20,
              data.prefix(4) == Data("glTF".utf8),
              readUInt32(data, at: 4) == 2,
              readUInt32(data, at: 8) == UInt32(data.count) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var chunks: [(type: UInt32, payload: Data)] = []
        var offset = 12
        while offset < data.count {
            guard offset + 8 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            let length = Int(readUInt32(data, at: offset))
            let type = readUInt32(data, at: offset + 4)
            offset += 8
            guard offset + length <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            chunks.append((type, data.subdata(in: offset..<(offset + length))))
            offset += length
        }
        guard chunks.first?.type == jsonChunkType else { throw CocoaError(.fileReadCorruptFile) }

        let jsonData = chunks[0].payload.prefix { byte in
            byte != 0
        }
        guard var document = try JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var nodes = document["nodes"] as? [[String: Any]] ?? []
        var scenes = document["scenes"] as? [[String: Any]] ?? []
        if scenes.isEmpty {
            let children = Set(nodes.flatMap { $0["children"] as? [Int] ?? [] })
            scenes = [["nodes": nodes.indices.filter { !children.contains($0) }]]
            document["scene"] = 0
        }

        let wrapperIndex = nodes.count
        let matrix = transformMatrix(transform)
        for index in scenes.indices {
            let roots = scenes[index]["nodes"] as? [Int] ?? []
            scenes[index]["nodes"] = [wrapperIndex]
            nodes.append([
                "name": "SpatiumIOSCorrection",
                "matrix": matrix,
                "children": roots,
                "extras": ["correctionSource": "iOS editor"]
            ])
            break
        }
        // 모든 scene이 같은 wrapper index를 참조할 수 없으므로 추가 scene에는 별도 wrapper를 만든다.
        if scenes.count > 1 {
            for index in scenes.indices.dropFirst() {
                let roots = scenes[index]["nodes"] as? [Int] ?? []
                let indexForScene = nodes.count
                nodes.append([
                    "name": "SpatiumIOSCorrection",
                    "matrix": matrix,
                    "children": roots,
                    "extras": ["correctionSource": "iOS editor"]
                ])
                scenes[index]["nodes"] = [indexForScene]
            }
        }
        document["nodes"] = nodes
        document["scenes"] = scenes

        var encoded = try JSONSerialization.data(withJSONObject: document, options: [.withoutEscapingSlashes])
        encoded.append(contentsOf: repeatElement(UInt8(0x20), count: (4 - encoded.count % 4) % 4))
        chunks[0].payload = encoded

        var body = Data()
        for chunk in chunks {
            appendUInt32(UInt32(chunk.payload.count), to: &body)
            appendUInt32(chunk.type, to: &body)
            body.append(chunk.payload)
        }
        var result = Data("glTF".utf8)
        appendUInt32(2, to: &result)
        appendUInt32(UInt32(12 + body.count), to: &result)
        result.append(body)
        return result
    }

    private static func transformMatrix(_ transform: ImgTo3DModelTransform) -> [Float] {
        let node = SCNNode()
        node.position = SCNVector3(transform.xPosition, transform.yPosition, transform.zPosition)
        node.eulerAngles = SCNVector3(
            Float(transform.xDegrees * .pi / 180),
            Float(transform.yDegrees * .pi / 180),
            Float(transform.zDegrees * .pi / 180)
        )
        node.scale = SCNVector3(transform.scale, transform.scale, transform.scale)
        let value = node.simdTransform
        return [
            value.columns.0.x, value.columns.0.y, value.columns.0.z, value.columns.0.w,
            value.columns.1.x, value.columns.1.y, value.columns.1.z, value.columns.1.w,
            value.columns.2.x, value.columns.2.y, value.columns.2.z, value.columns.2.w,
            value.columns.3.x, value.columns.3.y, value.columns.3.z, value.columns.3.w
        ]
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].enumerated().reduce(0) { partial, element in
            partial | UInt32(element.element) << UInt32(element.offset * 8)
        }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
