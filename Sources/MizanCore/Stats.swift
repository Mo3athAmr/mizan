import Foundation

public enum Period: String, CaseIterable, Sendable {
    case day, week, month


    /// يوم بداية الشهر الذي يختاره المستخدم (1–31)؛ 1 يعني الشهر الميلادي المعتاد.
    /// إذا كان الشهر أقصر من اليوم المختار (مثل 31 في فبراير) يبدأ من آخر يوم فيه.
    public static var monthStartDay: Int {
        let v = UserDefaults.standard.integer(forKey: "monthStartDay")
        return (1...31).contains(v) ? v : 1
    }

    /// بداية دورة الشهر داخل شهر ميلادي معيّن، مع قصّ اليوم على طول ذلك الشهر.
    static func cycleStart(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let len = calendar.range(of: .day, in: .month, for: first)!.count
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, len)))!
    }

    /// الساعة التي يبدأ منها اليوم (0–23)؛ 0 يعني منتصف الليل. مثلاً 4 تجعل السهر حتى الفجر من اليوم السابق.
    public static var dayStartHour: Int {
        let v = UserDefaults.standard.integer(forKey: "dayStartHour")
        return (0...23).contains(v) ? v : 0
    }

    /// المدى الذي يحتوي التاريخ المعطى. الأسبوع يبدأ الأحد، والشهر يبدأ من اليوم الذي يختاره المستخدم،
    /// وكل الحدود تُزاح بساعة بداية اليوم.
    public func range(containing date: Date, calendar: Calendar = .mizan,
                      monthStartDay: Int = Period.monthStartDay,
                      dayStartHour: Int = Period.dayStartHour) -> (start: Date, end: Date) {
        guard dayStartHour > 0 else { return baseRange(containing: date, calendar: calendar, monthStartDay: monthStartDay) }
        let shifted = calendar.date(byAdding: .hour, value: -dayStartHour, to: date)!
        let r = baseRange(containing: shifted, calendar: calendar, monthStartDay: monthStartDay)
        return (calendar.date(byAdding: .hour, value: dayStartHour, to: r.start)!,
                calendar.date(byAdding: .hour, value: dayStartHour, to: r.end)!)
    }

    private func baseRange(containing date: Date, calendar: Calendar, monthStartDay: Int) -> (start: Date, end: Date) {
        if self == .month, monthStartDay > 1 {
            let c = calendar.dateComponents([.year, .month], from: date)
            var start = Self.cycleStart(year: c.year!, month: c.month!, day: monthStartDay, calendar: calendar)
            if date < start {
                let prev = calendar.date(byAdding: .month, value: -1, to: calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1))!)!
                let pc = calendar.dateComponents([.year, .month], from: prev)
                start = Self.cycleStart(year: pc.year!, month: pc.month!, day: monthStartDay, calendar: calendar)
            }
            let sc = calendar.dateComponents([.year, .month], from: start)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: DateComponents(year: sc.year, month: sc.month, day: 1))!)!
            let nc = calendar.dateComponents([.year, .month], from: nextMonth)
            return (start, Self.cycleStart(year: nc.year!, month: nc.month!, day: monthStartDay, calendar: calendar))
        }
        let comp: Calendar.Component = switch self { case .day: .day; case .week: .weekOfYear; case .month: .month }
        let iv = calendar.dateInterval(of: comp, for: date)!
        return (iv.start, iv.end)
    }
}

public extension Calendar {
    static var mizan: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ar")
        c.firstWeekday = 1   // بعد تعيين اللغة، لأنها تعيد ضبطه
        c.timeZone = .current
        return c
    }
}

public struct KindStats: Sendable {
    public var kind: Kind
    /// وقتك النشط أمام الشاشة.
    public var userTime: TimeInterval = 0
    /// الجزء التقديري من وقتك (مستنتج من السجلات لا مقاس لحظياً).
    public var estimatedUserTime: TimeInterval = 0
    /// وقت عمل Claude وأنت غائب عن أي قسم.
    public var claudeAloneTime: TimeInterval = 0
    public var sessionCount = 0
    public var averageSession: TimeInterval { sessionCount == 0 ? 0 : userTime / Double(sessionCount) }
}

public struct PeriodStats: Sendable {
    public var start: Date
    public var end: Date
    public var kinds: [Kind: KindStats]
    /// وقتك في كل ساعة من ساعات اليوم (0…23).
    public var hourly: [TimeInterval]
    public var totalUser: TimeInterval { kinds.values.reduce(0) { $0 + $1.userTime } }
    public var totalEstimated: TimeInterval { kinds.values.reduce(0) { $0 + $1.estimatedUserTime } }
    public var totalClaudeAlone: TimeInterval { kinds.values.reduce(0) { $0 + $1.claudeAloneTime } }
    public var peakHour: Int? {
        guard let m = hourly.max(), m > 0 else { return nil }
        return hourly.firstIndex(of: m)
    }
}

