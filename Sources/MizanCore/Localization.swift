import Foundation

/// لغة الواجهة: العربية (الافتراضية) أو الإنجليزية. تُحفظ في UserDefaults بالمفتاح "lang".
public enum Lang: String, CaseIterable, Sendable {
    case ar, en

    public static var current: Lang {
        Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "ar") ?? .ar
    }

    public var locale: Locale { Locale(identifier: rawValue) }
    public var isRTL: Bool { self == .ar }
    public var nativeName: String { self == .ar ? "العربية" : "English" }
}

/// نص بلغتين حسب لغة الواجهة الحالية.
public func tr(_ ar: String, _ en: String, _ lang: Lang = .current) -> String {
    lang == .ar ? ar : en
}

public extension Kind {
    func displayName(_ lang: Lang = .current) -> String {
        switch self {
        case .chat: tr("المحادثة", "Chat", lang)
        case .cowork: tr("العمل المشترك", "Cowork", lang)
        case .code: tr("البرمجة", "Code", lang)
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        }
    }
    /// الاسم الإنجليزي الأصلي — يُستخدم كوسم ثابت.
    var tag: String {
        switch self {
        case .chat: "Chat"; case .cowork: "Cowork"; case .code: "Code"
        case .chatgpt: "ChatGPT"; case .gemini: "Gemini"
        }
    }
}

public extension Period {
    func displayName(_ lang: Lang = .current) -> String {
        switch self {
        case .day: tr("اليوم", "Today", lang)
        case .week: tr("الأسبوع", "Week", lang)
        case .month: tr("الشهر", "Month", lang)
        }
    }
}

public extension TimeInterval {
    /// «1 س 35 د» أو «1h 35m».
    func durationText(_ lang: Lang = .current) -> String {
        let mins = Int((self / 60).rounded())
        let h = mins / 60, m = mins % 60
        let (hs, ms) = lang == .ar ? (" س", " د") : ("h", "m")
        let text = h == 0 ? "\(m)\(ms)" : (m == 0 ? "\(h)\(hs)" : "\(h)\(hs) \(m)\(ms)")
        return lang == .ar ? rtlIsolated(text) : text
    }
}

public func hourLabel(_ h: Int, _ lang: Lang = .current) -> String {
    let h12 = h % 12 == 0 ? 12 : h % 12
    return lang == .ar ? rtlIsolated("\(h12) \(h < 12 ? "ص" : "م")") : "\(h12) \(h < 12 ? "AM" : "PM")"
}

/// يعزل النص العربي المختلط بالأرقام (مثل «46 د») في اتجاه من اليمين لليسار
/// عبر محارف Unicode الخفية RLI … PDI، فيُقرأ صحيحاً أينما وُضع:
/// في صفوف القائمة، والمربعات، وشريط القوائم، والإشعارات، وتقرير PDF.
/// بدونها يعرضه SwiftUI أحياناً بفقرة من اليسار لليمين فيظهر «د 46».
public func rtlIsolated(_ s: String) -> String { "\u{2067}" + s + "\u{2069}" }
