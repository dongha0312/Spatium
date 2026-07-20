import Foundation

nonisolated extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
