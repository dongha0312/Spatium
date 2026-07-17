import Foundation
import SceneKit

enum GLBTransformBaker {
    nonisolated static let streamingBufferSize = 1_048_576
    nonisolated private static let jsonChunkType: UInt32 = 0x4E4F534A

    private struct ChunkDescriptor: Sendable {
        let type: UInt32
        let length: UInt64
        let payloadOffset: UInt64
    }

    private struct FileLayout: Sendable {
        let fileSize: UInt64
        let chunks: [ChunkDescriptor]
        let jsonPayload: Data
    }

    /// 대용량 GLB의 BIN 청크를 메모리에 올리지 않고 파일에서 파일로 복사한다.
    /// source가 외부 파일 공급자 URL이어도 작업이 끝날 때까지 보안 범위 접근을 유지한다.
    nonisolated static func bakeFileInBackground(
        sourceURL: URL,
        destinationURL: URL,
        transform: ImgTo3DModelTransform
    ) async throws -> URL {
        let worker: Task<URL, Error> = Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try Task.checkCancellation()
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed { sourceURL.stopAccessingSecurityScopedResource() }
                }
                return try bakeFile(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    transform: transform
                )
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 파일 기반 보정의 동기 코어. 호출자는 메인 액터 밖에서 실행해야 한다.
    @discardableResult
    nonisolated static func bakeFile(
        sourceURL: URL,
        destinationURL: URL,
        transform: ImgTo3DModelTransform
    ) throws -> URL {
        try Task.checkCancellation()
        let layout = try inspectFile(at: sourceURL)
        guard let jsonChunk = layout.chunks.first,
              jsonChunk.type == jsonChunkType else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let correctedJSON = try correctedJSONPayload(
            from: layout.jsonPayload,
            transform: transform
        )
        let outputLength = layout.fileSize
            - jsonChunk.length
            + UInt64(correctedJSON.count)
        guard outputLength <= UInt64(UInt32.max) else {
            throw CocoaError(.fileWriteOutOfSpace)
        }

        let fileManager = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
        )

        do {
            try writeCorrectedFile(
                sourceURL: sourceURL,
                temporaryURL: temporaryURL,
                layout: layout,
                correctedJSON: correctedJSON,
                outputLength: UInt32(outputLength)
            )
            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// 작은 인메모리 입력과 기존 단위 테스트를 위한 호환 경로.
    /// 앱의 실제 가구 저장은 `bakeFileInBackground`를 사용한다.
    nonisolated static func bake(data: Data, transform: ImgTo3DModelTransform) throws -> Data {
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
        chunks[0].payload = try correctedJSONPayload(from: chunks[0].payload, transform: transform)

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

    nonisolated private static func inspectFile(at url: URL) throws -> FileLayout {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= 20, fileSize <= UInt64(UInt32.max) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try handle.seek(toOffset: 0)
        let header = try readExactly(from: handle, count: 12)
        guard header.prefix(4) == Data("glTF".utf8),
              readUInt32(header, at: 4) == 2,
              UInt64(readUInt32(header, at: 8)) == fileSize else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var chunks: [ChunkDescriptor] = []
        var offset: UInt64 = 12
        while offset < fileSize {
            try Task.checkCancellation()
            guard fileSize - offset >= 8 else { throw CocoaError(.fileReadCorruptFile) }
            try handle.seek(toOffset: offset)
            let chunkHeader = try readExactly(from: handle, count: 8)
            let length = UInt64(readUInt32(chunkHeader, at: 0))
            let type = readUInt32(chunkHeader, at: 4)
            let payloadOffset = offset + 8
            guard length <= fileSize - payloadOffset else {
                throw CocoaError(.fileReadCorruptFile)
            }
            chunks.append(.init(type: type, length: length, payloadOffset: payloadOffset))
            offset = payloadOffset + length
        }
        guard offset == fileSize,
              let first = chunks.first,
              first.type == jsonChunkType,
              first.length <= UInt64(Int.max) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try handle.seek(toOffset: first.payloadOffset)
        let jsonPayload = try readExactly(from: handle, count: Int(first.length))
        return FileLayout(fileSize: fileSize, chunks: chunks, jsonPayload: jsonPayload)
    }

    nonisolated private static func writeCorrectedFile(
        sourceURL: URL,
        temporaryURL: URL,
        layout: FileLayout,
        correctedJSON: Data,
        outputLength: UInt32
    ) throws {
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let source = try FileHandle(forReadingFrom: sourceURL)
        defer { try? source.close() }
        let output = try FileHandle(forWritingTo: temporaryURL)
        defer { try? output.close() }

        var header = Data("glTF".utf8)
        appendUInt32(2, to: &header)
        appendUInt32(outputLength, to: &header)
        try output.write(contentsOf: header)

        for (index, chunk) in layout.chunks.enumerated() {
            try Task.checkCancellation()
            let payloadLength = index == 0 ? UInt32(correctedJSON.count) : UInt32(chunk.length)
            var chunkHeader = Data()
            appendUInt32(payloadLength, to: &chunkHeader)
            appendUInt32(chunk.type, to: &chunkHeader)
            try output.write(contentsOf: chunkHeader)

            if index == 0 {
                try output.write(contentsOf: correctedJSON)
            } else {
                try copyPayload(
                    from: source,
                    offset: chunk.payloadOffset,
                    length: chunk.length,
                    to: output
                )
            }
        }
        try output.synchronize()
    }

    nonisolated private static func copyPayload(
        from source: FileHandle,
        offset: UInt64,
        length: UInt64,
        to output: FileHandle
    ) throws {
        try source.seek(toOffset: offset)
        var remaining = length
        while remaining > 0 {
            try Task.checkCancellation()
            let requested = Int(min(UInt64(streamingBufferSize), remaining))
            guard let chunk = try source.read(upToCount: requested), !chunk.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    nonisolated private static func readExactly(
        from handle: FileHandle,
        count: Int
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            result.append(chunk)
        }
        return result
    }

    nonisolated private static func correctedJSONPayload(
        from payload: Data,
        transform: ImgTo3DModelTransform
    ) throws -> Data {
        let jsonData = payload.prefix { byte in byte != 0 }
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
        return encoded
    }

    nonisolated private static func transformMatrix(_ transform: ImgTo3DModelTransform) -> [Float] {
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

    nonisolated private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].enumerated().reduce(0) { partial, element in
            partial | UInt32(element.element) << UInt32(element.offset * 8)
        }
    }

    nonisolated private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
