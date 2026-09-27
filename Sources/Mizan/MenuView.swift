import AppKit
import MizanCore
import SwiftUI

/// اللوح الزجاجي من شريط القوائم — تصميم «منتصف الليل»:
/// حلقة لوقت اليوم مقابل الحد، أعمدة الأسبوع، سطر الشهر، ثم صف لكل قسم بأيقونته الرسمية وتفاصيله.
struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var pal
    @AppStorage("dailyLimitHours") private var dailyLimitHours = 6.0
    @AppStorage("menuTransparency") private var transparency = 0.8
    @State private var hovered: Kind?
    @State private var logoHover = false
    @State private var hint: (kind: Kind, text: String)?

    private var visibleKinds: [Kind] {
        Kind.claudeSections + Kind.otherTools.filter {
            (model.today.kinds[$0]?.userTime ?? 0) > 0 || model.currentKind == $0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 12)
            Hairline()
            if !model.hasAccessibility { PermissionBanner().padding(.top, 10) }
            hero.padding(.vertical, 14)
            month.padding(.bottom, 12)
            Hairline()
            VStack(spacing: 0) {
                ForEach(Array(visibleKinds.enumerated()), id: \.element) { i, k in
                    if i > 0 { Hairline() }
                    row(k)
                }
            }
            .zIndex(1)
            Hairline()
            footer.padding(.top, 10)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .frame(width: 420)
        .glassSheet(transparency: transparency, radius: 20)
        .onAppear { model.refresh() }
    }

    // MARK: الرأس

    private var header: some View {
        HStack(spacing: 10) {
            LiveBrandLogo(size: 30)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { logoHover = inside } }
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("ميزان", "Mizan")).font(.mz(15, .bold))
                // عند المرور على الشعار يشرح نفسه
                Text(logoHover
                     ? tr("كل علامة ساعة من يومك، والزائد عن حدّك بلون التحذير", "Each tick is an hour of your day; past your limit turns warm")
                     : tr("وقتك مع الذكاء الاصطناعي", "Your time with AI"))
                    .font(.mz(11)).foregroundStyle(logoHover ? pal.text : pal.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            Button { open("settings") } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(GlassIcon()).help(tr("الإعدادات", "Settings"))
        }
    }

    // MARK: اليوم والأسبوع

    private var hero: some View {
        let total = model.today.totalUser
        let limit = dailyLimitHours * 3600
        let frac = min(total / max(limit, 1), 1)
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(pal.line, lineWidth: 9)
                Circle().trim(from: 0, to: max(frac, 0.012))
                    .stroke(AngularGradient(colors: [pal.gold, Color(hex: 0x6F7D93), pal.gold], center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    // الحلقة ساعة: تبدأ من الأعلى وتمتلئ مع عقارب الساعة في اللغتين (مثل الشعار).
                    .rotationEffect(.degrees(-90))
                BrandBeam().stroke(pal.gold, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 40, height: 40)
            }
            .frame(width: 88, height: 88)
            .environment(\.layoutDirection, .leftToRight)   // لا تُعكس الساعة في الواجهة العربية
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("وقتك اليوم", "Today")).font(.mz(11.5)).foregroundStyle(pal.muted)
                Text(total.durationText()).font(.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(tr("\(Int((total / max(limit, 1) * 100).rounded()))٪ من حدّك (", "\(Int((total / max(limit, 1) * 100).rounded()))% of your limit (")
                     + limit.durationText() + ")")
                    .font(.mz(11)).foregroundStyle(total >= limit ? Color(hex: 0xFFB4A8) : pal.muted)
            }
            Rectangle().fill(pal.line).frame(width: 1).padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("هذا الأسبوع", "This week")).font(.mz(11.5)).foregroundStyle(pal.muted)
                Text(model.week.totalUser.durationText()).font(.display(17)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                weekBars.frame(height: 34).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// أعمدة أيام الأسبوع السبعة (اليوم مُبرز).
    private var weekBars: some View {
        let byKind = model.sparks[.week] ?? [:]
        let n = byKind.values.map(\.count).max() ?? 0
        var days = (0..<n).map { i in byKind.values.reduce(0) { $0 + ($1.count > i ? $1[i] : 0) } }
        let todayIndex = max(days.count - 1, 0)
        days += Array(repeating: 0, count: max(0, 7 - days.count))
        let m = max(days.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i == todayIndex ? pal.gold : pal.gold.opacity(0.35))
                    .frame(height: max(3, 34 * v / m))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: الشهر

    private var month: some View {
        let s = model.month
        let days = max(1, Calendar.mizan.dateComponents([.day], from: s.start, to: s.end).day ?? 30)
        let limit = dailyLimitHours * 3600 * Double(days)
        return HStack(spacing: 10) {
            Text(tr("الشهر", "Month")).font(.mz(12)).foregroundStyle(pal.muted)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.line)
                    Capsule().fill(pal.gold).frame(width: max(5, g.size.width * min(s.totalUser / max(limit, 1), 1)))
                }
            }
            .frame(height: 5)
            Text(s.totalUser.durationText()).font(.display(14)).monospacedDigit()
            Text(tr("من ", "of ") + limit.durationText()).font(.mz(10.5)).foregroundStyle(pal.faint)
        }
    }

    // MARK: الأقسام

    private func row(_ k: Kind) -> some View {
        let s = model.today.kinds[k]
        let time = s?.userTime ?? 0
        let total = max(model.today.totalUser, 1)
        let pct = Int((time / total * 100).rounded())
        let live = model.currentKind == k
        return HStack(spacing: 12) {
            KindIcon(kind: k, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(k.displayName()).font(.mz(13.5, .bold))
                    if live {
                        Text(tr("الآن", "now")).font(.mz(9.5, .bold)).foregroundStyle(pal.gold)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().stroke(pal.gold, lineWidth: 1))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(time.durationText()).font(.display(16)).monospacedDigit()
                        .foregroundStyle(time > 0 ? pal.text : pal.faint)
                    Text("\(pct)٪").font(.mz(10.5)).foregroundStyle(pal.muted)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(pal.line)
                        Capsule().fill(k.color).frame(width: max(4, g.size.width * Double(pct) / 100))
                    }
                }
                .frame(height: 4)
            }
            .frame(width: 140)
            Rectangle().fill(pal.line).frame(width: 1).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                detail(k, tr("الجلسات", "Sessions"), "\(s?.sessionCount ?? 0)", info: Explain.sessions)
                detail(k, tr("متوسط الجلسة", "Avg. session"), (s?.averageSession ?? 0).durationText(), info: Explain.average)
                // Chat لا يترك سجلات محلية، فلا يُعرف فيه «عمل الوكيل»
                if k == .cowork || k == .code {
                    detail(k, tr("عمل الوكيل", "Agent work"), (s?.claudeAloneTime ?? 0).durationText(), info: Explain.agent)
                }
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.faint)
        }
        .padding(.horizontal, 6).padding(.vertical, 10)
        .background {
            if hovered == k {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
                    .padding(.horizontal, -6)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = inside ? k : (hovered == k ? nil : hovered)
                if !inside, hint?.kind == k { hint = nil }
            }
        }
        .onTapGesture { open("dashboard") }
        // الشرح يطفو تحت الصف فوق ما بعده، فلا يتغيّر ارتفاع القائمة
        .overlay(alignment: .bottom) {
            if let h = hint, h.kind == k {
                HintText(text: h.text)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x1E2430)))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    // إطار بارتفاع صفر عند حافة الصف السفلى، والشرح يتدلّى منه للأسفل
                    .frame(maxWidth: .infinity, maxHeight: 0, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(hint?.kind == k ? 1 : 0)
    }

    private func detail(_ k: Kind, _ label: String, _ value: String, info: String) -> some View {
        let on = hint?.kind == k && hint?.text == info
        return HStack(spacing: 6) {
            Circle().fill(k.color).frame(width: 5, height: 5)
            Text(Lang.current.isRTL ? rtlIsolated(label) : label).foregroundStyle(on ? pal.text : pal.muted)
            Image(systemName: "info.circle").font(.system(size: 8.5)).foregroundStyle(on ? Color.mizanOn : pal.faint)
            Spacer(minLength: 4)
            Text(value).monospacedDigit()
        }
        .font(.mz(11))
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                if inside { hint = (k, info) } else if on { hint = nil }
            }
        }
    }

    // MARK: الأسفل

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { open("dashboard") } label: {
                    Label(tr("الإحصائيات", "Statistics"), systemImage: "chart.bar.xaxis")
                }
                .buttonStyle(GlassPill())
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.system(size: 10.5))
                    Text(tr("متواصل ", "Continuous ") + model.continuous.durationText()).monospacedDigit()
                }
                .font(.mz(11.5))
                .foregroundStyle(model.continuous > 45 * 60 ? Color(hex: 0xFFB4A8) : pal.muted)
                .padding(.horizontal, 6)
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(GlassIcon()).help(tr("إنهاء", "Quit"))
            }
            // التوقيع في الوسط كما في الإعدادات
            DeveloperCredit().padding(.top, 2)
        }
    }

    private func open(_ id: String) {
        Windows.open(id, model: model)
    }
}

