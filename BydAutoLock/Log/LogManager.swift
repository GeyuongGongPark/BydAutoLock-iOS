import Foundation
import SQLite3


/// SQLite 기반 디버그 로그 저장소 (최대 5,000행)
final class LogManager {

    static let shared = LogManager()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "byd.log.queue", qos: .background)
    private static let maxRows = 5000

    private init() {
        openDatabase()
        createTable()
    }

    private func openDatabase() {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("byd_log.sqlite").path
        sqlite3_open(path, &db)
    }

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS logs (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                tag       TEXT NOT NULL,
                message   TEXT NOT NULL
            );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Write

    func log(_ tag: String, _ message: String) {
        guard StorageManager.shared.isDebugLoggingEnabled else { return }
        queue.async { [weak self] in
            self?.insertLog(tag: tag, message: message)
        }
    }

    private func insertLog(tag: String, message: String) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO logs (timestamp, tag, message) VALUES (?, ?, ?)", -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, ts)
        sqlite3_bind_text(stmt, 2, tag, -1, nil)
        sqlite3_bind_text(stmt, 3, message, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        // 최대 행 수 초과 시 오래된 항목 제거
        var countStmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM logs", -1, &countStmt, nil)
        if sqlite3_step(countStmt) == SQLITE_ROW {
            let count = Int(sqlite3_column_int64(countStmt, 0))
            if count > Self.maxRows {
                sqlite3_exec(db,
                    "DELETE FROM logs WHERE id IN (SELECT id FROM logs ORDER BY id ASC LIMIT \(count - Self.maxRows))",
                    nil, nil, nil)
            }
        }
        sqlite3_finalize(countStmt)
    }

    // MARK: - Read

    func fetchLogs(limit: Int = 500, tag: String? = nil) -> [LogEntry] {
        var entries = [LogEntry]()
        var stmt: OpaquePointer?

        if let t = tag, !t.isEmpty {
            sqlite3_prepare_v2(db, "SELECT id, timestamp, tag, message FROM logs WHERE tag LIKE ? ORDER BY id DESC LIMIT ?", -1, &stmt, nil)
            let pattern = "%\(t)%"
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
        } else {
            sqlite3_prepare_v2(db, "SELECT id, timestamp, tag, message FROM logs ORDER BY id DESC LIMIT ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(limit))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id  = sqlite3_column_int64(stmt, 0)
            let ts  = sqlite3_column_int64(stmt, 1)
            let tagStr = String(cString: sqlite3_column_text(stmt, 2))
            let msg    = String(cString: sqlite3_column_text(stmt, 3))
            let date   = Date(timeIntervalSince1970: Double(ts) / 1000.0)
            entries.append(LogEntry(id: id, timestamp: date, tag: tagStr, message: msg))
        }
        sqlite3_finalize(stmt)
        return entries
    }

    func clearAll() {
        queue.async { [weak self] in
            sqlite3_exec(self?.db, "DELETE FROM logs", nil, nil, nil)
        }
    }
}
