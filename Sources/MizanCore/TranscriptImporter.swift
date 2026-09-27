import Foundation

/// يقرأ سجلات Claude Code و Cowork المحلية (قراءة فقط) ويحوّلها إلى فترات.
/// - وقت Claude: من رسالتك حتى آخر نشاط له في الدورة، ويُقطع عند فجوة أطول من `claudeGap`.
/// - وقتك (للتاريخ السابق فقط): تقديري — من انتهاء ردّ Claude حتى رسالتك التالية إذا كانت الفجوة قصيرة،
///   وإلا دقيقة واحدة لكتابة الرسالة. بعد بدء القياس الحيّ لا يُستخدم هذا التقدير.
public struct TranscriptImporter {
    public static let claudeGap: TimeInterval = 5 * 60
    public static let readingGap: TimeInterval = 10 * 60
    public static let composeTime: TimeInterval = 60

    public struct Event: Equatable {
        public var time: Date
        public var isHumanPrompt: Bool
    }

    let db: Database
    let home: URL

    public init(db: Database, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.db = db; self.home = home
    }

    /// أماكن السجلات لكل نوع.
    public func transcriptFiles() -> [(Kind, URL)] {
        var out: [(Kind, URL)] = []
        let fm = FileManager.default
        func jsonl(in dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
        func subdirs(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        // Claude Code: ~/.claude/projects/<مشروع>/<جلسة>.jsonl
        for p in subdirs(home.appendingPathComponent(".claude/projects")) {
            out += jsonl(in: p).map { (.code, $0) }
        }
        // Cowork: ~/Library/Application Support/Claude/local-agent-mode-sessions/<حساب>/<منظمة>/local_*/.claude/projects/<مشروع>/*.jsonl
        let cowork = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
        for a in subdirs(cowork) { for o in subdirs(a) { for s in subdirs(o) where s.lastPathComponent.hasPrefix("local_") {
            for p in subdirs(s.appendingPathComponent(".claude/projects")) {
                out += jsonl(in: p).map { (.cowork, $0) }
            }
        }}}
        return out
    }

    /// يستورد الملفات الجديدة أو المتغيّرة فقط. يعيد عدد الملفات المستوردة.
    @discardableResult
    public func importAll(liveSince: Date?) -> Int {
        var count = 0
        for (kind, url) in transcriptFiles() {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                  let size = (attrs[.size] as? NSNumber)?.int64Value else { continue }
            if let old = db.importedStamp(path: url.path), old.mtime == mtime, old.size == size { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let source = "transcript:\(url.path)"
            let items = Self.intervals(from: Self.parse(data), kind: kind, source: source, liveSince: liveSince)
            db.deleteIntervals(source: source)
            db.insert(items)
            db.setImportedStamp(path: url.path, mtime: mtime, size: size)
            count += 1
        }
        return count
    }

    // MARK: التحليل (دوال نقية قابلة للاختبار)

    public static func parse(_ data: Data) -> [Event] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var events: [Event] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let ts = obj["timestamp"] as? String, let time = iso.date(from: ts),
                  let type = obj["type"] as? String else { continue }
            if (obj["isSidechain"] as? Bool) == true { continue }
            let message = obj["message"] as? [String: Any]
            switch type {
            case "assistant":
                events.append(Event(time: time, isHumanPrompt: false))
            case "user":
                let content = message?["content"]
                let blocks = content as? [[String: Any]] ?? []
                let isToolResult = !blocks.isEmpty && blocks.allSatisfy { ($0["type"] as? String) == "tool_result" }
                if isToolResult { events.append(Event(time: time, isHumanPrompt: false)); continue }
                if (obj["isMeta"] as? Bool) == true { continue }
                let originKind = (obj["origin"] as? [String: Any])?["kind"] as? String
                let text = (content as? String) ?? blocks.compactMap { $0["text"] as? String }.first ?? ""
                // origin.kind = human في الإصدارات الحديثة؛ في القديمة نستبعد رسائل النظام المغلّفة بوسوم
                let human = originKind == "human" || (originKind == nil && !text.hasPrefix("<") && !text.isEmpty)
                if human { events.append(Event(time: time, isHumanPrompt: true)) }
            default:
                continue
            }
        }
        return events.sorted { $0.time < $1.time }
    }

    public static func intervals(from events: [Event], kind: Kind, source: String, liveSince: Date?) -> [Interval] {
        var out: [Interval] = []
        var segStart: Date?          // بداية دورة Claude الحالية
        var segLast: Date?           // آخر نشاط في الدورة
        var lastClaudeEnd: Date?     // نهاية آخر دورة مكتملة

        func closeSegment() {
            if let s = segStart, let l = segLast, l > s {
                out.append(Interval(kind: kind, actor: .claude, start: s, end: l, estimated: false, source: source))
            }
            if segStart != nil { lastClaudeEnd = segLast ?? segStart }
            segStart = nil; segLast = nil
        }

        for e in events {
            if e.isHumanPrompt {
                closeSegment()
                // تقدير وقتك: قراءة الرد + كتابة الرسالة
                var uStart = e.time.addingTimeInterval(-composeTime)
                if let prev = lastClaudeEnd, e.time.timeIntervalSince(prev) <= readingGap { uStart = prev }
                var uEnd = e.time
                if let live = liveSince { uEnd = min(uEnd, live) }
                if uEnd > uStart {
                    out.append(Interval(kind: kind, actor: .user, start: uStart, end: uEnd, estimated: true, source: source))
                }
                segStart = e.time; segLast = e.time
            } else if let last = segLast {
                if e.time.timeIntervalSince(last) <= claudeGap { segLast = e.time } else { closeSegment() }
            }
        }
        closeSegment()
        return out
    }
}
