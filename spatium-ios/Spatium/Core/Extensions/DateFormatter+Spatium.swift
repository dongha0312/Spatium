import Foundation

extension DateFormatter {
    static let roomRow: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M.d HH:mm"
        return formatter
    }()

    static let apiDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter
    }()
}
