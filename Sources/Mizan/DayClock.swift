import MizanCore
import SwiftUI

/// «ساعة يومك»: حلقة من ٢٤ ساعة تضيء فيها الساعات التي عملت فيها فعلاً في مواضعها الحقيقية.
/// منتصف الليل في الأعلى، والظهر في الأسفل، وتدور مع عقارب الساعة. طول كل قطعة بقدر ما عملت
/// في تلك الساعة، مقسّمة بألوان الأقسام. الشعار يجيب «كم اشتغلت؟» وهذه تجيب «متى؟».
struct DayClock: View {
    @Environment(\.palette) private var pal
    let stats: PeriodStats
    let intervals: [Interval]
    let period: Period
    var compact = false
    @State private var hover: Int?

    private var byKind: [Kind: [TimeInterval]] {
        Dictionary(uniqueKeysWithValues: Kind.allCases.map { k in
            (k, Stats.compute(intervals.filter { $0.kind == k }, from: stats.start, to: stats.end).hourly)
        })
    }

    /// أول نشاط وآخر نشاط لك داخل المدة.
    private var span: (Date, Date)? {
        let mine = intervals.filter { $0.actor == .user }
            .map { (max($0.start, stats.start), min($0.end, stats.end)) }.filter { $0.1 > $0.0 }
        guard let a = mine.map(\.0).min(), let b = mine.map(\.1).max() else { return nil }
        return (a, b)
    }

