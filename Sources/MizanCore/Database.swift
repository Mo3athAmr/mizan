import Foundation
import SQLite3

/// مكان الاستخدام: أقسام Claude الثلاثة، وأدوات الذكاء الاصطناعي الأخرى.
public enum Kind: String, CaseIterable, Sendable {
    case chat, cowork, code, chatgpt, gemini

    public static let claudeSections: [Kind] = [.chat, .cowork, .code]
    public static let otherTools: [Kind] = [.chatgpt, .gemini]
    public var isClaude: Bool { Kind.claudeSections.contains(self) }
}

/// من صاحب هذا الوقت: المستخدم أمام الشاشة، أم Claude يعمل وحده.
public enum Actor: String, Sendable {
    case user, claude
}

/// فترة زمنية مسجّلة.
public struct Interval: Equatable, Sendable {
    public var kind: Kind
    public var actor: Actor
    public var start: Date
    public var end: Date
    /// true إذا كانت مستنتجة من السجلات وليست مقاسة لحظياً.
    public var estimated: Bool
    public var source: String

    public init(kind: Kind, actor: Actor, start: Date, end: Date, estimated: Bool, source: String) {
        self.kind = kind; self.actor = actor; self.start = start; self.end = end
        self.estimated = estimated; self.source = source
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public enum DBError: Error { case open(String), exec(String) }

/// غلاف بسيط فوق SQLite المدمجة في النظام. لا مكتبات خارجية.
public final class Database: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mizan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mizan.sqlite")
    }

    public init(url: URL = Database.defaultURL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw DBError.open(url.path) }
        try exec("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS intervals(
            id INTEGER PRIMARY KEY,
            kind TEXT NOT NULL, actor TEXT NOT NULL,
            start REAL NOT NULL, end REAL NOT NULL,
            estimated INTEGER NOT NULL, source TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_intervals_start ON intervals(start);
        CREATE INDEX IF NOT EXISTS idx_intervals_source ON intervals(source);
        CREATE TABLE IF NOT EXISTS imported_files(path TEXT PRIMARY KEY, mtime REAL, size INTEGER);
        CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT);
        """)
    }

    deinit { sqlite3_close(db) }

    public func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &st, nil)
        return st
    }

    // MARK: الفترات

    public func insert(_ items: [Interval]) {
        lock.lock(); defer { lock.unlock() }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        let st = prepare("INSERT INTO intervals(kind,actor,start,end,estimated,source) VALUES(?,?,?,?,?,?)")
        for i in items {
            sqlite3_bind_text(st, 1, i.kind.rawValue, -1, Self.transient)
            sqlite3_bind_text(st, 2, i.actor.rawValue, -1, Self.transient)
            sqlite3_bind_double(st, 3, i.start.timeIntervalSince1970)
            sqlite3_bind_double(st, 4, i.end.timeIntervalSince1970)
            sqlite3_bind_int(st, 5, i.estimated ? 1 : 0)
            sqlite3_bind_text(st, 6, i.source, -1, Self.transient)
            sqlite3_step(st); sqlite3_reset(st)
        }
        sqlite3_finalize(st)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    /// يمدّ نهاية آخر فترة حيّة إذا كانت متصلة، وإلا يضيف فترة جديدة. يُستخدم من محرّك القياس كل بضع ثوانٍ.
    public func extendOrInsertLive(kind: Kind, from start: Date, to end: Date, maxGap: TimeInterval) {
        lock.lock()
        let st = prepare("SELECT id, end FROM intervals WHERE source='live' AND actor='user' AND kind=? ORDER BY end DESC LIMIT 1")
        sqlite3_bind_text(st, 1, kind.rawValue, -1, Self.transient)
        var lastID: Int64?; var lastEnd = 0.0
        if sqlite3_step(st) == SQLITE_ROW { lastID = sqlite3_column_int64(st, 0); lastEnd = sqlite3_column_double(st, 1) }
        sqlite3_finalize(st)
        if let id = lastID, start.timeIntervalSince1970 - lastEnd <= maxGap, start.timeIntervalSince1970 >= lastEnd - 1 {
            let up = prepare("UPDATE intervals SET end=? WHERE id=?")
            sqlite3_bind_double(up, 1, end.timeIntervalSince1970)
            sqlite3_bind_int64(up, 2, id)
            sqlite3_step(up); sqlite3_finalize(up)
            lock.unlock()
        } else {
            lock.unlock()
            insert([Interval(kind: kind, actor: .user, start: start, end: end, estimated: false, source: "live")])
        }
    }

    public func deleteIntervals(source: String) {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("DELETE FROM intervals WHERE source=?")
        sqlite3_bind_text(st, 1, source, -1, Self.transient)
        sqlite3_step(st); sqlite3_finalize(st)
    }

    /// كل الفترات التي تتقاطع مع المدى المطلوب.
    public func intervals(from: Date, to: Date) -> [Interval] {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("SELECT kind,actor,start,end,estimated,source FROM intervals WHERE end>? AND start<? ORDER BY start")
        sqlite3_bind_double(st, 1, from.timeIntervalSince1970)
        sqlite3_bind_double(st, 2, to.timeIntervalSince1970)
        var out: [Interval] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let k = Kind(rawValue: String(cString: sqlite3_column_text(st, 0))),
                  let a = Actor(rawValue: String(cString: sqlite3_column_text(st, 1))) else { continue }
            out.append(Interval(kind: k, actor: a,
                                start: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
                                end: Date(timeIntervalSince1970: sqlite3_column_double(st, 3)),
                                estimated: sqlite3_column_int(st, 4) == 1,
                                source: String(cString: sqlite3_column_text(st, 5))))
        }
        sqlite3_finalize(st)
        return out
    }

    // MARK: الملفات المستوردة

    public func importedStamp(path: String) -> (mtime: Double, size: Int64)? {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("SELECT mtime,size FROM imported_files WHERE path=?")
        sqlite3_bind_text(st, 1, path, -1, Self.transient)
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return (sqlite3_column_double(st, 0), sqlite3_column_int64(st, 1))
    }

    public func setImportedStamp(path: String, mtime: Double, size: Int64) {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("INSERT OR REPLACE INTO imported_files(path,mtime,size) VALUES(?,?,?)")
        sqlite3_bind_text(st, 1, path, -1, Self.transient)
        sqlite3_bind_double(st, 2, mtime)
        sqlite3_bind_int64(st, 3, size)
        sqlite3_step(st); sqlite3_finalize(st)
    }

    // MARK: الإعدادات

    public func setting(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("SELECT value FROM settings WHERE key=?")
        sqlite3_bind_text(st, 1, key, -1, Self.transient)
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return nil }
        return String(cString: c)
    }

    /// كل الإعدادات التي يبدأ مفتاحها بالبادئة (مثل أرشيف الأشهر).
    public func settings(prefix: String) -> [(key: String, value: String)] {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("SELECT key, value FROM settings WHERE key LIKE ? ORDER BY key")
        sqlite3_bind_text(st, 1, prefix + "%", -1, Self.transient)
        defer { sqlite3_finalize(st) }
        var out: [(String, String)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            if let k = sqlite3_column_text(st, 0), let v = sqlite3_column_text(st, 1) {
                out.append((String(cString: k), String(cString: v)))
            }
        }
        return out
    }

    public func setSetting(_ key: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        let st = prepare("INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)")
        sqlite3_bind_text(st, 1, key, -1, Self.transient)
        sqlite3_bind_text(st, 2, value, -1, Self.transient)
        sqlite3_step(st); sqlite3_finalize(st)
    }
}
