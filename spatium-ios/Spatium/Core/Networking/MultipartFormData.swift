import Foundation

nonisolated struct MultipartFormPart: Sendable {
    /// 작은 파트(텍스트/이미지)는 메모리로, 큰 파일(USDZ/GLB)은 URL로 실어
    /// 바디 작성 시 디스크에서 바로 스트리밍한다.
    enum Source: Sendable {
        case data(Data)
        case file(URL)
    }

    let name: String
    let source: Source
    var fileName: String?
    var contentType: String?

    init(name: String, data: Data, fileName: String? = nil, contentType: String? = nil) {
        self.name = name
        self.source = .data(data)
        self.fileName = fileName
        self.contentType = contentType
    }

    init(name: String, fileURL: URL, fileName: String? = nil, contentType: String? = nil) {
        self.name = name
        self.source = .file(fileURL)
        self.fileName = fileName ?? fileURL.lastPathComponent
        self.contentType = contentType
    }
}

/// 사용자가 고른 파일명에 든 따옴표/줄바꿈이 multipart 헤더를 깨뜨리지 않게 정리한다.
nonisolated func sanitizedMultipartToken(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\"", with: "'")
}

nonisolated enum MultipartFormDataError: Error {
    /// 파일 파트를 메모리 바디로 인코딩하려 한 경우. 대용량 USDZ/GLB가 통째로
    /// 메모리에 올라가는 사고를 막기 위해 파일 파트는 `writeBodyFile`만 허용한다.
    case filePartRequiresBodyFile
}

nonisolated struct MultipartFormData {
    let boundary: String
    let body: Data

    /// 작은 `.data` 파트 전용 메모리 바디 생성. 파일 파트가 하나라도 있으면 throw한다 —
    /// 실제 업로드 경로는 파일을 1MiB 청크로 스트리밍하는 `writeBodyFile`을 사용해야 한다.
    init(parts: [MultipartFormPart], boundary: String = "Spatium-\(UUID().uuidString)") throws {
        self.boundary = boundary
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n")
            body.append(Self.partHeader(for: part))
            switch part.source {
            case let .data(data):
                body.append(data)
            case .file:
                throw MultipartFormDataError.filePartRequiresBodyFile
            }
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        self.body = body
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    private static func partHeader(for part: MultipartFormPart) -> String {
        var disposition = "Content-Disposition: form-data; name=\"\(sanitizedMultipartToken(part.name))\""
        if let fileName = part.fileName {
            disposition += "; filename=\"\(sanitizedMultipartToken(fileName))\""
        }
        var header = "\(disposition)\r\n"
        if let contentType = part.contentType {
            header += "Content-Type: \(contentType)\r\n"
        }
        header += "\r\n"
        return header
    }

    /// multipart 바디를 임시 파일로 작성한다. 파일 파트는 1MB 청크로 복사해
    /// 대용량 USDZ/GLB를 업로드해도 바디 전체가 메모리에 올라가지 않는다.
    /// 반환된 파일은 업로드 후 호출자가 삭제해야 한다.
    static func writeBodyFile(parts: [MultipartFormPart], boundary: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }

            func write(_ string: String) throws {
                try handle.write(contentsOf: Data(string.utf8))
            }

            for part in parts {
                try write("--\(boundary)\r\n")
                try write(partHeader(for: part))
                switch part.source {
                case let .data(data):
                    try handle.write(contentsOf: data)
                case let .file(fileURL):
                    let reader = try FileHandle(forReadingFrom: fileURL)
                    defer { try? reader.close() }
                    while let chunk = try reader.read(upToCount: 1_048_576), !chunk.isEmpty {
                        try handle.write(contentsOf: chunk)
                    }
                }
                try write("\r\n")
            }
            try write("--\(boundary)--\r\n")
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
