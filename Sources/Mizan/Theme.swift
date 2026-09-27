import AppKit
import MizanCore
import SwiftUI

// MARK: هوية ميزان — حبر داكن، عاجي، ولمسة ذهب واحدة.

extension Color {
    /// لون «التفعيل»: أزرق سماوي مشرق للمفاتيح والشرائح المفعّلة — الوحيد المشبع مع لون التحذير،
    /// حتى تُعرف حالة «مفعّل» بنظرة على خلفية «منتصف الليل».
    static let mizanOn = Color(hex: 0x6EA8FF)

    init(hex: UInt32, _ opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// لوحة الألوان. نسختان: الشاشة (حبر داكن) والورق (عاجي للطباعة).
struct Palette {
    var background: Color
    var text: Color
    var muted: Color
    var faint: Color
    var line: Color
    var gold: Color
    /// الورق لا يدعم الزجاج؛ يُرسم بأسطح مسطّحة.
    var isPaper = false

    /// «منتصف الليل» — مستوحى من لون MacBook Air: كحلي داكن ودرجات رمادي مزرقّ. (`gold` هو لون التمييز.)
    static let screen = Palette(background: Color(hex: 0x1E2430), text: Color(hex: 0xEEF2F8),
                                muted: Color(hex: 0xE2E9F5, 0.60), faint: Color(hex: 0xE2E9F5, 0.34),
                                line: Color(hex: 0xBECDE6, 0.12), gold: Color(hex: 0xDCE4F0))
    static let paper = Palette(background: Color(hex: 0xFBF8F2), text: Color(hex: 0x17181C),
                               muted: Color(hex: 0x17181C, 0.58), faint: Color(hex: 0x17181C, 0.32),
                               line: Color(hex: 0x17181C, 0.10), gold: Color(hex: 0xA8843F), isPaper: true)
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.screen }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Kind {
    /// درجات «منتصف الليل» الأحادية — من الفاتح إلى الداكن. الأيقونة الرسمية هي المميّز الأساسي.
    var color: Color {
        switch self {
        case .chat: Color(hex: 0xDCE4F0)
        case .cowork: Color(hex: 0x9AA7BB)
        case .code: Color(hex: 0x64718A)
        case .chatgpt: Color(hex: 0xB7C2D4)
        case .gemini: Color(hex: 0x7C889E)
        }
    }
}

extension Font {
    /// خط ثمانية Sans للنصوص.
    static func mz(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        let name = switch weight {
        case .bold, .heavy, .black, .semibold: "thmanyahsans-Bold"
        case .medium: "thmanyahsans-Medium"
        case .light, .thin, .ultraLight: "thmanyahsans-Light"
        default: "thmanyahsans-Regular"
        }
        return .custom(name, size: size)
    }

    /// خط ثمانية Serif Display للأرقام والعناوين الكبيرة.
    static func display(_ size: CGFloat, _ weight: Weight = .medium) -> Font {
        let name = switch weight {
        case .bold, .heavy, .black, .semibold: "thmanyahserifdisplay-Bold"
        case .light, .thin, .ultraLight: "thmanyahserifdisplay-Light"
        case .regular: "thmanyahserifdisplay-Regular"
        default: "thmanyahserifdisplay-Medium"
        }
        return .custom(name, size: size)
    }
}

// MARK: اللغة والاتجاه

/// يطبّق لغة الواجهة واتجاهها والخط والهوية. `.id(lang)` يعيد بناء الواجهة كاملة عند تغيير اللغة.
struct Localized: ViewModifier {
    @AppStorage("lang") private var lang = "ar"
    var palette: Palette = .screen
    func body(content: Content) -> some View {
        let l = Lang(rawValue: lang) ?? .ar
        content
            .environment(\.layoutDirection, l.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, l.locale)
            .environment(\.palette, palette)
            .font(.mz(14))
            .foregroundStyle(palette.text)
            .tint(palette.gold)
            .id(lang)
    }
}

extension View {
    func localized(_ palette: Palette = .screen) -> some View { modifier(Localized(palette: palette)) }
}

// MARK: Liquid Glass

extension View {
    /// لوح زجاجي حقيقي (Liquid Glass، macOS 26+). على الورق: سطح مسطّح رقيق. على الأنظمة الأقدم: مادة شفافة.
    @ViewBuilder
    func glassPanel(_ radius: CGFloat = 24, tint: Color? = nil, paper: Bool = false) -> some View {
        if paper {
            self.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(hex: 0x17181C, 0.035)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color(hex: 0x17181C, 0.08), lineWidth: 1))
        } else if #available(macOS 26, *) {
            self.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            let g: Glass = tint.map { .regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? g.interactive() : g, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// تجمع الألواح الزجاجية حتى تتفاعل حوافها معاً (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: spacing) { content } } else { content }
    }
}

/// خلفية حبرية بتوهّجات ذهبية وملوّنة يكسرها الزجاج — بدونها لا يظهر أثر Liquid Glass.
struct GlowBackground: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Color(hex: 0x0E131C)
                Circle().fill(Color(hex: 0x2E3A50, 0.9)).frame(width: w * 0.9).blur(radius: 140)
                    .position(x: w * 0.85, y: h * 0.05)
                Circle().fill(Color(hex: 0x3E4A5E, 0.55)).frame(width: w * 0.7).blur(radius: 150)
                    .position(x: w * 0.1, y: h * 0.9)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: عناصر الهوية

/// شعار ميزان: عمود وعاتق وكفّتان — خطوط رفيعة فقط.
struct BrandMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, cx = r.midX
        let beamY = r.minY + h * 0.30
        // العمود والقاعدة
        p.move(to: CGPoint(x: cx, y: r.minY + h * 0.14)); p.addLine(to: CGPoint(x: cx, y: r.minY + h * 0.90))
        p.move(to: CGPoint(x: cx - w * 0.20, y: r.minY + h * 0.90)); p.addLine(to: CGPoint(x: cx + w * 0.20, y: r.minY + h * 0.90))
        // العاتق
        p.move(to: CGPoint(x: r.minX + w * 0.10, y: beamY)); p.addLine(to: CGPoint(x: r.maxX - w * 0.10, y: beamY))
        // الكفّتان: خيطان وقوس
        for x in [r.minX + w * 0.18, r.maxX - w * 0.18] {
            p.move(to: CGPoint(x: x, y: beamY)); p.addLine(to: CGPoint(x: x - w * 0.10, y: r.minY + h * 0.58))
            p.move(to: CGPoint(x: x, y: beamY)); p.addLine(to: CGPoint(x: x + w * 0.10, y: r.minY + h * 0.58))
            p.move(to: CGPoint(x: x - w * 0.13, y: r.minY + h * 0.58))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.13, y: r.minY + h * 0.58), control: CGPoint(x: x, y: r.minY + h * 0.72))
        }
        // نقطة الارتكاز
        p.addEllipse(in: CGRect(x: cx - w * 0.035, y: r.minY + h * 0.07, width: w * 0.07, height: w * 0.07))
        return p
    }
}

