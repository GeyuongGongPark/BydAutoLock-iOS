import Foundation

struct LogEntry: Identifiable {
    let id: Int64
    let timestamp: Date
    let tag: String
    let message: String

    var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm:ss"
        return fmt.string(from: timestamp)
    }
}
