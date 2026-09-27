import AppKit
import ApplicationServices
import MizanCore

/// محرّك القياس الحيّ: كل بضع ثوانٍ يسأل —
/// أي تطبيق في المقدّمة؟ هل لمستَ الفأرة أو لوحة المفاتيح مؤخراً؟ أي مكان مفتوح (قسم Claude، ChatGPT، Gemini)؟
/// لا يقرأ نصوص المحادثات؛ فقط عنوان الصفحة الرئيسية في النافذة المركّزة.
final class Tracker {
    static let claudeBundleID = "com.anthropic.claudefordesktop"
    /// متصفحات يُقرأ منها عنوان الصفحة المفتوحة.
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.google.Chrome.canary",
    ]
    static let tick: TimeInterval = 5

    private let db: Database
    private var timer: Timer?
    private var lastTick = Date()
    private var lastClaudeKind: Kind?
    private var enabledPIDs = Set<pid_t>()
    var idleThreshold: () -> TimeInterval
    var onTick: ((Kind?) -> Void)?

    private(set) var currentKind: Kind?

    init(db: Database, idleThreshold: @escaping () -> TimeInterval) {
        self.db = db
        self.idleThreshold = idleThreshold
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        if db.setting("live_since") == nil {
            db.setSetting("live_since", String(Date().timeIntervalSince1970))
        }
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in self?.step() }
        timer?.tolerance = 1
    }

    /// ثوانٍ منذ آخر حركة فأرة أو ضغطة مفتاح (لا يحتاج صلاحية).
    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func step() {
        let now = Date()
        // إذا نام الجهاز بين نبضتين، لا نحسب الفجوة
        let from = max(lastTick, now.addingTimeInterval(-Self.tick * 2))
        lastTick = now
        currentKind = nil
        defer { onTick?(currentKind) }

        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              Self.idleSeconds < idleThreshold() else { return }

        let kind: Kind?
        if let k = SectionClassifier.kind(forBundleID: id) {
            kind = k                                          // تطبيق ChatGPT أو Gemini المستقل
        } else if id == Self.claudeBundleID, Self.hasAccessibility {
            // صفحات الإعدادات لا تُصنَّف، فيبقى القسم السابق
            if let k = pageKind(of: app.processIdentifier, anyPage: false) { lastClaudeKind = k }
            kind = lastClaudeKind
        } else if Self.browsers.contains(id), Self.hasAccessibility {
            kind = pageKind(of: app.processIdentifier, anyPage: true)
        } else {
            kind = nil
        }
        guard let kind else { return }
        currentKind = kind
        db.extendOrInsertLive(kind: kind, from: from, to: now, maxGap: Self.tick * 2)
    }

    /// يقرأ عنوان الصفحة الرئيسية في النافذة المركّزة ويصنّفه.
    /// في Claude نتخطّى صفحات الواجهة الداخلية (anyPage=false)؛ في المتصفح نأخذ أول صفحة ويب فقط (التبويب الظاهر).
    private func pageKind(of pid: pid_t, anyPage: Bool) -> Kind? {
        let axApp = AXUIElementCreateApplication(pid)
        if !enabledPIDs.contains(pid) {
            // Electron و Chrome لا يبنيان شجرة الوصول إلا إذا طُلبت منهما صراحة
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            enabledPIDs.insert(pid)
        }
        guard let win = copy(axApp, kAXFocusedWindowAttribute) else { return nil }
        var queue: [(AXUIElement, Int)] = [(win as! AXUIElement, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 600 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            if (copy(el, kAXRoleAttribute) as? String) == "AXWebArea", let url = copy(el, "AXURL") as? URL {
                if let kind = SectionClassifier.kind(forURL: url.absoluteString) { return kind }
                if anyPage, url.scheme?.hasPrefix("http") == true { return nil }
            }
            guard depth < 14, let kids = copy(el, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            queue += kids.map { ($0, depth + 1) }
        }
        return nil
    }

    private func copy(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
}
