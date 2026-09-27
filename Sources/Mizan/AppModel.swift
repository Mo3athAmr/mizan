import AppKit
import MizanCore
import ServiceManagement
import SwiftUI
import UserNotifications

/// الإعدادات القابلة للتعديل (محفوظة محلياً في UserDefaults). الواجهة تعدّلها عبر @AppStorage بالمفاتيح نفسها.
struct Settings {
    static let defaults: [String: Any] = [
        "idleMinutes": 2.0, "breakMinutes": 50.0, "breakEnabled": true,
        "dailyLimitHours": 6.0, "dailyLimitEnabled": true, "weeklySummaryEnabled": true,
    ]
    private var d: UserDefaults { .standard }
    var idleMinutes: Double { d.double(forKey: "idleMinutes") }
    var breakMinutes: Double { d.double(forKey: "breakMinutes") }
    var breakEnabled: Bool { d.bool(forKey: "breakEnabled") }
    var dailyLimitHours: Double { d.double(forKey: "dailyLimitHours") }
    var dailyLimitEnabled: Bool { d.bool(forKey: "dailyLimitEnabled") }
    var weeklySummaryEnabled: Bool { d.bool(forKey: "weeklySummaryEnabled") }
}

@MainActor
final class AppModel: ObservableObject {
    let db: Database
    let settings = Settings()
    private var tracker: Tracker!
    private var importTimer: Timer?
    private var refreshTimer: Timer?

    @Published var today: PeriodStats
    @Published var currentKind: Kind?
    @Published var continuous: TimeInterval = 0
    @Published var week: PeriodStats
    @Published var month: PeriodStats
    /// للخطوط الزمنية الصغيرة في القائمة: ساعة بساعة لليوم، ويوماً بيوم للأسبوع والشهر — لكل قسم.
    @Published var sparks: [Period: [Kind: [TimeInterval]]] = [:]
    /// أرشيف الأشهر المنتهية — لقطة ثابتة تُحفظ مرة واحدة كمرجع.
    @Published var archive: [MonthRecord] = []
    private var streakStart: Date?
    @Published var hasAccessibility = Tracker.hasAccessibility
    @Published var importing = false
    @Published var lastImportCount = 0

