import Foundation

/// يحدّد مكان الاستخدام من عنوان الصفحة (AXWebArea) في تطبيق Claude أو في المتصفح.
/// مسارات Claude مأخوذة من اختبار فعلي على تطبيق Claude للماك في 2026-09-24، وقد تتغيّر مع تحديثاته.
public enum SectionClassifier {
    public static func kind(forURL url: String) -> Kind? {
        guard let comps = URLComponents(string: url), let host = comps.host?.lowercased() else { return nil }
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("chatgpt.com") || matches("chat.openai.com") { return .chatgpt }
        if host == "gemini.google.com" || host == "aistudio.google.com" { return .gemini }
        guard host == "claude.ai" else { return nil }
        let first = comps.path.split(separator: "/").first.map(String.init) ?? ""
        switch first {
        case "new", "chat", "recents", "project", "projects": return .chat
        case "cowork", "scheduled-task": return .cowork
        case "epitaxy", "code": return .code
        default: return nil   // إعدادات، تنزيلات… → يبقى القسم السابق
        }
    }

    /// تطبيقات مستقلة تُعرف من معرّفها مباشرة.
    public static func kind(forBundleID id: String) -> Kind? {
        if id == "com.openai.chat" { return .chatgpt }
        if id.lowercased().contains("gemini") { return .gemini }
        return nil
    }
}
