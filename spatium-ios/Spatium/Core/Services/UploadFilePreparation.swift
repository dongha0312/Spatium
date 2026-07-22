import Foundation

/// Spring `FileValidationService`와 같은 확장자·용량·파일 헤더 규칙을 앱에서도 먼저 확인합니다.
/// 문서 선택기가 돌려준 보안 범위 URL은 업로드가 끝날 때까지 안정적으로 읽을 수 있도록
/// 앱 소유 임시 파일로 복사합니다.
nonisolated enum UploadFileKind: Equatable, Sendable {
    case furnitureGLB
    case roomUSDZ
    case roomJSON

    var fileExtension: String {
        switch self {
        case .furnitureGLB: "glb"
        case .roomUSDZ: "usdz"
        case .roomJSON: "json"
        }
    }

    var maximumBytes: Int64 {
        switch self {
        case .furnitureGLB, .roomUSDZ: 100 * 1_024 * 1_024
        case .roomJSON: 10 * 1_024 * 1_024
        }
    }

    var displayName: String {
        switch self {
        case .furnitureGLB: "GLB"
        case .roomUSDZ: "USDZ"
        case .roomJSON: "JSON"
        }
    }
}

nonisolated struct PreparedUploadFile: Equatable, Sendable {
    let url: URL
    let originalFileName: String
    let byteCount: Int64
}

nonisolated enum UploadFilePreparationError: LocalizedError, Equatable {
    case invalidExtension(expected: String)
    case emptyFile
    case fileTooLarge(kind: String, maximumMegabytes: Int)
    case invalidGLB
    case invalidUSDZ
    case invalidJSON
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case let .invalidExtension(expected):
            "\(expected.uppercased()) 파일만 선택할 수 있어요."
        case .emptyFile:
            "비어 있는 파일은 업로드할 수 없어요."
        case let .fileTooLarge(kind, maximumMegabytes):
            "\(kind) 파일은 최대 \(maximumMegabytes)MB까지 업로드할 수 있어요."
        case .invalidGLB:
            "올바른 GLB 2.0 파일이 아니에요."
        case .invalidUSDZ:
            "올바른 USDZ 파일이 아니에요."
        case .invalidJSON:
            "JSON 파일의 형식이 올바르지 않아요."
        case .unreadableFile:
            "선택한 파일을 읽을 수 없어요."
        }
    }
}

nonisolated enum UploadFilePreparation {
    static func prepare(sourceURL: URL, kind: UploadFileKind) async throws -> PreparedUploadFile {
        let worker = Task.detached(priority: .userInitiated) {
            try prepareSynchronously(sourceURL: sourceURL, kind: kind)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func remove(_ file: PreparedUploadFile?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file.url)
        let directory = file.url.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// 업로드 직후 방 목록에 감지 요소 개수를 표시하기 위한 best-effort 파싱입니다.
    /// 백엔드는 유효한 JSON이면 저장하므로, RoomPlan 키가 없는 JSON도 업로드 자체는 허용합니다.
    static func roomItemCount(at jsonURL: URL) async -> Int {
        let worker = Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: jsonURL),
                  let metadata = try? JSONDecoder().decode(RoomPlanExportJSON.self, from: data) else {
                return 0
            }
            return metadata.items().count
        }
        return await worker.value
    }

    private static func prepareSynchronously(
        sourceURL: URL,
        kind: UploadFileKind
    ) throws -> PreparedUploadFile {
        try Task.checkCancellation()
        guard sourceURL.pathExtension.lowercased() == kind.fileExtension else {
            throw UploadFilePreparationError.invalidExtension(expected: kind.fileExtension)
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let byteCount = try fileSize(at: sourceURL)
        guard byteCount > 0 else { throw UploadFilePreparationError.emptyFile }
        guard byteCount <= kind.maximumBytes else {
            throw UploadFilePreparationError.fileTooLarge(
                kind: kind.displayName,
                maximumMegabytes: Int(kind.maximumBytes / 1_024 / 1_024)
            )
        }

        switch kind {
        case .furnitureGLB:
            try validateGLB(at: sourceURL, byteCount: byteCount)
        case .roomUSDZ:
            try validateUSDZ(at: sourceURL)
        case .roomJSON:
            try validateJSON(at: sourceURL)
        }
        try Task.checkCancellation()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpatiumImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalFileName = sourceURL.lastPathComponent
        let destination = directory.appendingPathComponent(
            originalFileName.isEmpty ? "upload.\(kind.fileExtension)" : originalFileName
        )
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw UploadFilePreparationError.unreadableFile
        }

        return PreparedUploadFile(
            url: destination,
            originalFileName: originalFileName,
            byteCount: byteCount
        )
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else {
                throw UploadFilePreparationError.unreadableFile
            }
            return Int64(size)
        } catch let error as UploadFilePreparationError {
            throw error
        } catch {
            throw UploadFilePreparationError.unreadableFile
        }
    }

    private static func validateGLB(at url: URL, byteCount: Int64) throws {
        let header = try readHeader(at: url, count: 12)
        guard header.count == 12,
              Array(header.prefix(4)) == Array("glTF".utf8),
              littleEndianUInt32(header, offset: 4) == 2,
              Int64(littleEndianUInt32(header, offset: 8)) == byteCount else {
            throw UploadFilePreparationError.invalidGLB
        }
    }

    private static func validateUSDZ(at url: URL) throws {
        let header = try readHeader(at: url, count: 4)
        guard Array(header) == [0x50, 0x4B, 0x03, 0x04] else {
            throw UploadFilePreparationError.invalidUSDZ
        }
    }

    private static func validateJSON(at url: URL) throws {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw UploadFilePreparationError.invalidJSON
        }
    }

    private static func readHeader(at url: URL, count: Int) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: count) ?? Data()
        } catch {
            throw UploadFilePreparationError.unreadableFile
        }
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
