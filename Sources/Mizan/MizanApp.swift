import AppKit
import Combine
import MizanCore
import SwiftUI

/// ميزان يُدار من AppKit: أيقونة في شريط القوائم تفتح لوحاً زجاجياً شفافاً (NSPanel) بدل MenuBarExtra،
/// لأن نافذة MenuBarExtra في macOS 26 ترسم خلفية معتمة خاصة بها لا يمكن إزالتها.
///
/// نقطة البدء AppKit خالصة، بلا مشاهد SwiftUI: مشهد Settings الفارغ السابق كان النظام يعيد فتحه
/// عند إعادة التشغيل نافذةً فارغة باسم «إعدادات ميزان».
@main
enum MizanMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let a = CommandLine.arguments
        if a.contains("--render-check") || a.contains("--render-icon") { return }
        status = StatusController(model: model)
        // للمراجعة: `--open menu` يفتح اللوح، و `--open dashboard|settings` يفتح نافذة.
        if let i = a.firstIndex(of: "--open"), i + 1 < a.count {
            let id = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                if id == "menu" { status?.show() } else { Windows.open(id, model: model) }
            }
        }
    }
}

// MARK: النوافذ

@MainActor
enum Windows {
    private static var open: [String: NSWindow] = [:]

    static func open(_ id: String, model: AppModel) {
        StatusController.shared?.close()
        if let w = open[id] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let isSettings = id == "settings"
        let root: AnyView = isSettings
            ? AnyView(SettingsView().environmentObject(model).localized().preferredColorScheme(.dark))
            : AnyView(DashboardView().environmentObject(model).localized().preferredColorScheme(.dark))
        let host = NSHostingController(rootView: root)
        if !isSettings { host.sizingOptions = [] }
        let w = NSWindow(contentViewController: host)
        w.title = isSettings ? tr("ميزان — الإعدادات", "Mizan — Settings") : tr("ميزان — الإحصائيات", "Mizan — Statistics")
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if !isSettings { mask.insert(.resizable) }
        w.styleMask = mask
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        if isSettings {
            // نافذة شفافة: يظهر زجاج الإعدادات وحده، ويتأثر بمقياس الشفافية مثل القائمة.
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
        }
        if !isSettings { w.setContentSize(NSSize(width: 860, height: 820)) }
        w.center()
        open[id] = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: أيقونة شريط القوائم واللوح الزجاجي

/// لوح بلا إطار ولا خلفية: كل ما يظهر هو زجاج MenuView نفسه فوق سطح المكتب.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { StatusController.shared?.close() }
}

@MainActor
final class StatusController: NSObject, NSWindowDelegate {
    static weak var shared: StatusController?

    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: GlassPanel
    private let host: NSHostingView<AnyView>
    private var clickMonitor: Any?
    private var observer: AnyCancellable?
    private var lastClose = Date.distantPast

    init(model: AppModel) {
        self.model = model
        host = NSHostingView(rootView: AnyView(
            MenuView().environmentObject(model).localized().preferredColorScheme(.dark)))
        panel = GlassPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        super.init()
        StatusController.shared = self

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = host
        // قصّ النافذة على شكل الزجاج المستدير، حتى لا يظهر ظلّ أو حافة مربّعة عند الزوايا.
        host.wantsLayer = true
        host.layer?.cornerRadius = 18
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true

        if let b = item.button {
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(toggle)
        }
        observer = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        updateTitle()
    }

    private var iconKey = ""

    private func updateTitle() {
        // الأيقونة عدّاد: تُعاد رسمها فقط حين يتغيّر ما يظهر فيها (كل نصف ساعة أو عند تغيّر المظهر/الحد).
        if let b = item.button {
            let d = UserDefaults.standard
            let hours = LogoProgress.halfHours(model.today.totalUser)   // يتقدّم كل نصف ساعة
            let warnFrom = LogoProgress.warnFrom(limit: d.double(forKey: "dailyLimitHours"), enabled: d.bool(forKey: "dailyLimitEnabled"))
            let dark = b.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let key = "\(hours)|\(warnFrom)|\(dark)"
            if key != iconKey {
                iconKey = key
                b.image = MenuBarIcon.image(hours: hours, warnFrom: warnFrom, dark: dark)
            }
        }
        let time = model.today.totalUser.durationText()
        let text = model.currentKind.map { "\($0.tag) · \(time)" } ?? time
        item.button?.title = " " + text
    }

    @objc private func toggle() {
        if panel.isVisible { close(); return }
        // الضغط على الأيقونة وهو مفتوح يغلقه أولاً (بفقدان التركيز)، فلا نعيد فتحه فوراً.
        if Date().timeIntervalSince(lastClose) < 0.25 { return }
        show()
    }

    func show() {
        model.refresh()
        let size = host.fittingSize
        guard let button = item.button, let bw = button.window else { return }
        let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = r.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = r.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.14; panel.animator().alphaValue = 1 }
        panel.invalidateShadow()
        button.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        item.button?.highlight(false)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        lastClose = Date()
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}