/// توقيع المطوّر أسفل الواجهات والتقارير.
struct DeveloperCredit: View {
    @Environment(\.palette) private var pal
    /// ارتفاع حروف الاسم بالنقاط.
    var height: CGFloat = 9
    var body: some View {
        HStack(spacing: 6) {
            Text(tr("مطوّر بواسطة", "Developed by"))
            NameMarkView(height: height, color: pal.faint)
        }
        .font(.mz(9.5, .medium))
        .foregroundStyle(pal.faint)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, Lang.current.isRTL ? .rightToLeft : .leftToRight)
    }
}

/// توقيع «YAHYA ALDORAIBI» — حروف مرسومة يدوياً بوزن الشعرة (من عائلة «الميزان»، بلا قطع).
/// ارتفاع الحرف 100 وحدة في التصميم. النسخة المرجعية لكل الأدوات: ~/ClaudeFonts/brand/
struct NameMark: Shape {
    static let spacing: CGFloat = 30, word: CGFloat = 110

    /// كل حرف: عرضه، ومساراته بإحداثيات التصميم (y للأسفل، الارتفاع 100).
    private static func glyph(_ c: Character) -> (CGFloat, (inout Path) -> Void) {
        func p(_ pts: [(CGFloat, CGFloat)]) -> (inout Path) -> Void {
            { path in path.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { path.addLine(to: CGPoint(x: q.0, y: q.1)) } }
        }
        switch c {
        case "Y": return (96, { path in p([(0, 0), (48, 50)])(&path); p([(96, 0), (48, 50), (48, 100)])(&path) })
        case "A": return (88, { path in p([(0, 100), (44, 0), (88, 100)])(&path); p([(18, 64), (70, 64)])(&path) })
        case "H": return (78, { path in p([(0, 0), (0, 100)])(&path); p([(78, 0), (78, 100)])(&path); p([(0, 50), (78, 50)])(&path) })
        case "D": return (78, { path in
            p([(0, 0), (0, 100)])(&path)
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 30, y: 0))
            path.addCurve(to: CGPoint(x: 30, y: 100), control1: CGPoint(x: 92, y: 0), control2: CGPoint(x: 92, y: 100))
            path.addLine(to: CGPoint(x: 0, y: 100)) })
        case "L": return (62, { path in p([(0, 0), (0, 100), (62, 100)])(&path) })
        case "O": return (100, { path in path.addEllipse(in: CGRect(x: 0, y: 0, width: 100, height: 100)) })
        case "R": return (74, { path in
            p([(0, 100), (0, 0)])(&path)
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 40, y: 0))
            path.addCurve(to: CGPoint(x: 40, y: 54), control1: CGPoint(x: 78, y: 0), control2: CGPoint(x: 78, y: 54))
            path.addLine(to: CGPoint(x: 0, y: 54))
            p([(36, 54), (74, 100)])(&path) })
        case "I": return (0, { path in p([(0, 0), (0, 100)])(&path) })
        case "B": return (70, { path in
            p([(0, 0), (0, 100)])(&path)
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 36, y: 0))
            path.addCurve(to: CGPoint(x: 36, y: 48), control1: CGPoint(x: 68, y: 0), control2: CGPoint(x: 68, y: 48))
            path.addLine(to: CGPoint(x: 0, y: 48))
            path.move(to: CGPoint(x: 0, y: 48)); path.addLine(to: CGPoint(x: 40, y: 48))
            path.addCurve(to: CGPoint(x: 40, y: 100), control1: CGPoint(x: 76, y: 48), control2: CGPoint(x: 76, y: 100))
            path.addLine(to: CGPoint(x: 0, y: 100)) })
        default: return (0, { _ in })
        }
    }

    /// العرض الكلي بوحدات التصميم.
    static var designWidth: CGFloat {
        var x: CGFloat = 0
        for w in "YAHYA ALDORAIBI".split(separator: " ", omittingEmptySubsequences: false) {
            if x > 0 { x += word - spacing }
            for c in w { x += glyph(c).0 + spacing }
        }
        return x - spacing
    }

    func path(in rect: CGRect) -> Path {
        var unit = Path(); var x: CGFloat = 0
        for c in "YAHYA ALDORAIBI" {
            if c == " " { x += Self.word - Self.spacing; continue }
            let (w, draw) = Self.glyph(c)
            var g = Path(); draw(&g)
            unit.addPath(g, transform: CGAffineTransform(translationX: x, y: 0))
            x += w + Self.spacing
        }
        let s = rect.height / 100
        return unit.applying(CGAffineTransform(scaleX: s, y: s).translatedBy(x: rect.minX / s, y: rect.minY / s))
    }
}