extension Color {
    /// لون التحذير في الهوية (تجاوز الحد).
    static let mizanWarn = Color(hex: 0xFFB4A8)
}

/// الشعار عدّاد: ١٢ علامة = ١٢ ساعة من يومك، تمتلئ من الأعلى مع عقارب الساعة
/// (ساعة ونصف تبدو كالساعة ١:٣٠ — الشكل دائري فيتبع اتجاه الساعة لا اتجاه القراءة).
/// ما يتجاوز حدّك اليومي (أو ١٢ ساعة كحد أقصى) يتلوّن بلون التحذير، وبعد ١٢ ساعة تبدأ دورة ثانية كلها تحذير.
enum LogoProgress {
    struct Piece { let k: Int; let a: CGFloat; let b: CGFloat; let warn: Bool }

    /// موضع العلامة على الساعة للساعة رقم i من اليوم (0 = الأعلى، ثم مع عقارب الساعة).
    static func position(_ i: Int) -> Int { i % 12 }

    /// الوقت بالساعات مقرّباً للأسفل إلى نصف ساعة.
    static func halfHours(_ seconds: TimeInterval) -> Double { (seconds / 1800).rounded(.down) / 2 }

    static func warnFrom(limit: Double, enabled: Bool) -> Double { enabled ? min(max(limit, 0.5), 12) : 12 }

