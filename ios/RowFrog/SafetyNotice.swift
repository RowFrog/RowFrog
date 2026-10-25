import SwiftUI

/// The safety notice every user accepts before using the app: Row Frog gives
/// advice, the rower decides. It comes before the tour, cannot be skipped and
/// needs a tick and a tap. The accepted version and date stay on the phone;
/// raising `version` asks everyone to accept the changed text again.
enum SafetyNotice {
    /// Raise when the text changes in a way users must see again.
    static let version = 1
    static let versionKey = "RWSafetyAcceptedVersion"
    static let dateKey = "RWSafetyAcceptedAt"

    static var acceptedVersion: Int { UserDefaults.standard.integer(forKey: versionKey) }

    static var acceptedAt: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    /// `-RWSafetyAccepted YES` skips the notice for screenshots.
    static var needsAcceptance: Bool {
        !UserDefaults.standard.bool(forKey: "RWSafetyAccepted") && acceptedVersion < version
    }

    /// Accepted before, but an older text.
    static var changedSinceAcceptance: Bool { acceptedVersion > 0 && acceptedVersion < version }

    static func accept(at date: Date = .now) {
        UserDefaults.standard.set(version, forKey: versionKey)
        UserDefaults.standard.set(date, forKey: dateKey)
    }

    static var title: String { tr("Before you row") }

    static var points: [SafetyPoint] {
        [
            SafetyPoint(symbol: "info.circle", title: tr("Row Frog gives information and advice, not decisions."),
                        text: tr("Forecasts, rowing lights, limits and maps are calculated from weather models and measurements by third parties. They can be wrong, late or missing, and conditions on the water can change faster than any forecast.")),
            SafetyPoint(symbol: "light.beacon.max", title: tr("Green does not mean safe, and red does not cover every danger."),
                        text: tr("The app does not know your skills, your fitness, your boat and equipment, or what you see on the water.")),
            SafetyPoint(symbol: "person.fill.checkmark", title: tr("You decide."),
                        text: tr("Whether you go out and when you turn back is always your own decision, and that of your crew, cox or coach, whatever the app shows.")),
            SafetyPoint(symbol: "person.2.fill", title: tr("When in doubt, ask or stay ashore."),
                        text: tr("Ask experienced rowers, your coach or your club's boat warden, or stay ashore.")),
            SafetyPoint(symbol: "figure.and.child.holdinghands", title: tr("Under 18?"),
                        text: tr("Decide together with your coach or your parents, and follow your club's rules for young rowers.")),
            SafetyPoint(symbol: "list.bullet.clipboard", title: tr("Always follow the rules."),
                        text: tr("Your club's rowing rules, local regulations, official warnings such as storm warning lights, and instructions from authorities and the water police come first.")),
            SafetyPoint(symbol: "exclamationmark.shield", title: tr("Use at your own risk."),
                        text: tr("To the extent permitted by law, we accept no liability for decisions made on the basis of the app's data and advice.")),
        ]
    }

    static var confirmation: String {
        tr("I have read this and understand that Row Frog only gives advice. I alone decide whether and when I go on the water.")
    }
}

struct SafetyPoint: Hashable {
    let symbol: String
    let title: String
    let text: String
}

/// The notice's points, shared by the first-start page and the settings.
private struct SafetyPointsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(SafetyNotice.points, id: \.self) { point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: point.symbol)
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(point.title).font(.headline)
                        Text(point.text).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The first-start page. No close button and no swipe: the only way on is to
/// read to the end, tick the box and tap "Agree and continue".
struct SafetyNoticeView: View {
    let accept: () -> Void
    @State private var readToEnd = false
    @State private var ticked = false
    private let changed = SafetyNotice.changedSinceAcceptance

    var body: some View {
        VStack(spacing: 0) {
            // The settings can't be reached yet, so the language is chosen here:
            // every choice the settings offer, the device's language first and preset.
            Picker(tr("Language"), selection: Binding(
                get: { AppSettings.shared.language },
                set: { AppSettings.shared.language = $0 }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language == .device ? tr("Device") : language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .padding(.top, 8)
            .padding(.horizontal)
            ScrollView {
                // Lazy, so the end marker only appears once it is scrolled into view.
                LazyVStack(spacing: 20) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(SafetyNotice.title).font(.largeTitle.bold())
                        if changed {
                            Label(tr("This notice has changed. Please read it again."), systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .multilineTextAlignment(.center)
                    SafetyPointsList()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    Color.clear
                        .frame(height: 1)
                        .onAppear { readToEnd = true }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 12) {
                Button {
                    ticked.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: ticked ? "checkmark.square.fill" : "square")
                            .font(.title2)
                            .foregroundStyle(ticked ? Color.accentColor : .secondary)
                        Text(SafetyNotice.confirmation)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!readToEnd)
                .opacity(readToEnd ? 1 : 0.5)
                .accessibilityAddTraits(ticked ? .isSelected : [])
                if !readToEnd {
                    Label(tr("Scroll to the end to continue."), systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    SafetyNotice.accept()
                    accept()
                } label: {
                    Text(tr("Agree and continue"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!(readToEnd && ticked))
            }
            .padding()
            .frame(maxWidth: 640)
            .background(.bar)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.locale, AppSettings.shared.locale)
        .interactiveDismissDisabled()
    }
}

/// The notice again, from the settings, with the day it was accepted.
struct SafetyNoticeSettingsView: View {
    var body: some View {
        List {
            Section {
                SafetyPointsList().padding(.vertical, 6)
            } footer: {
                if let date = SafetyNotice.acceptedAt {
                    Text(tr("You accepted this notice on %@.", date.formatted(.dateTime.day().month(.wide).year().locale(AppSettings.shared.locale))))
                }
            }
        }
        .navigationTitle(SafetyNotice.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
