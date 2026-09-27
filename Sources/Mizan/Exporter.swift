import AppKit
import MizanCore
import SwiftUI
import UniformTypeIdentifiers

/// تصدير التقرير. الملفات تُحفظ حيث تختار أنت فقط.
enum Exporter {
    static func fileBase(_ period: Period, _ start: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return tr("ميزان", "Mizan") + "-\(period.displayName())-\(f.string(from: start))"
    }

    @MainActor
    static func savePanel(_ name: String, _ type: UTType) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        p.allowedContentTypes = [type]
        NSApp.activate(ignoringOtherApps: true)
        return p.runModal() == .OK ? p.url : nil
    }

    // MARK: CSV

    static func csv(stats: PeriodStats, intervals: [Interval]) -> String {
        let iso = ISO8601DateFormatter(); iso.timeZone = .current
        var rows = [tr("القسم,وقتك النشط (دقيقة),منه تقديري (دقيقة),عمل الوكيل (دقيقة),عدد الجلسات,متوسط الجلسة (دقيقة)",
                        "Section,Your active time (min),Estimated (min),Agent work (min),Sessions,Avg. session (min)")]
        for k in Kind.allCases {
            let s = stats.kinds[k]!
            rows.append([k.tag, m(s.userTime), m(s.estimatedUserTime), m(s.claudeAloneTime),
                         "\(s.sessionCount)", m(s.averageSession)].joined(separator: ","))
        }
        rows.append("")
        rows.append(tr("القسم,صاحب الوقت,البداية,النهاية,المدة (دقيقة),تقديري", "Section,Who,Start,End,Duration (min),Estimated"))
        for i in intervals {
            let a = max(i.start, stats.start), b = min(i.end, stats.end)
            guard b > a else { continue }
            rows.append([i.kind.tag, i.actor == .user ? tr("أنت", "You") : tr("الوكيل", "Agent"),
                         iso.string(from: a), iso.string(from: b), m(b.timeIntervalSince(a)),
                         i.estimated ? tr("نعم", "yes") : tr("لا", "no")].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func m(_ t: TimeInterval) -> String { String(format: "%.1f", t / 60) }

    @MainActor
    static func exportCSV(stats: PeriodStats, intervals: [Interval], period: Period) {
        guard let url = savePanel(fileBase(period, stats.start) + ".csv", .commaSeparatedText) else { return }
        // BOM حتى يفتحه Excel بالعربية بشكل صحيح
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(csv(stats: stats, intervals: intervals).utf8)
        try? data.write(to: url)
    }

    // MARK: PDF (A4 طولي)

    @MainActor
    static func exportPDF(stats: PeriodStats, intervals: [Interval], period: Period, liveSince: Date?) {
        guard let url = savePanel(fileBase(period, stats.start) + ".pdf", .pdf) else { return }
        writePDF(to: url, stats: stats, intervals: intervals, period: period, liveSince: liveSince)
    }

    @MainActor
    static func writePDF(to url: URL, stats: PeriodStats, intervals: [Interval], period: Period, liveSince: Date?) {
        let page = CGSize(width: 595, height: 842)
        let pal = Palette.paper
        let view = VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                BrandLogo(size: 22, color: pal.text, glow: nil)
                Text(tr("ميزان", "Mizan")).font(.display(22))
                Spacer()
                Text(tr("تقرير وقتك مع الذكاء الاصطناعي", "Your time with AI")).font(.mz(11)).foregroundStyle(pal.muted)
            }
            Rectangle().fill(pal.gold).frame(height: 1)
            ReportContent(stats: stats, intervals: intervals, period: period, liveSince: liveSince, compact: true)
                .padding(.top, 8)
            Text(tr("أُنشئ محلياً بواسطة ميزان — لا تغادر بياناتك جهازك.", "Generated locally by Mizan — your data never leaves your Mac."))
                .font(.mz(9)).foregroundStyle(pal.faint).padding(.top, 6)
        }
        .padding(44)
        .frame(width: page.width, alignment: .top)
        .background(pal.background)
        .environment(\.colorScheme, .light)
        .localized(.paper)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: page.width, height: nil)
        var box = CGRect(origin: .zero, size: page)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        renderer.render { size, draw in
            // تصغير المحتوى ليتّسع في صفحة A4 واحدة طولية، مع خلفية بيضاء كاملة
            let s = min(1, page.height / size.height, page.width / size.width)
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(srgbRed: 0xFB / 255, green: 0xF8 / 255, blue: 0xF2 / 255, alpha: 1)); ctx.fill(box)
            ctx.translateBy(x: (page.width - size.width * s) / 2, y: page.height - size.height * s)
            ctx.scaleBy(x: s, y: s)
            draw(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