    init() {
        UserDefaults.standard.register(defaults: Settings.defaults)
        db = try! Database()
        let r = Period.day.range(containing: Date())
        let empty = Stats.compute([], from: r.start, to: r.end)
        today = empty
        week = empty
        month = empty
        tracker = Tracker(db: db) { [settings] in settings.idleMinutes * 60 }
        tracker.onTick = { [weak self] kind in
            Task { @MainActor in
                self?.currentKind = kind
                self?.hasAccessibility = Tracker.hasAccessibility
            }
        }
        if CommandLine.arguments.contains("--render-icon") {
            DispatchQueue.main.async { RenderCheck.renderIconIfRequested() }
            return
        }
        if CommandLine.arguments.contains("--render-check") {
            _ = TranscriptImporter(db: db).importAll(liveSince: liveSince)
            refresh()
            DispatchQueue.main.async { [self] in RenderCheck.runIfRequested(model: self) }
            return
        }
        tracker.start()
        refresh()
        runImport()
        importTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runImport() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(); self?.checkAlerts() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var liveSince: Date? {
        db.setting("live_since").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    }

    func stats(_ period: Period, containing date: Date) -> PeriodStats {
        let r = period.range(containing: date)
        return Stats.compute(db.intervals(from: r.start, to: r.end), from: r.start, to: r.end)
    }

    func intervals(_ period: Period, containing date: Date) -> [Interval] {
        let r = period.range(containing: date)
        return db.intervals(from: r.start, to: r.end)
    }

    func refresh() {
        hasAccessibility = Tracker.hasAccessibility
        let now = Date()
        func load(_ p: Period) -> (PeriodStats, [Interval]) {
            let r = p.range(containing: now)
            let iv = db.intervals(from: r.start, to: r.end)
            return (Stats.compute(iv, from: r.start, to: r.end), iv)
        }
        let (d, dayIv) = load(.day), (w, weekIv) = load(.week), (m, monthIv) = load(.month)
        today = d; week = w; month = m
        var sp: [Period: [Kind: [TimeInterval]]] = [:]
        sp[.day] = Dictionary(uniqueKeysWithValues: Kind.allCases.map { k in
            (k, Stats.compute(dayIv.filter { $0.kind == k }, from: d.start, to: d.end).hourly)
        })
        let tomorrow = d.end
        for (p, st, iv) in [(Period.week, w, weekIv), (Period.month, m, monthIv)] {
            let days = Stats.daily(iv, from: st.start, to: min(st.end, tomorrow))
            sp[p] = Dictionary(uniqueKeysWithValues: Kind.allCases.map { k in (k, days.map { $0.kinds[k] ?? 0 }) })
        }
        sparks = sp
        archiveCompletedMonths(now: now)
        let recent = db.intervals(from: Date().addingTimeInterval(-12 * 3600), to: Date())
        let streak = Stats.currentStreak(recent, now: Date(), breakGap: 5 * 60)
        streakStart = streak?.start
        continuous = streak.map { $0.end.timeIntervalSince($0.start) } ?? 0
    }

    func runImport() {
        guard !importing else { return }
        importing = true
        let db = db, since = liveSince
        Task.detached(priority: .utility) {
            let n = TranscriptImporter(db: db).importAll(liveSince: since)
            await MainActor.run { self.importing = false; self.lastImportCount = n; self.refresh() }
        }
    }

    // MARK: التنبيهات الصحية

    private func notify(_ id: String, _ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    func checkAlerts(now: Date = Date()) {
        // تذكير الراحة: مرة واحدة لكل فترة متواصلة
        if settings.breakEnabled, continuous >= settings.breakMinutes * 60, let s = streakStart {
            let streakKey = "break_notified_\(Int(s.timeIntervalSince1970))"
            if db.setting(streakKey) == nil {
                db.setSetting(streakKey, "1")
                notify("break", tr("وقت الراحة 🌿", "Time for a break 🌿"),
                       tr("عملتَ \(continuous.durationText()) متواصلة. قم وتحرّك، وأرح عينيك: انظر لشيء بعيد 20 ثانية.",
                          "You've worked \(continuous.durationText()) straight. Stand up, move, and rest your eyes: look at something far away for 20 seconds."))
            }
        }
        // الحد اليومي: مرة واحدة في اليوم
        let dayKey = "limit_notified_" + ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: .withFullDate)
        if settings.dailyLimitEnabled, today.totalUser >= settings.dailyLimitHours * 3600, db.setting(dayKey) == nil {
            db.setSetting(dayKey, "1")
            notify("limit", tr("تجاوزتَ حدّك اليومي", "You passed your daily limit"),
                   tr("وقتك مع Claude اليوم \(today.totalUser.durationText())، والحد الذي اخترته \((settings.dailyLimitHours * 3600).durationText()).",
                      "Your time with Claude today is \(today.totalUser.durationText()); your limit is \((settings.dailyLimitHours * 3600).durationText())."))
        }
        // الملخص الأسبوعي: أول مرة يعمل فيها التطبيق في أسبوع جديد، عن الأسبوع السابق
        if settings.weeklySummaryEnabled {
            let thisWeek = Period.week.range(containing: now).start
            let key = "weekly_\(Int(thisWeek.timeIntervalSince1970))"
            if db.setting(key) == nil {
                db.setSetting(key, "1")
                let prev = stats(.week, containing: thisWeek.addingTimeInterval(-3600))
                if prev.totalUser > 0 {
                    let parts = Kind.allCases.compactMap { k -> String? in
                        guard let s = prev.kinds[k], s.userTime > 0 else { return nil }
                        return "\(k.displayName()): \(s.userTime.durationText())"
                    }
                    notify("weekly", tr("ملخص أسبوعك مع Claude", "Your week with Claude"),
                           tr("المجموع ", "Total ") + prev.totalUser.durationText() + " — " + parts.joined(separator: tr("، ", ", ")))
                }
            }
        }
    }

    // MARK: أرشيف الأشهر

    /// يحفظ لقطة ثابتة لكل شهر انتهى (حتى 12 شهراً للخلف) مرة واحدة، لتبقى مرجعاً
    /// حتى لو أُعيدت قراءة السجلات أو تغيّرت التقديرات لاحقاً.
    func archiveCompletedMonths(now: Date = Date()) {
        let startDay = Period.monthStartDay
        var cursor = Period.month.range(containing: now).start
        for _ in 0..<12 {
            let prev = Period.month.range(containing: cursor.addingTimeInterval(-3600))
            cursor = prev.start
            let key = "archive_month_\(Int(prev.start.timeIntervalSince1970))_\(startDay)"
            if db.setting(key) != nil { continue }
            let st = Stats.compute(db.intervals(from: prev.start, to: prev.end), from: prev.start, to: prev.end)
            guard st.totalUser > 0 else { continue }
            let rec = MonthRecord(start: prev.start, end: prev.end, startDay: startDay,
                                  kinds: Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0.rawValue, st.kinds[$0]?.userTime ?? 0) }),
                                  claudeAlone: st.totalClaudeAlone,
                                  sessions: st.kinds.values.reduce(0) { $0 + $1.sessionCount },
                                  savedAt: now)
            if let data = try? JSONEncoder().encode(rec), let json = String(data: data, encoding: .utf8) {
                db.setSetting(key, json)
            }
        }
        archive = db.settings(prefix: "archive_month_")
            .compactMap { try? JSONDecoder().decode(MonthRecord.self, from: Data($0.value.utf8)) }
            .filter { $0.startDay == startDay }
            .sorted { $0.start > $1.start }
    }

    /// يعيد تشغيل التطبيق (بعض إصدارات macOS لا تُحدّث حالة صلاحية Accessibility للعملية الجارية).
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: التشغيل عند الإقلاع

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}

/// لقطة محفوظة لشهر منتهٍ.
struct MonthRecord: Codable, Identifiable, Hashable {
    var start: Date
    var end: Date
    var startDay: Int
    var kinds: [String: TimeInterval]
    var claudeAlone: TimeInterval
    var sessions: Int
    var savedAt: Date
    var id: Date { start }
    var total: TimeInterval { kinds.values.reduce(0, +) }
    func time(_ k: Kind) -> TimeInterval { kinds[k.rawValue] ?? 0 }
}