/// الاسم بخط الشعرة — حروف كاملة بلا قطع.
struct NameMarkView: View {
    var height: CGFloat = 9
    var color: Color
    var body: some View {
        let lw = max(0.8, height * 0.075)   // الشعرة: لا تقل عن 0.8 نقطة لتبقى مرئية
        NameMark()
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .miter))
            .frame(width: NameMark.designWidth * height / 100, height: height)
            .padding(.vertical, lw / 2)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel("YAHYA ALDORAIBI")
    }
}

// MARK: عناصر القائمة

/// شريط مكدّس بأجزاء لكل قسم، والباقي حتى الحد اليومي خافت. عند المرور على صف يبرز جزؤه.
struct SegmentBar: View {
    @Environment(\.palette) private var pal
    let parts: [(Kind, Double)]
    let total: Double
    var hovered: Kind?
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(parts.filter { $0.1 > 0 }, id: \.0) { k, v in
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(k.color)
                        .frame(width: max(4, (g.size.width - 12) * min(v / max(total, 1), 1)))
                        .opacity(hovered == nil || hovered == k ? 1 : 0.35)
                }
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(pal.line)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// خط زمني صغير لآخر ساعات اليوم.
struct Sparkline: Shape {
    let values: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else {
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            return p
        }
        let m = max(values.max() ?? 0, 1)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: r.maxY - r.height * CGFloat(v / m))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// زر كبسولة زجاجية تفاعلية (يلمع ويتمدّد عند الضغط على macOS 26).
struct GlassPill: ButtonStyle {
    @Environment(\.palette) private var pal
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mz(12, .medium)).labelStyle(.titleAndIcon)
            .padding(.vertical, 6).padding(.horizontal, 12)
            .glassCapsule(interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(Capsule())
    }
}

