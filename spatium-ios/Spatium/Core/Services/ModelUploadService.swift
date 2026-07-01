import Foundation

struct ModelUploadService {
    func uploadModel(endpoint: URL, metadataURL: URL, usdzFileURL: URL) async throws -> UploadResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        // 파일 업로드는 application/json이 아니라 multipart/form-data로 보내야 합니다.
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // Spring Boot의 @RequestPart("metadata")와 매칭되는 JSON 파일 파트입니다.
        try body.appendMultipartField(
            name: "metadata",
            fileName: metadataURL.lastPathComponent,
            contentType: "application/json",
            fileURL: metadataURL,
            boundary: boundary
        )
        // Spring Boot의 @RequestPart("file")와 매칭되는 USDZ 파일 파트입니다.
        try body.appendMultipartField(
            name: "file",
            fileName: usdzFileURL.lastPathComponent,
            contentType: "model/vnd.usdz+zip",
            fileURL: usdzFileURL,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            // 서버가 공통 응답 포맷으로 에러를 내려주면 message만 뽑아 보여줍니다.
            let message = (try? JSONDecoder().decode(UploadResponse.self, from: data).message)
                ?? String(data: data, encoding: .utf8)
            throw UploadError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        if data.isEmpty {
            return UploadResponse(
                statusCode: httpResponse.statusCode,
                message: "업로드 성공",
                data: UploadResponseData(modelId: nil, fileName: usdzFileURL.lastPathComponent, jsonFileName: metadataURL.lastPathComponent)
            )
        }

        if let decodedResponse = try? JSONDecoder().decode(UploadResponse.self, from: data) {
            return decodedResponse
        }

        // 서버가 아직 문자열만 반환해도 앱 화면에는 성공 메시지를 보여줄 수 있게 둡니다.
        let message = String(data: data, encoding: .utf8) ?? "업로드 성공"
        return UploadResponse(
            statusCode: httpResponse.statusCode,
            message: message,
            data: UploadResponseData(modelId: nil, fileName: usdzFileURL.lastPathComponent, jsonFileName: metadataURL.lastPathComponent)
        )
    }
}
