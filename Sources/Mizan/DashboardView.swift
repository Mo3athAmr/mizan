import Charts
import MizanCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var pal
    @State private var period: Period = .day
    @State private var date = Date()
    /// للفحص فقط: عرض المحتوى بلا تمرير حتى يُرسم إلى صورة.
    var scrolls = true

    var body: some View {
        let intervals = model.intervals(period, containing: date)
        let r = period.range(containing: date)
        let stats = Stats.compute(intervals, from: r.start, to: r.end)
        let page = VStack(alignment: .leading, spacing: 0) {
                toolbar(stats: stats, intervals: intervals)
                ReportContent(stats: stats, intervals: intervals, period: period, liveSince: model.liveSince)
                    .padding(.top, 22)
                if period == .month && !model.archive.isEmpty {
                    PastMonths(records: model.archive).padding(.top, 16)
                }
        }
            .padding(.horizontal, 32)
            .padding(.top, 38)
            .padding(.bottom, 32)
        return Group {
            if scrolls { ScrollView { page } } else { page }
        }
        .background(GlowBackground())
        .frame(minWidth: 760, minHeight: 640)
        .onAppear { model.runImport() }
    }

    private func toolbar(stats: PeriodStats, intervals: [Interval]) -> some View {
        GlassGroup(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                LiveBrandLogo(size: 22).padding(9).glassCapsule()
                TabBar(items: Period.allCases.map { ($0, $0.displayName()) }, selection: $period)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.backward") }.buttonStyle(QuietButton())
                Button(tr("الحالي", "Now")) { date = Date() }.buttonStyle(QuietButton())
                Button { shift(1) } label: { Image(systemName: "chevron.forward") }.buttonStyle(QuietButton())
                Button("PDF") {
                    Exporter.exportPDF(stats: stats, intervals: intervals, period: period, liveSince: model.liveSince)
                }
                .buttonStyle(QuietButton(primary: true)).help(tr("تصدير تقرير PDF", "Export PDF report"))
                Button("CSV") { Exporter.exportCSV(stats: stats, intervals: intervals, period: period) }
                    .buttonStyle(QuietButton()).help(tr("تصدير جدول CSV", "Export CSV table"))
            }
        }
    }

    private func shift(_ n: Int) {
        let comp: Calendar.Component = switch period { case .day: .day; case .week: .weekOfYear; case .month: .month }
        date = Calendar.mizan.date(byAdding: comp, value: n, to: date) ?? date
    }
}

/// محتوى التقرير — يُستخدم في اللوحة وفي ملف PDF (مع لوحة ألوان الورق).
struct ReportContent: View {
    @Environment(\.palette) private var pal
    let stats: PeriodStats
    let intervals: [Interval]
    let period: Period
    let liveSince: Date?
    var compact = false