    static func pieces(hours: Double, warnFrom: Double) -> [Piece] {
        var out: [Piece] = []
        let h = max(0, min(hours, 24))
        for i in 0..<12 {
            let k = position(i)
            let f = min(max(h - Double(i), 0), 1)
            if f > 0 {
                let normalEnd = min(f, max(0, warnFrom - Double(i)))
                if normalEnd > 0 { out.append(Piece(k: k, a: 0, b: normalEnd, warn: false)) }
                if f > normalEnd { out.append(Piece(k: k, a: normalEnd, b: f, warn: true)) }
            }
            let f2 = min(max(h - 12 - Double(i), 0), 1)
            if f2 > 0 { out.append(Piece(k: k, a: 0, b: f2, warn: true)) }
        }
        return out
    }
}

/// العلامات: إما المسار كاملاً (track) أو أجزاء التقدّم. الامتلاء من الداخل إلى الخارج.
struct BrandTicks: Shape {
    var pieces: [LogoProgress.Piece] = []
    var track = false
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        let r0 = R * 0.66, r1 = R * 0.96
        func seg(_ k: Int, _ a: CGFloat, _ b: CGFloat) {
            let ang = CGFloat(k) * .pi / 6 - .pi / 2
            let s = r0 + (r1 - r0) * a, e = r0 + (r1 - r0) * b
            p.move(to: CGPoint(x: c.x + s * cos(ang), y: c.y + s * sin(ang)))
            p.addLine(to: CGPoint(x: c.x + e * cos(ang), y: c.y + e * sin(ang)))
        }
        if track { for k in 0..<12 { seg(k, 0, 1) } } else { for x in pieces where x.b > x.a { seg(x.k, x.a, x.b) } }
        return p
    }
}

struct BrandBeam: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        p.move(to: CGPoint(x: c.x - R * 0.44, y: c.y)); p.addLine(to: CGPoint(x: c.x - R * 0.17, y: c.y))
        p.move(to: CGPoint(x: c.x + R * 0.17, y: c.y)); p.addLine(to: CGPoint(x: c.x + R * 0.44, y: c.y))
        p.addEllipse(in: CGRect(x: c.x - R * 0.11, y: c.y - R * 0.11, width: R * 0.22, height: R * 0.22))
        return p
    }
}

/// الشعار. `hours = nil` يرسم الشكل الثابت (ست علامات) للتقرير والأماكن غير الحيّة.
struct BrandLogo: View {
    var size: CGFloat = 22
    var color: Color = Color(hex: 0xE4EEFF)
    var glow: Color? = .mizanOn
    var hours: Double? = nil
    var warnFrom: Double = 12
    var body: some View {
        let lw = max(1.1, size * 0.075)
        let style = StrokeStyle(lineWidth: lw, lineCap: .round)
        let pieces = LogoProgress.pieces(hours: hours ?? 6, warnFrom: hours == nil ? 12 : warnFrom)
        let normal = pieces.filter { !$0.warn }, warn = pieces.filter(\.warn)
        ZStack {
            BrandTicks(track: true).stroke(color.opacity(0.26), style: style)
            BrandTicks(pieces: normal).stroke(color, style: style)
                .shadow(color: (glow ?? .clear).opacity(0.9), radius: size * 0.12)
                .shadow(color: (glow ?? .clear).opacity(0.5), radius: size * 0.28)
            if !warn.isEmpty {
                BrandTicks(pieces: warn).stroke(Color.mizanWarn, style: style)
                    .shadow(color: glow == nil ? .clear : Color.mizanWarn.opacity(0.9), radius: size * 0.12)
                    .shadow(color: glow == nil ? .clear : Color(hex: 0xFF7A5C, 0.6), radius: size * 0.28)
            }
            BrandBeam().stroke(color, style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
        }
        .frame(width: size, height: size)
        .environment(\.layoutDirection, .leftToRight)
        // بلا حركة متحرّكة: الوقت يتغيّر كل ثانية تقريباً، وتراكم الحركات المتداخلة كان يستهلك المعالج ويجمّد النافذة.
    }
}

/// الشعار الحيّ: يقرأ وقتك اليوم وحدّك من الإعدادات.
struct LiveBrandLogo: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("dailyLimitHours") private var limit = 6.0
    @AppStorage("dailyLimitEnabled") private var limitOn = true
    var size: CGFloat = 22
    var body: some View {
        // يتقدّم كل نصف ساعة فقط (نصف علامة) — لا يُعاد رسمه مع كل تحديث صغير
        BrandLogo(size: size, hours: LogoProgress.halfHours(model.today.totalUser),
                  warnFrom: LogoProgress.warnFrom(limit: limit, enabled: limitOn))
            .accessibilityLabel(tr("وقتك اليوم ", "Today ") + model.today.totalUser.durationText())
    }
}

