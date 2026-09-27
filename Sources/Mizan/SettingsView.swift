import MizanCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var pal
    @AppStorage("lang") private var lang = "ar"
    @AppStorage("idleMinutes") private var idleMinutes = 2.0
    @AppStorage("breakEnabled") private var breakEnabled = true
    @AppStorage("breakMinutes") private var breakMinutes = 50.0
    @AppStorage("dailyLimitEnabled") private var dailyLimitEnabled = true
    @AppStorage("dailyLimitHours") private var dailyLimitHours = 6.0
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled = true
    @AppStorage("monthStartDay") private var monthStartDay = 1
    @AppStorage("dayStartHour") private var dayStartHour = 0
    @AppStorage("menuTransparency") private var transparency = 0.8

    var body: some View {
        ScrollView {
            GlassGroup(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    LiveBrandLogo(size: 24)
                    Text(tr("الإعدادات", "Settings")).font(.display(24))
                }

                section(tr("اللغة", "Language")) {
                    TabBar(items: Lang.allCases.map { ($0.rawValue, $0.nativeName) }, selection: $lang)
                }

                section(tr("المظهر", "Appearance")) {
                    HStack {
                        Text(tr("شفافية القائمة", "Menu transparency"))
                        Spacer()
                        Text("\(Int((transparency * 100).rounded()))٪").font(.display(16)).monospacedDigit()
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill").font(.system(size: 10)).foregroundStyle(pal.muted)
                        Slider(value: $transparency, in: 0...1).tint(.mizanOn)
                        Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(pal.muted)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    note(tr("كلما زادت ظهر ما خلف القائمة والإعدادات أوضح، مع بقاء التمويه ليبقى النص مقروءاً.",
                            "Higher shows more of what's behind the menu and settings, with blur kept so text stays readable."))
                }

                section(tr("اليوم", "Day")) {
                    stepper(tr("يبدأ اليوم الساعة", "Day starts at"), dayStartHour == 0 ? tr("12 ص", "12 AM") : hourLabel(dayStartHour),
                            Binding(get: { Double(dayStartHour) }, set: { dayStartHour = Int($0); model.refresh() }), 0...12, 1)
                    note(dayStartHour == 0
                         ? tr("اليوم يبدأ من منتصف الليل. إن كنت تسهر، اجعله مثلاً 4 ص حتى لا ينقسم سهرك على يومين.",
                              "The day starts at midnight. If you work late, set e.g. 4 AM so a late session isn't split across two days.")
                         : tr("ما تعمله قبل هذه الساعة يُحسب لليوم السابق، ويبدأ الشعار عدّه من جديد عندها.",
                              "Work before this hour counts toward the previous day; the logo starts counting again from here."))
                }

                section(tr("الشهر", "Month")) {
                    stepper(tr("يبدأ الشهر يوم", "Month starts on day"), "\(monthStartDay)",
                            Binding(get: { Double(monthStartDay) }, set: { monthStartDay = Int($0); model.refresh() }), 1...31, 1)
                    note(monthStartDay == 1
                         ? tr("الشهر ميلادي كامل: من يوم 1 إلى آخر الشهر.", "Calendar month: from the 1st to the last day.")
                         : tr("الشهر من يوم \(monthStartDay) حتى اليوم السابق له في الشهر التالي — مناسب لمن يحسب الشهر من يوم الاشتراك."
                              + (monthStartDay > 28 ? " في الأشهر الأقصر يبدأ من آخر يوم فيها." : ""),
                              "From day \(monthStartDay) to the day before it next month — useful if you count your month from your subscription day."
                              + (monthStartDay > 28 ? " In shorter months it starts on their last day." : "")))
                    note(tr("يُحفظ كل شهر ينتهي تلقائياً كمرجع ثابت، وتجده في الإحصائيات ضمن «الأشهر السابقة».",
                            "Each finished month is saved automatically as a fixed reference — see “Previous months” in Statistics."))
                }

                section(tr("القياس", "Tracking")) {
                    stepper(tr("احسبني خاملاً بعد", "Idle after"), "\(Int(idleMinutes)) " + tr("د", "min"), $idleMinutes, 1...10, 1)
                    note(tr("كلما قصرت المدة كان القياس أدق، لكن القراءة الطويلة دون تحريك الفأرة قد تُحسب خمولاً.",
                            "Shorter is more precise, but long reading without moving the mouse may count as idle."))
                }

                section(tr("التنبيهات الصحية", "Health reminders")) {
                    toggle(tr("ذكّرني بالراحة", "Remind me to take breaks"), $breakEnabled)
                    stepper(tr("بعد عمل متواصل مدته", "After continuous work of"), "\(Int(breakMinutes)) " + tr("د", "min"),
                            $breakMinutes, 15...120, 5).opacity(breakEnabled ? 1 : 0.4).disabled(!breakEnabled)
                    Hairline()
                    toggle(tr("نبّهني عند تجاوز حدّ يومي", "Alert me past a daily limit"), $dailyLimitEnabled)
                    stepper(tr("الحدّ اليومي", "Daily limit"), (dailyLimitHours * 3600).durationText(),
                            $dailyLimitHours, 1...16, 0.5).opacity(dailyLimitEnabled ? 1 : 0.4).disabled(!dailyLimitEnabled)
                    Hairline()
                    toggle(tr("ملخّص أسبوعي", "Weekly summary"), $weeklySummaryEnabled)
                }

                section(tr("النظام", "System")) {
                    toggle(tr("شغّل ميزان مع تشغيل الجهاز", "Open Mizan at login"),
                           Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                    HStack {
                        Text("Accessibility")
                        Spacer()
                        if model.hasAccessibility {
                            Text(tr("ممنوحة", "Granted")).foregroundStyle(pal.gold)
                        } else {
                            Button(tr("منح الصلاحية", "Grant access")) { Tracker.requestAccessibility() }
                                .buttonStyle(QuietButton(primary: true))
                        }
                    }
                    Button(tr("إعادة قراءة سجلات Code و Cowork", "Re-read Code and Cowork logs")) { model.runImport() }
                        .buttonStyle(QuietButton()).disabled(model.importing)
                }

                section(tr("الخصوصية", "Privacy")) {
                    note(tr("لا يتصل ميزان بالإنترنت، ولا يقرأ نصوص محادثاتك. كل البيانات في ملف واحد على جهازك:",
                            "Mizan never connects to the internet and never reads your conversations. All data lives in one file on your Mac:"))
                    Text("~/Library/Application Support/Mizan/mizan.sqlite")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(pal.muted)
                        .textSelection(.enabled).environment(\.layoutDirection, .leftToRight)
                }

                DeveloperCredit().padding(.top, 4)
            }
            }
            .padding(.horizontal, 26).padding(.top, 40).padding(.bottom, 26)
        }
        .frame(width: 460, height: 700)
        .ignoresSafeArea()
        // نفس زجاج القائمة ونفس مقياس الشفافية
        .glassSheet(transparency: transparency, radius: 24)
        .onAppear { model.refresh() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(22)
    }

    private func toggle(_ t: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) { Text(t) }.toggleStyle(.switch).tint(.mizanOn)
    }

    private func stepper(_ t: String, _ value: String, _ b: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double) -> some View {
        HStack {
            Text(t)
            Spacer()
            Button { b.wrappedValue = max(range.lowerBound, b.wrappedValue - step) } label: { Image(systemName: "minus") }
                .buttonStyle(QuietButton())
            Text(value).font(.display(16)).monospacedDigit().frame(minWidth: 64)
            Button { b.wrappedValue = min(range.upperBound, b.wrappedValue + step) } label: { Image(systemName: "plus") }
                .buttonStyle(QuietButton())
        }
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.mz(11)).foregroundStyle(pal.faint).fixedSize(horizontal: false, vertical: true)
    }
}