    var body: some View {
        GlassGroup(spacing: 16) {
            VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                hero.panel(pal, tint: pal.gold.opacity(0.10))
                DayClock(stats: stats, intervals: intervals, period: period, compact: compact).panel(pal)
                insights.panel(pal, padding: 0)
                columns("Claude", Kind.claudeSections).panel(pal)
                if Kind.otherTools.contains(where: { (stats.kinds[$0]?.userTime ?? 0) > 0 }) {
                    columns(tr("أدوات أخرى", "Other tools"), Kind.otherTools).panel(pal)
                }
                chart.panel(pal)
                AccuracyNote(liveSince: liveSince).panel(pal)
                DeveloperCredit().padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(title)
                Text(stats.totalUser.durationText()).font(.display(compact ? 54 : 68)).monospacedDigit()
                Text(tr("وقتك النشط مع الذكاء الاصطناعي", "Your active time with AI")).font(.mz(13)).foregroundStyle(pal.muted)
            }
            Spacer(minLength: 24)
            HStack(spacing: 28) {
                figure(tr("عمل الوكيل وأنت غائب", "Agent work while you're away"), stats.totalClaudeAlone.durationText())
                    .help(tr("وقت اشتغل فيه Claude على مهمتك وأنت بعيد عن الشاشة، ولا يُحسب من وقتك", "Time Claude worked on your task while you were away from the screen — not counted in your time"))
                if stats.totalEstimated > 0 {
                    Hairline(vertical: true).frame(height: 40)
                    figure(tr("منه تقديري", "Estimated"), stats.totalEstimated.durationText(), gold: true)
                }
            }
        }
    }

    private func figure(_ t: String, _ v: String, gold: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.mz(11)).foregroundStyle(pal.muted)
            Text(v).font(.display(24)).monospacedDigit().foregroundStyle(gold ? pal.gold : pal.text)
        }
    }

    private func columns(_ heading: String, _ kinds: [Kind]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(heading)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
                    if i > 0 { Hairline(vertical: true).padding(.horizontal, 22) }
                    KindColumn(kind: k, s: stats.kinds[k]!)
                }
                if kinds.count < 3 {
                    Hairline(vertical: true).padding(.horizontal, 22).opacity(0)
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var chart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(period == .day ? tr("على مدار اليوم", "Across the day") : tr("يوماً بيوم", "Day by day"))
            if period == .day {
                Chart(Array(stats.hourly.enumerated()), id: \.offset) { h, v in
                    BarMark(x: .value("h", h), y: .value("m", v / 60), width: .fixed(compact ? 9 : 14))
                        .foregroundStyle(pal.gold)
                        .cornerRadius(2)
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis { AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { v in
                    AxisValueLabel { Text(hourLabel(v.as(Int.self) ?? 0)).font(.mz(10)).foregroundStyle(pal.muted) }
                } }
                .chartYAxis { AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(pal.line)
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.mz(10)).foregroundStyle(pal.faint) }
                } }
                .frame(height: compact ? 130 : 170)
            } else {
                let days = Stats.daily(intervals, from: stats.start, to: stats.end)
                Chart {
                    ForEach(days, id: \.day) { d in
                        ForEach(Kind.allCases, id: \.self) { k in
                            BarMark(x: .value("d", d.day, unit: .day), y: .value("h", (d.kinds[k] ?? 0) / 3600), width: .ratio(0.55))
                                .foregroundStyle(by: .value("k", k.displayName()))
                        }
                    }
                }
                .chartForegroundStyleScale(domain: Kind.allCases.map { $0.displayName() }, range: Kind.allCases.map(\.color))
                .chartLegend(position: .bottom, alignment: .leading) {
                    HStack(spacing: 14) {
                        ForEach(Kind.allCases, id: \.self) { k in
                            HStack(spacing: 5) {
                                Circle().fill(k.color).frame(width: 6, height: 6)
                                Text(k.displayName()).font(.mz(10)).foregroundStyle(pal.muted)
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(d.formatted(.dateTime.day().month(.abbreviated).locale(Lang.current.locale)))
                                .font(.mz(10)).foregroundStyle(pal.muted)
                        }
                    }
                } }
                .chartYAxis { AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(pal.line)
                    AxisValueLabel { Text(String(format: "%.1f", v.as(Double.self) ?? 0)).font(.mz(10)).foregroundStyle(pal.faint) }
                } }
                .frame(height: compact ? 150 : 190)
            }
        }
    }

    private var insights: some View {
        let sessions = stats.kinds.values.reduce(0) { $0 + $1.sessionCount }
        let avg = sessions == 0 ? 0 : stats.totalUser / Double(sessions)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                insight(tr("أكثر ساعة استخداماً", "Peak hour"), stats.peakHour.map { hourLabel($0) } ?? "—")
                Hairline(vertical: true)
                insight(tr("الجلسات", "Sessions"), "\(sessions)")
                Hairline(vertical: true)
                insight(tr("متوسط الجلسة", "Avg. session"), avg.durationText())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func insight(_ t: String, _ v: String) -> some View {
        VStack(spacing: 6) {
            Text(t).font(.mz(11)).foregroundStyle(pal.muted)
            Text(v).font(.display(22)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var title: String {
        let f = DateFormatter(); f.locale = Lang.current.locale; f.calendar = .mizan
        switch period {
        case .day: f.dateFormat = "EEEE d MMMM"; return f.string(from: stats.start)
        case .week:
            f.dateFormat = "d MMMM"
            return "\(f.string(from: stats.start)) – \(f.string(from: stats.end.addingTimeInterval(-1)))"
        case .month:
            if Calendar.mizan.component(.day, from: stats.start) == 1 {
                f.dateFormat = "MMMM yyyy"; return f.string(from: stats.start)
            }
            f.dateFormat = "d MMMM"
            return "\(f.string(from: stats.start)) – \(f.string(from: stats.end.addingTimeInterval(-1)))"
        }
    }
}

struct KindColumn: View {
    @Environment(\.palette) private var pal
    let kind: Kind
    let s: KindStats
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(kind.color).frame(width: 7, height: 7)
                Text(kind.displayName()).font(.mz(13, .medium)).lineLimit(1)
            }
            Text(s.userTime.durationText()).font(.display(30)).monospacedDigit()
            VStack(alignment: .leading, spacing: 5) {
                row(tr("الجلسات", "Sessions"), "\(s.sessionCount)", info: Explain.sessions)
                row(tr("متوسط الجلسة", "Avg. session"), s.averageSession.durationText(), info: Explain.average)
                if kind == .cowork || kind == .code { row(tr("عمل الوكيل", "Agent work"), s.claudeAloneTime.durationText(), info: Explain.agent) }
                if let hint { HintText(text: hint) }
                if s.estimatedUserTime > 0 {
                    row(tr("تقديري", "Estimated"), s.estimatedUserTime.durationText(), gold: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ a: String, _ b: String, gold: Bool = false, info: String? = nil) -> some View {
        let on = info != nil && hint == info
        return HStack(spacing: 5) {
            Text(a).foregroundStyle(on ? pal.text : pal.muted).lineLimit(1).minimumScaleFactor(0.7)
            if info != nil && !pal.isPaper {
                Image(systemName: "info.circle").font(.system(size: 9)).foregroundStyle(on ? Color.mizanOn : pal.faint)
            }
            Spacer(minLength: 4)
            Text(b).foregroundStyle(gold ? pal.gold : pal.text).monospacedDigit()
        }
        .font(.mz(12))
        .contentShape(Rectangle())
        .onHover { inside in
            guard let info else { return }
            withAnimation(.easeOut(duration: 0.15)) { if inside { hint = info } else if on { hint = nil } }
        }
    }
}

private extension View {
    /// لوح زجاجي على الشاشة، وسطح مسطّح على الورق.
    func panel(_ pal: Palette, tint: Color? = nil, padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(26, tint: tint, paper: pal.isPaper)
    }
}

/// شرح صريح لحدود الدقة — جزء من التقرير نفسه.
struct AccuracyNote: View {
    @Environment(\.palette) private var pal
    let liveSince: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(tr("عن دقة الأرقام", "About accuracy"))
            Group {
                Text(tr("• وقتك النشط يُقاس لحظياً: أداة الذكاء الاصطناعي في المقدّمة، وآخر حركة للفأرة أو لوحة المفاتيح قبل أقل من مدة الخمول التي اخترتها. القراءة الطويلة دون تحريك شيء قد تُحسب خمولاً.",
                        "• Active time is measured live: the AI tool is in front and you touched the mouse or keyboard within your idle threshold. Long reading without moving anything may count as idle."))
                Text(tr("• يُعرف ChatGPT و Gemini من تطبيقيهما أو من عنوان الصفحة في المتصفح (Safari و Chrome وغيرهما).",
                        "• ChatGPT and Gemini are detected from their apps or from the page address in your browser (Safari, Chrome and others)."))
                Text(tr("• «التقديري» مستنتج من أوقات رسائلك في سجلات Code و Cowork قبل تشغيل ميزان، وليس قياساً فعلياً. لا توجد سجلات محلية لـ Chat ولا للأدوات الأخرى.",
                        "• “Estimated” is inferred from your message times in Code and Cowork logs before Mizan ran — not a real measurement. Chat and other tools keep no local logs."))
                Text(tr("• «عمل الوكيل» هو وقت عمل Claude وحده في العمل المشترك والبرمجة، مأخوذ من سجلاته: من رسالتك حتى آخر نشاط له، ويُطرح منه أي وقت كنت فيه نشطاً.",
                        "• “Agent work” is Claude working alone in Cowork and Code, taken from its logs: from your message to its last activity, minus any time you were active."))
                if let s = liveSince {
                    Text(tr("• القياس الحيّ بدأ في ", "• Live tracking started on ")
                         + s.formatted(.dateTime.day().month().year().locale(Lang.current.locale)) + ".")
                }
            }
            .font(.mz(11)).foregroundStyle(pal.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// الأشهر السابقة: لقطات ثابتة محفوظة لكل شهر انتهى، للمقارنة.
struct PastMonths: View {
    @Environment(\.palette) private var pal
    let records: [MonthRecord]

    var body: some View {
        let maxTotal = max(records.map(\.total).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(tr("الأشهر السابقة", "Previous months"))
                Spacer()
                Text(tr("مرجع محفوظ — لا يتغيّر", "Saved reference — fixed")).font(.mz(10.5)).foregroundStyle(pal.faint)
            }
            ForEach(records) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(label(r)).font(.mz(13, .medium))
                        Spacer()
                        Text(r.total.durationText()).font(.display(18)).monospacedDigit()
                    }
                    SegmentBar(parts: Kind.allCases.map { ($0, r.time($0)) }, total: maxTotal)
                    HStack(spacing: 12) {
                        ForEach(Kind.allCases.filter { r.time($0) > 0 }, id: \.self) { k in
                            HStack(spacing: 4) {
                                Circle().fill(k.color).frame(width: 6, height: 6)
                                Text(k.displayName()).foregroundStyle(pal.muted)
                                Text(r.time(k).durationText())
                            }
                        }
                        Spacer(minLength: 0)
                        Text(tr("الجلسات \(r.sessions)", "\(r.sessions) sessions")).foregroundStyle(pal.faint)
                    }
                    .font(.mz(11))
                }
                if r.id != records.last?.id { Hairline() }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(26)
    }

    private func label(_ r: MonthRecord) -> String {
        let f = DateFormatter(); f.locale = Lang.current.locale; f.calendar = .mizan
        if r.startDay == 1 { f.dateFormat = "MMMM yyyy"; return f.string(from: r.start) }
        f.dateFormat = "d MMMM"
        return f.string(from: r.start) + " – " + f.string(from: r.end.addingTimeInterval(-1))
    }
}
