import Foundation

extension DateFormatter {
    static let roomRow: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M.d HH:mm"
        return formatter
    }()
}