public enum Stats {
    /// الفجوة التي تفصل جلسة عن الأخرى.
    public static let sessionGap: TimeInterval = 5 * 60

    public typealias Span = (start: Date, end: Date)

    /// دمج الفترات المتداخلة أو المتلاصقة (ضمن `gap`).
    public static func union(_ spans: [Span], gap: TimeInterval = 0) -> [Span] {
        let sorted = spans.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var out: [Span] = []
        for s in sorted {
            if let last = out.last, s.start.timeIntervalSince(last.end) <= gap {
                out[out.count - 1].end = max(last.end, s.end)
            } else { out.append(s) }
        }
        return out
    }

    public static func total(_ spans: [Span]) -> TimeInterval {
        spans.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// طرح مجموعة فترات (مدموجة) من أخرى.
    public static func subtract(_ a: [Span], _ b: [Span]) -> [Span] {
        var out: [Span] = []
        for s in a {
            var pieces: [Span] = [s]
            for r in b where r.end > s.start && r.start < s.end {
                pieces = pieces.flatMap { p -> [Span] in
                    var res: [Span] = []
                    if r.start > p.start { res.append((p.start, min(p.end, r.start))) }
                    if r.end < p.end { res.append((max(p.start, r.end), p.end)) }
                    return res.filter { $0.end > $0.start }
                }
            }
            out += pieces
        }
        return out
    }

    static func clip(_ s: Span, _ from: Date, _ to: Date) -> Span? {
        let a = max(s.start, from), b = min(s.end, to)
        return b > a ? (a, b) : nil
    }

    public static func compute(_ intervals: [Interval], from: Date, to: Date, calendar: Calendar = .mizan) -> PeriodStats {
        var kinds: [Kind: KindStats] = [:]
        var hourly = Array(repeating: 0.0, count: 24)

        let allUser = union(intervals.filter { $0.actor == .user }.compactMap { clip(($0.start, $0.end), from, to) })

        for kind in Kind.allCases {
            var ks = KindStats(kind: kind)
            let mine = intervals.filter { $0.kind == kind }
            let user = mine.filter { $0.actor == .user }
            let userSpans = union(user.compactMap { clip(($0.start, $0.end), from, to) })
            ks.userTime = total(userSpans)
            // الجزء التقديري = ما لا تغطيه القياسات الحيّة
            let liveSpans = union(user.filter { !$0.estimated }.compactMap { clip(($0.start, $0.end), from, to) })
            ks.estimatedUserTime = total(subtract(userSpans, liveSpans))
            ks.sessionCount = union(userSpans, gap: sessionGap).count
            let claudeSpans = union(mine.filter { $0.actor == .claude }.compactMap { clip(($0.start, $0.end), from, to) })
            ks.claudeAloneTime = total(subtract(claudeSpans, allUser))
            kinds[kind] = ks

            for s in userSpans { addHourly(s, into: &hourly, calendar: calendar) }
        }
        return PeriodStats(start: from, end: to, kinds: kinds, hourly: hourly)
    }

    /// وقتك لكل يوم ولكل نوع داخل المدى (للرسم البياني الأسبوعي والشهري).
    public static func daily(_ intervals: [Interval], from: Date, to: Date, calendar: Calendar = .mizan) -> [(day: Date, kinds: [Kind: TimeInterval])] {
        var out: [(Date, [Kind: TimeInterval])] = []
        var d = from
        while d < to {
            let next = calendar.date(byAdding: .day, value: 1, to: d)!
            let s = compute(intervals, from: d, to: next, calendar: calendar)
            out.append((d, s.kinds.mapValues(\.userTime)))
            d = next
        }
        return out
    }

    static func addHourly(_ s: Span, into hourly: inout [TimeInterval], calendar: Calendar) {
        var t = s.start
        while t < s.end {
            let hourStart = calendar.dateInterval(of: .hour, for: t)!.start
            let next = min(s.end, hourStart.addingTimeInterval(3600))
            hourly[calendar.component(.hour, from: t)] += next.timeIntervalSince(t)
            t = next
        }
    }

    /// وقتك المتواصل حتى الآن (بلا انقطاع أطول من `breakGap`) — لتذكير الراحة.
    public static func currentStreak(_ intervals: [Interval], now: Date, breakGap: TimeInterval) -> Span? {
        let spans = union(intervals.filter { $0.actor == .user && !$0.estimated }.map { ($0.start, $0.end) }, gap: breakGap)
        guard let last = spans.last, now.timeIntervalSince(last.end) <= breakGap else { return nil }
        return last
    }
}