/// شرح المصطلحات — يظهر عند مرور الماوس على السطر.
enum Explain {
    static var sessions: String { tr("كل فترة عمل متواصلة تُعدّ جلسة، والتوقف أقل من ٥ دقائق لا يقطعها", "Each continuous stretch of work is a session; pauses under 5 minutes don't break it") }
    static var average: String { tr("متوسط طول الجلسة الواحدة: وقتك في هذا القسم مقسوماً على عدد الجلسات", "Average length of one session: your time in this section divided by the number of sessions") }
    static var agent: String { tr("وقت اشتغل فيه Claude على مهمتك وأنت بعيد عن الشاشة، ولا يُحسب من وقتك", "Time Claude worked on your task while you were away from the screen — not counted in your time") }
}

/// سطر الشرح الصغير الذي يظهر تحت العنصر.
struct HintText: View {
    @Environment(\.palette) private var pal
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.mizanOn)
            Text(text).font(.mz(10.5)).foregroundStyle(pal.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.mizanOn.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.mizanOn.opacity(0.25), lineWidth: 0.8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct Hairline: View {
    @Environment(\.palette) private var pal
    var vertical = false
    var body: some View {
        Rectangle().fill(pal.line)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// عنوان صغير متباعد الأحرف.
struct Eyebrow: View {
    @Environment(\.palette) private var pal
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.mz(11, .medium)).foregroundStyle(pal.muted).kerning(Lang.current == .en ? 1.2 : 0)
            .textCase(Lang.current == .en ? .uppercase : nil)
    }
}

/// زر كبسولة زجاجية: الأساسي مصبوغ بالذهب، والثانوي زجاج صافٍ.
struct QuietButton: ButtonStyle {
    @Environment(\.palette) private var pal
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mz(13, primary ? .bold : .medium))
            .foregroundStyle(primary ? Color(hex: 0x1E2430) : pal.text)
            .padding(.vertical, 7).padding(.horizontal, 14)
            .glassCapsule(tint: primary ? pal.gold : nil, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(Capsule())
    }
}

/// تبويب داخل كبسولة زجاجية؛ الاختيار كبسولة ذهبية تنزلق بين الخيارات.
struct TabBar<T: Hashable>: View {
    @Environment(\.palette) private var pal
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { value, title in
                Button { withAnimation(.spring(duration: 0.35)) { selection = value } } label: {
                    Text(title).font(.mz(13, selection == value ? .bold : .medium))
                        .foregroundStyle(selection == value ? Color(hex: 0x1E2430) : pal.muted)
                        .padding(.vertical, 6).padding(.horizontal, 16)
                        .background {
                            if selection == value {
                                Capsule().fill(pal.gold).matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .fixedSize()
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCapsule()
    }
}

/// شريط نسبي رفيع لتوزيع الوقت على الأقسام (مقابل حدّ).
struct ProportionBar: View {
    @Environment(\.palette) private var pal
    let parts: [(Color, Double)]
    let total: Double
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    if p.1 > 0 {
                        Capsule().fill(p.0).frame(width: max(height, g.size.width * min(p.1 / max(total, 1), 1)))
                    }
                }
                Capsule().fill(pal.line)
            }
        }
        .frame(height: height)
    }
}

