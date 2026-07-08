import Foundation

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(
        name: String,
        fileName: String? = nil,
        contentType: String,
        fileURL: URL,
        boundary: String
    ) throws {
        append("--\(boundary)\r\n")

        if let fileName {
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        } else {
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        }

        append("Content-Type: \(contentType)\r\n\r\n")
        append(try Data(contentsOf: fileURL))
        append("\r\n")
    }

    mutating func appendMultipartTextField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }
}
