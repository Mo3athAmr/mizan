import AppKit
import MizanCore
import SwiftUI

/// للمطوّر فقط: `Mizan --render-check <مجلد>` يرسم الواجهات إلى ملفات صور و PDF ثم يخرج،
/// للتحقق من الخط والاتجاه دون فتح نوافذ.
enum RenderCheck {
    @MainActor
    static func runIfRequested(model: AppModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-check"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let original = UserDefaults.standard.string(forKey: "lang")
        for lang in Lang.allCases {
        UserDefaults.standard.set(lang.rawValue, forKey: "lang")
        let sub = dir.appendingPathComponent(lang.rawValue)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for p in Period.allCases {
            let r = p.range(containing: now)
            let iv = model.db.intervals(from: r.start, to: r.end)
            let st = Stats.compute(iv, from: r.start, to: r.end)
            Exporter.writePDF(to: sub.appendingPathComponent("report-\(p.rawValue).pdf"),
                              stats: st, intervals: iv, period: p, liveSince: model.liveSince)
            try? Exporter.csv(stats: st, intervals: iv).write(to: sub.appendingPathComponent("report-\(p.rawValue).csv"),
                                                          atomically: true, encoding: .utf8)
        }
        png(MenuView().environmentObject(model).localized().environment(\.colorScheme, .dark),
            to: sub.appendingPathComponent("menu.png"))
        png(DashboardView(scrolls: false).environmentObject(model).localized().environment(\.colorScheme, .dark).frame(width: 860),
            to: sub.appendingPathComponent("dashboard.png"))
        png(SettingsView().environmentObject(model).localized().environment(\.colorScheme, .dark),
            to: sub.appendingPathComponent("settings.png"))
        }
        // حالات الشعار العدّاد: 0، ساعة ونصف، 5، تجاوز حد 6، دورة ثانية — مع أيقونة الشريط (داكن وفاتح)
        let samples: [Double] = [0, 1.5, 5, 7.5, 13.5]
        png(VStack(spacing: 18) {
            HStack(spacing: 28) { ForEach(samples, id: \.self) { h in BrandLogo(size: 72, hours: h, warnFrom: 6) } }
            HStack(spacing: 28) { ForEach(samples, id: \.self) { h in
                Image(nsImage: MenuBarIcon.image(hours: h, warnFrom: 6, dark: true)).renderingMode(.original)
                    .resizable().frame(width: 36, height: 36).frame(width: 72) } }
            HStack(spacing: 28) { ForEach(samples, id: \.self) { h in
                Image(nsImage: MenuBarIcon.image(hours: h, warnFrom: 6, dark: false)).renderingMode(.original)
                    .resizable().frame(width: 36, height: 36).frame(width: 72) } }
                .padding(8).background(Color(hex: 0xE8E8EA))
        }.padding(24).background(Color(hex: 0x0E131C)), to: dir.appendingPathComponent("logos.png"))
        if let original { UserDefaults.standard.set(original, forKey: "lang") } else { UserDefaults.standard.removeObject(forKey: "lang") }
        exit(0)
    }

    /// `Mizan --render-icon <ملف.png>`: يرسم أيقونة التطبيق 1024×1024 ثم يخرج.
    @MainActor
    static func renderIconIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count else { return }
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1C1D23), Color(hex: 0x0E0F12)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .stroke(Color(hex: 0xC9A86A, 0.25), lineWidth: 3)
                .frame(width: 824, height: 824)
            BrandMark()
                .stroke(LinearGradient(colors: [Color(hex: 0xE3C88F), Color(hex: 0xB08D4F)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                .frame(width: 470, height: 470)
                .offset(y: 10)
        }
        .frame(width: 1024, height: 1024)
        let r = ImageRenderer(content: icon)
        r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        exit(0)
    }

    @MainActor
    static func png(_ view: some View, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