    var body: some View {
        let data = byKind
        let totals = (0..<24).map { h in Kind.allCases.reduce(0) { $0 + (data[$1]?[h] ?? 0) } }
        let scale = period == .day ? max(3600, totals.max() ?? 0) : max(1, totals.max() ?? 0)
        let size: CGFloat = compact ? 160 : 250
        HStack(alignment: .center, spacing: compact ? 12 : 28) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(period == .day ? tr("ساعة يومك", "Your day's clock") : tr("ساعات عملك", "When you work"))
                Text(period == .day
                     ? tr("كل قطعة ساعة من الساعات الـ24 في موضعها الحقيقي، وطولها بقدر ما عملت فيها، بلون القسم.",
                          "Each segment is one of the 24 hours in its real place; its length is how much you worked in it, in the section's color.")
                     : tr("مجموع كل ساعة خلال المدة: أطول قطعة هي الساعة التي تعمل فيها أكثر عادةً.",
                          "Each hour summed across the period: the longest segment is when you usually work most."))
                    .font(.mz(11.5)).foregroundStyle(pal.muted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    if period == .day, let s = span {
                        fact(tr("أول نشاط", "First activity"), timeLabel(s.0))
                        fact(tr("آخر نشاط", "Last activity"), timeLabel(s.1))
                    }
                    fact(tr("ساعات فيها عمل", "Active hours"), "\(totals.filter { $0 > 0 }.count) " + tr("من 24", "of 24"))
                    fact(tr("أكثر ساعة", "Peak hour"), stats.peakHour.map { hourLabel($0) } ?? "—")
                }
                .padding(.top, 4)
                if !compact { HStack(spacing: 12) {
                    ForEach(Kind.allCases.filter { (stats.kinds[$0]?.userTime ?? 0) > 0 }, id: \.self) { k in
                        HStack(spacing: 5) {
                            Circle().fill(k.color).frame(width: 6, height: 6)
                            Text(k.displayName()).font(.mz(10)).foregroundStyle(pal.muted)
                        }
                    }
                } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                ring(data: data, scale: scale, size: size)
                center(data: data, totals: totals)
                labels(size: size)
            }
            .frame(width: size + 56, height: size + 44)
            .environment(\.layoutDirection, .leftToRight)   // الساعة لا تُعكس في الواجهة العربية
        }
    }

    // MARK: الحلقة

    private func ring(data: [Kind: [TimeInterval]], scale: Double, size: CGFloat) -> some View {
        let now = Date()
        let showNow = period == .day && now >= stats.start && now < stats.end
        let nowHour = Double(Calendar.mizan.component(.hour, from: now)) + Double(Calendar.mizan.component(.minute, from: now)) / 60
        return Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let R = size / 2, r0 = R * 0.56, r1 = R * 0.98
            func ang(_ h: Double) -> Angle { .degrees(-90 + h * 15) }
            func arc(_ h: Int, _ a: CGFloat, _ b: CGFloat) -> Path {
                var p = Path()
                p.addArc(center: c, radius: (a + b) / 2, startAngle: ang(Double(h) + 0.06), endAngle: ang(Double(h) + 0.94), clockwise: false)
                return p
            }
            for h in 0..<24 {
                let on = hover == h
                ctx.stroke(arc(h, r0, r1), with: .color(on ? pal.text.opacity(0.14) : (pal.isPaper ? pal.line : pal.text.opacity(0.045))), lineWidth: r1 - r0)
                var r = r0
                for k in Kind.allCases {
                    let t = data[k]?[h] ?? 0
                    guard t > 0 else { continue }
                    let th = max(1.5, (r1 - r0) * CGFloat(t / scale))
                    let b = min(r1, r + th)
                    ctx.stroke(arc(h, r, b), with: .color(k.color.opacity(hover == nil || on ? 1 : 0.55)), lineWidth: b - r)
                    r = b
                }
            }
            // علامات الأرباع داخل الحلقة
            for q in [0.0, 6, 12, 18] {
                let a = ang(q).radians
                var p = Path()
                p.move(to: CGPoint(x: c.x + (r0 - 10) * cos(a), y: c.y + (r0 - 10) * sin(a)))
                p.addLine(to: CGPoint(x: c.x + (r0 - 4) * cos(a), y: c.y + (r0 - 4) * sin(a)))
                ctx.stroke(p, with: .color(pal.muted), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            // الآن
            if showNow {
                let a = ang(nowHour).radians
                var p = Path()
                p.move(to: CGPoint(x: c.x + (r0 - 2) * cos(a), y: c.y + (r0 - 2) * sin(a)))
                p.addLine(to: CGPoint(x: c.x + (r1 + 5) * cos(a), y: c.y + (r1 + 5) * sin(a)))
                ctx.stroke(p, with: .color(.mizanOn), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                let d = CGRect(x: c.x + (r1 + 8) * cos(a) - 3, y: c.y + (r1 + 8) * sin(a) - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: d), with: .color(.mizanOn))
            }
        }
        .frame(width: size + 56, height: size + 44)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                let c = CGPoint(x: (size + 56) / 2, y: (size + 44) / 2)
                let dx = p.x - c.x, dy = p.y - c.y, dist = sqrt(dx * dx + dy * dy)
                guard dist > size * 0.24, dist < size * 0.56 else { hover = nil; return }
                var deg = atan2(dy, dx) * 180 / .pi + 90
                if deg < 0 { deg += 360 }
                hover = min(23, Int(deg / 15))
            case .ended: hover = nil
            }
        }
    }

    // MARK: المركز

    @ViewBuilder private func center(data: [Kind: [TimeInterval]], totals: [Double]) -> some View {
        VStack(spacing: 3) {
            if let h = hover {
                Text(hourLabel(h) + " – " + hourLabel((h + 1) % 24)).font(.mz(10.5)).foregroundStyle(pal.muted)
                Text(totals[h].durationText()).font(.display(compact ? 20 : 24)).monospacedDigit()
                ForEach(Kind.allCases.filter { (data[$0]?[h] ?? 0) > 0 }, id: \.self) { k in
                    HStack(spacing: 4) {
                        Circle().fill(k.color).frame(width: 5, height: 5)
                        Text((data[k]?[h] ?? 0).durationText()).font(.mz(10)).monospacedDigit().foregroundStyle(pal.muted)
                    }
                }
            } else if period == .day, let s = span {
                Text(tr("من", "From")).font(.mz(10)).foregroundStyle(pal.faint)
                Text(timeLabel(s.0)).font(.display(compact ? 16 : 19)).monospacedDigit()
                Text(tr("إلى", "to")).font(.mz(10)).foregroundStyle(pal.faint)
                Text(timeLabel(s.1)).font(.display(compact ? 16 : 19)).monospacedDigit()
            } else if let peak = stats.peakHour {
                Text(tr("أكثر ساعة", "Peak hour")).font(.mz(10)).foregroundStyle(pal.faint)
                Text(hourLabel(peak)).font(.display(compact ? 18 : 22)).monospacedDigit()
            } else {
                Text(tr("لا نشاط", "No activity")).font(.mz(11)).foregroundStyle(pal.faint)
            }
        }
        .environment(\.layoutDirection, Lang.current.isRTL ? .rightToLeft : .leftToRight)
        .allowsHitTesting(false)
    }

    private func labels(size: CGFloat) -> some View {
        let R = size / 2 + 16
        return ZStack {
            ForEach([0, 6, 12, 18], id: \.self) { h in
                let a = (-90 + Double(h) * 15) * .pi / 180
                Text(hourLabel(h)).font(.mz(10)).foregroundStyle(pal.faint).fixedSize()
                    .offset(x: (R + (h % 12 == 6 ? 8 : 0)) * cos(a), y: R * sin(a))
            }
        }
        .allowsHitTesting(false)
    }

    private func fact(_ t: String, _ v: String) -> some View {
        HStack {
            Text(t).font(.mz(12)).foregroundStyle(pal.muted)
            Spacer(minLength: 8)
            Text(v).font(.mz(12, .medium)).monospacedDigit()
        }
        .frame(maxWidth: 240)
    }

    private func timeLabel(_ d: Date) -> String {
        let c = Calendar.mizan.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let t = String(format: "%d:%02d", h12, m)
        return Lang.current == .ar ? rtlIsolated("\(t) \(h < 12 ? "ص" : "م")") : "\(t) \(h < 12 ? "AM" : "PM")"
    }
}
