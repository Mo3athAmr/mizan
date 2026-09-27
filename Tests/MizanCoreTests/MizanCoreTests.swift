import XCTest
@testable import MizanCore

final class MizanCoreTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    func testParseDistinguishesHumanFromToolAndMeta() {
        let lines = [
            #"{"type":"user","timestamp":"2026-09-20T10:00:00.000Z","origin":{"kind":"human"},"message":{"content":"مرحبا"}}"#,
            #"{"type":"assistant","timestamp":"2026-09-20T10:00:05.000Z","message":{"content":[]}}"#,
            #"{"type":"user","timestamp":"2026-09-20T10:00:06.000Z","message":{"content":[{"type":"tool_result"}]}}"#,
            #"{"type":"user","timestamp":"2026-09-20T10:00:07.000Z","isMeta":true,"message":{"content":"x"}}"#,
            #"{"type":"user","timestamp":"2026-09-20T10:00:08.000Z","origin":{"kind":"task-notification"},"message":{"content":"x"}}"#,
            #"{"type":"assistant","timestamp":"2026-09-20T10:00:09.000Z","isSidechain":true,"message":{"content":[]}}"#,
            #"not json"#,
        ].joined(separator: "\n")
        let ev = TranscriptImporter.parse(Data(lines.utf8))
        XCTAssertEqual(ev.map(\.isHumanPrompt), [true, false, false])
    }

    func testIntervalsFromEvents() {
        let ev: [TranscriptImporter.Event] = [
            .init(time: at(0), isHumanPrompt: true),
            .init(time: at(2), isHumanPrompt: false),
            .init(time: at(4), isHumanPrompt: false),   // Claude يعمل 0→4
            .init(time: at(7), isHumanPrompt: true),    // قرأتَ وكتبتَ 4→7
            .init(time: at(8), isHumanPrompt: false),
            .init(time: at(30), isHumanPrompt: false),  // فجوة طويلة: لا تُحسب
        ]
        let iv = TranscriptImporter.intervals(from: ev, kind: .code, source: "t", liveSince: nil)
        let claude = iv.filter { $0.actor == .claude }.map { ($0.start, $0.end) }
        let user = iv.filter { $0.actor == .user }
        XCTAssertEqual(claude.count, 2)
        XCTAssertEqual(claude[0].0, at(0)); XCTAssertEqual(claude[0].1, at(4))
        XCTAssertEqual(claude[1].0, at(7)); XCTAssertEqual(claude[1].1, at(8))
        XCTAssertEqual(user.count, 2)
        XCTAssertEqual(user[0].start, at(-1))      // أول رسالة: دقيقة كتابة
        XCTAssertEqual(user[1].start, at(4)); XCTAssertEqual(user[1].end, at(7))
        XCTAssertTrue(user.allSatisfy(\.estimated))
    }

    func testLiveSinceStopsEstimates() {
        let ev: [TranscriptImporter.Event] = [.init(time: at(10), isHumanPrompt: true)]
        let iv = TranscriptImporter.intervals(from: ev, kind: .cowork, source: "t", liveSince: at(0))
        XCTAssertTrue(iv.filter { $0.actor == .user }.isEmpty)
    }

    func testStatsSeparatesClaudeAloneAndSessions() {
        let iv = [
            Interval(kind: .code, actor: .user, start: at(0), end: at(10), estimated: false, source: "live"),
            Interval(kind: .code, actor: .user, start: at(12), end: at(20), estimated: false, source: "live"),
            Interval(kind: .code, actor: .user, start: at(60), end: at(70), estimated: true, source: "t"),
            Interval(kind: .code, actor: .claude, start: at(5), end: at(40), estimated: false, source: "t"),
        ]
        let s = Stats.compute(iv, from: at(0), to: at(120)).kinds[.code]!
        XCTAssertEqual(s.userTime, 28 * 60)
        XCTAssertEqual(s.estimatedUserTime, 10 * 60)
        XCTAssertEqual(s.sessionCount, 2)            // 0→20 جلسة واحدة (فجوة دقيقتين)، و60→70 ثانية
        XCTAssertEqual(s.claudeAloneTime, 22 * 60)   // 10→12 و 20→40
    }

    func testDatabaseRoundTripAndLiveExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try Database(url: url)
        db.extendOrInsertLive(kind: .chat, from: at(0), to: at(1), maxGap: 10)
        db.extendOrInsertLive(kind: .chat, from: at(1), to: at(2), maxGap: 10)
        db.extendOrInsertLive(kind: .chat, from: at(10), to: at(11), maxGap: 10)
        let rows = db.intervals(from: at(-1), to: at(20))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].end, at(2))
        db.setSetting("k", "v"); XCTAssertEqual(db.setting("k"), "v")
    }

    func testArabicDuration() {
        XCTAssertEqual((95.0 * 60).durationText(.ar), "\u{2067}1 س 35 د\u{2069}")
        XCTAssertEqual((95.0 * 60).durationText(.en), "1h 35m")
        XCTAssertEqual(hourLabel(13, .en), "1 PM")
    }

    func testSectionClassifier() {
        XCTAssertEqual(SectionClassifier.kind(forURL: "https://claude.ai/new"), .chat)
        XCTAssertEqual(SectionClassifier.kind(forURL: "https://claude.ai/chat/83cbbd14"), .chat)
        XCTAssertEqual(SectionClassifier.kind(forURL: "https://claude.ai/cowork/cse_01Kax"), .cowork)
        XCTAssertEqual(SectionClassifier.kind(forURL: "https://claude.ai/epitaxy/local_ccbaa0a9"), .code)
        XCTAssertNil(SectionClassifier.kind(forURL: "https://claude.ai/downloads"))
        XCTAssertNil(SectionClassifier.kind(forURL: "file:///Applications/Claude.app/index.html"))
        XCTAssertEqual(SectionClassifier.kind(forURL: "https://chatgpt.com/c/abc"), .chatgpt)
        XCTAssertEqual(SectionClassifier.kind(forURL: "https://gemini.google.com/app/123"), .gemini)
        XCTAssertNil(SectionClassifier.kind(forURL: "https://notchatgpt.com/"))
        XCTAssertNil(SectionClassifier.kind(forURL: "https://google.com/search?q=claude.ai"))
        XCTAssertEqual(SectionClassifier.kind(forBundleID: "com.openai.chat"), .chatgpt)
    }

    func testDailyAndStreak() {
        let iv = [Interval(kind: .chat, actor: .user, start: at(0), end: at(30), estimated: false, source: "live"),
                  Interval(kind: .chat, actor: .user, start: at(33), end: at(60), estimated: false, source: "live")]
        let streak = Stats.currentStreak(iv, now: at(61), breakGap: 5 * 60)
        XCTAssertEqual(streak?.start, at(0))
        XCTAssertNil(Stats.currentStreak(iv, now: at(70), breakGap: 5 * 60))
        let r = Period.week.range(containing: at(0))
        let days = Stats.daily(iv, from: r.start, to: r.end)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.reduce(0) { $0 + ($1.kinds[.chat] ?? 0) }, 57 * 60)
    }

    func testWeekStartsSunday() {
        let r = Period.week.range(containing: Date())
        XCTAssertEqual(Calendar.mizan.component(.weekday, from: r.start), 1)
    }

    func testCustomMonthStart() {
        let cal = Calendar.mizan
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10))!
        let r = Period.month.range(containing: d, calendar: cal, monthStartDay: 25)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r.start), DateComponents(month: 9, day: 25))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r.end), DateComponents(month: 10, day: 25))
        let e = cal.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let r2 = Period.month.range(containing: e, calendar: cal, monthStartDay: 25)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r2.start), DateComponents(month: 8, day: 25))
        let r3 = Period.month.range(containing: e, calendar: cal, monthStartDay: 1)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r3.start), DateComponents(month: 9, day: 1))
    }

    func testMonthStartBeyond28() {
        let cal = Calendar.mizan
        // 31 في فبراير يصبح آخر يوم فيه، ويعود إلى 31 في مارس
        let d = cal.date(from: DateComponents(year: 2027, month: 3, day: 10))!
        let r = Period.month.range(containing: d, calendar: cal, monthStartDay: 31)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r.start), DateComponents(month: 2, day: 28))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r.end), DateComponents(month: 3, day: 31))
        let e = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
        let r2 = Period.month.range(containing: e, calendar: cal, monthStartDay: 31)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r2.start), DateComponents(month: 10, day: 31))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r2.end), DateComponents(month: 11, day: 30))
        let f = cal.date(from: DateComponents(year: 2026, month: 9, day: 29))!
        let r3 = Period.month.range(containing: f, calendar: cal, monthStartDay: 30)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r3.start), DateComponents(month: 8, day: 30))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r3.end), DateComponents(month: 9, day: 30))
    }

    func testDayStartHour() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let late = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 2, minute: 30))!
        let r = Period.day.range(containing: late, calendar: cal, monthStartDay: 1, dayStartHour: 4)
        XCTAssertEqual(r.start, cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 4))!)
        XCTAssertEqual(r.end, cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 4))!)
        let morning = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 9))!
        XCTAssertEqual(Period.day.range(containing: morning, calendar: cal, monthStartDay: 1, dayStartHour: 4).start,
                       cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 4))!)
        XCTAssertEqual(Period.day.range(containing: late, calendar: cal, monthStartDay: 1, dayStartHour: 0).start,
                       cal.date(from: DateComponents(year: 2026, month: 9, day: 26))!)
    }
}
