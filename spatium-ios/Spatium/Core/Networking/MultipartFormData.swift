import Foundation

struct MultipartFormPart {
    let name: String
    let data: Data
    var fileName: String?
    var contentType: String?
}

struct MultipartFormData {
    let boundary: String
    let body: Data

    init(parts: [MultipartFormPart], boundary: String = "Spatium-\(UUID().uuidString)") {
        self.boundary = boundary
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append("\(disposition)\r\n")
            if let contentType = part.contentType {
                body.append("Content-Type: \(contentType)\r\n")
            }
            body.append("\r\n")
            body.append(part.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        self.body = body
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
}