/// زر أيقونة دائري زجاجي.
struct GlassIcon: ButtonStyle {
    @Environment(\.palette) private var pal
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5)).foregroundStyle(pal.muted)
            .frame(width: 28, height: 28)
            .glassCapsule(interactive: true)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(Circle())
    }
}

extension View {
    /// لوح زجاجي واحد يغطي النافذة كاملة. الشفافية (0–1) يختارها المستخدم من الإعدادات:
    /// تدرّج متصل حتى 100٪ — كلما زادت قلّت الصبغة الحبرية، ويبقى التمويه دائماً (بلا قفزة إلى زجاج صافٍ).
    @ViewBuilder
    func glassSheet(transparency: Double = 0.8, radius: CGFloat = 18) -> some View {
        let t = min(max(transparency, 0), 1)
        let tint = Color(hex: 0x1E2430, 0.25 + 0.6 * (1 - t))
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint))
        }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var pal
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("يحتاج ميزان صلاحية Accessibility", "Mizan needs Accessibility access")).font(.mz(13, .bold))
            Text(tr("لمعرفة المكان المفتوح من عنوان الصفحة فقط: قسم Claude، أو ChatGPT و Gemini في المتصفح. لا يقرأ محادثاتك، ولا يرسل شيئاً خارج جهازك.",
                    "Only to read the page address: which Claude section, or ChatGPT and Gemini in your browser. It never reads your conversations or sends anything off your Mac."))
                .font(.mz(11)).foregroundStyle(pal.muted).fixedSize(horizontal: false, vertical: true)
            Text(tr("إن بدت ممنوحة في الإعدادات: احذف Mizan بزر −، ثم أضفه من جديد.",
                    "If it already looks enabled: remove Mizan with −, then add it again."))
                .font(.mz(11)).foregroundStyle(pal.faint).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Button(tr("منح الصلاحية", "Grant access")) { Tracker.requestAccessibility() }.buttonStyle(QuietButton(primary: true))
                Button(tr("إعادة التشغيل", "Restart")) { AppModel.relaunch() }.buttonStyle(QuietButton())
            }
            .padding(.top, 2)
        }
        .padding(16)
        .glassPanel(20, tint: pal.gold.opacity(0.18))
    }
}
