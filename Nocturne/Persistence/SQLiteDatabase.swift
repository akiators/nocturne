import Foundation
import SQLite3

/// Минимальная обёртка над sqlite3 (системная библиотека iOS, без зависимостей).
/// Потокобезопасность: все вызовы выполняются снаружи; LibraryStore сериализует доступ.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "app.nocturne.sqlite")

    static let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard code == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw NSError(domain: "SQLite", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func execute(_ sql: String) throws {
        try queue.sync {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let code = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
            if code != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
                sqlite3_free(errorMessage)
                throw NSError(domain: "SQLite", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
    }

    func run(_ sql: String, _ bind: (Statement) -> Void) throws {
        try queue.sync {
            let statement = try Statement(db: handle, sql: sql)
            defer { statement.finalize() }
            bind(statement)
            let code = sqlite3_step(statement.raw)
            guard code == SQLITE_DONE || code == SQLITE_ROW else {
                throw Self.error(from: handle, code: code)
            }
        }
    }

    func query(_ sql: String, read: (Statement) -> Void, bind: (Statement) -> Void = { _ in }) throws {
        try queue.sync {
            let statement = try Statement(db: handle, sql: sql)
            defer { statement.finalize() }
            bind(statement)
            while true {
                let code = sqlite3_step(statement.raw)
                if code == SQLITE_ROW { read(statement) }
                else if code == SQLITE_DONE { break }
                else { throw Self.error(from: handle, code: code) }
            }
        }
    }

    private static func error(from db: OpaquePointer?, code: Int32) -> NSError {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return NSError(domain: "SQLite", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
    }

    final class Statement {
        let raw: OpaquePointer

        init(db: OpaquePointer, sql: String) throws {
            var stmt: OpaquePointer?
            let code = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard code == SQLITE_OK, let stmt else {
                let message = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "SQLite", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
            }
            raw = stmt
        }

        func finalize() { sqlite3_finalize(raw) }

        // Bind (индексы с 1)
        func bindText(_ index: Int32, _ value: String?) {
            if let value {
                sqlite3_bind_text(raw, index, value, -1, SQLiteDatabase.transient)
            } else {
                sqlite3_bind_null(raw, index)
            }
        }
        func bindDouble(_ index: Int32, _ value: Double) { sqlite3_bind_double(raw, index, value) }
        func bindInt(_ index: Int32, _ value: Int64) { sqlite3_bind_int64(raw, index, value) }
        func bindBlob(_ index: Int32, _ value: Data) {
            value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(raw, index, buffer.baseAddress, Int32(buffer.count), SQLiteDatabase.transient)
            }
        }
        func bindNull(_ index: Int32) { sqlite3_bind_null(raw, index) }

        // Read (индексы с 0)
        func text(_ index: Int32) -> String? {
            guard let cString = sqlite3_column_text(raw, index) else { return nil }
            return String(cString: cString)
        }
        func double(_ index: Int32) -> Double { sqlite3_column_double(raw, index) }
        func int(_ index: Int32) -> Int64 { sqlite3_column_int64(raw, index) }
        func bool(_ index: Int32) -> Bool { sqlite3_column_int64(raw, index) != 0 }
        func blob(_ index: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(raw, index) else { return nil }
            let count = Int(sqlite3_column_bytes(raw, index))
            return Data(bytes: bytes, count: count)
        }
    }
}