// MARK: أيقونة شريط القوائم

enum MenuBarIcon {
    /// أيقونة الشريط مفرّغة. تحت الحد: قالب أحادي (يتكيّف مع الفاتح والداكن) والعلامات المنجزة أوضح.
    /// بعد تجاوز الحد: صورة ملوّنة — العلامات الزائدة بلون التحذير، وخروجها عن اللون المعتاد هو التنبيه نفسه.
    static func image(hours: Double, warnFrom: Double, dark: Bool) -> NSImage {
        let over = hours >= warnFrom
        let ink = dark ? NSColor.white : NSColor.black
        let warnInk = dark ? NSColor(srgbRed: 1, green: 0.706, blue: 0.659, alpha: 1)      // #FFB4A8
                           : NSColor(srgbRed: 0.878, green: 0.376, blue: 0.290, alpha: 1)  // #E0604A
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let h = max(0, min(hours, 24))
            for i in 0..<12 {
                let k = LogoProgress.position(i)
                let a = CGFloat(k) * .pi / 6 - .pi / 2
                let f1 = min(max(h - Double(i), 0), 1), f2 = min(max(h - 12 - Double(i), 0), 1)
                let color: NSColor
                if f2 > 0 { color = warnInk.withAlphaComponent(0.45 + 0.55 * f2) }
                else if f1 > 0 && over && Double(i) + f1 > warnFrom { color = warnInk.withAlphaComponent(0.35 + 0.65 * f1) }
                else { color = ink.withAlphaComponent(0.32 + 0.68 * f1) }
                let p = NSBezierPath()
                p.move(to: CGPoint(x: c.x + 6.0 * cos(a), y: c.y + 6.0 * sin(a)))
                p.line(to: CGPoint(x: c.x + 8.4 * cos(a), y: c.y + 8.4 * sin(a)))
                p.lineWidth = 1.4; p.lineCapStyle = .round
                color.setStroke(); p.stroke()
            }
            ink.setStroke()
            let beam = NSBezierPath()
            beam.move(to: CGPoint(x: c.x - 3.6, y: c.y)); beam.line(to: CGPoint(x: c.x - 1.3, y: c.y))
            beam.move(to: CGPoint(x: c.x + 1.3, y: c.y)); beam.line(to: CGPoint(x: c.x + 3.6, y: c.y))
            beam.lineWidth = 1.2; beam.lineCapStyle = .round; beam.stroke()
            let pivot = NSBezierPath(ovalIn: NSRect(x: c.x - 1.1, y: c.y - 1.1, width: 2.2, height: 2.2))
            pivot.lineWidth = 0.9; pivot.stroke()
            return true
        }
        img.isTemplate = !over
        return img
    }
}


// MARK: أيقونات الأقسام

/// أيقونات خاصة بميزان تصف كل قسم وكل أداة (ليست شعارات الشركات):
/// بلاطة زجاجية بتدرّج من درجة القسم، ورمز يصف طبيعة العمل فيه.
extension Kind {
    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"            // محادثة
        case .cowork: "person.2.fill"                               // عمل مشترك مع Claude على ملفاتك
        case .code: "chevron.left.forwardslash.chevron.right"       // برمجة
        case .chatgpt: "brain.head.profile"                         // مساعد عام
        case .gemini: "atom"                                        // مساعد متعدد الوسائط
        }
    }
}

struct KindIcon: View {
    @Environment(\.palette) private var pal
    let kind: Kind
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [kind.color.opacity(0.95), kind.color.opacity(0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
            .overlay(Image(systemName: kind.symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle([.code, .gemini].contains(kind) ? Color(hex: 0xEEF2F8) : Color(hex: 0x141A24)))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}
