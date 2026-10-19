import SwiftUI

/// Official DWD warnings for the location: the lake warning (strong wind or
/// storm, as the shore lights show it) where DWD covers the lake, and the
/// weather warnings for the place. Says plainly when there is none, and when
/// DWD could not be checked.
struct WarningsCard: View {
    let warnings: Warnings
    let lakeName: String?
    let town: String?
    let checkedAt: Date

    var body: some View {
        Card(title: tr("DWD warnings"), symbol: "exclamationmark.triangle") {
            if !warnings.checked {
                Label(tr("Warnings could not be loaded. Check dwd.de or the shore lights before going out."), systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            } else if warnings.items.isEmpty {
                Label(tr("No warning right now"), systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(coverage + " " + tr("Checked %@.", Format.time(checkedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(warnings.items) { WarningRow(warning: $0) }
                Text(coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    /// What was checked: the lake warning service where DWD runs one, and the place.
    private var coverage: String {
        let place = town.map { tr("weather warnings for %@", $0) } ?? tr("weather warnings for this place")
        if let area = warnings.lakeArea {
            return tr("Covers the DWD lake warning for %@ and %@.", area, place)
        }
        let water = lakeName.map { tr("for %@", $0) } ?? tr("for this water")
        return tr("DWD has no lake warning service %@. Covers %@.", water, place)
    }
}

private struct WarningRow: View {
    let warning: DWDWarning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(warning.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: warning.isLake ? "light.beacon.max.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(warning.color)
                    Text((warning.isLake ? tr("Lake warning") : tr("Weather warning")) + " · \(warning.area)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if warning.sample == true {
                        Text(tr("SAMPLE"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityLabel(tr("Sample warning for the preview, not from DWD"))
                    }
                }
                if warningsInEnglish, let english = warning.english {
                    Text(english.headline).font(.headline)
                    if let period = period {
                        Label(period, systemImage: "clock").font(.caption)
                    }
                    Text(english.description ?? tr("DWD publishes the details of this warning in German only; see the original below."))
                        .fixedSize(horizontal: false, vertical: true)
                    if let instruction = english.instruction, !instruction.isEmpty {
                        Text(instruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GermanOriginal(warning: warning)
                } else {
                    Text(warning.headline).font(.headline)
                    if let period = period {
                        Label(period, systemImage: "clock").font(.caption)
                    }
                    Text(warning.description).fixedSize(horizontal: false, vertical: true)
                    if let instruction = warning.instruction, !instruction.isEmpty {
                        Text(instruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var period: String? {
        switch (warning.onset, warning.expires) {
        case let (onset?, expires?): tr("%@ until %@", Format.dayTime(onset), Format.dayTime(expires))
        case let (onset?, nil): tr("From %@", Format.dayTime(onset))
        case let (nil, expires?): tr("Until %@", Format.dayTime(expires))
        default: nil
        }
    }
}

/// DWD's German text under the English one, for completeness.
private struct GermanOriginal: View {
    let warning: DWDWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(tr("Original from DWD (German)"), systemImage: "character.book.closed")
                .font(.caption2.weight(.semibold))
            Text(warning.headline).font(.caption.weight(.semibold))
            Text(warning.description).font(.caption)
            if let instruction = warning.instruction, !instruction.isEmpty {
                Text(instruction).font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .environment(\.locale, Locale(identifier: "de_DE"))
        .accessibilityElement(children: .combine)
    }
}

/// Whether DWD warnings are shown in English: when the app is in English.
var warningsInEnglish: Bool { AppSettings.shared.resolvedLanguage == .english }

extension DWDWarning {
    /// DWD's warning colours: yellow, orange, red, dark red.
    var color: Color {
        switch severity {
        case "extreme": Color(red: 0.55, green: 0, blue: 0.3)
        case "severe": .red
        case "moderate": .orange
        default: .yellow
        }
    }

    /// Short label for the location list, e.g. "DWD lake warning" or "DWD warning: Wind gusts".
    var shortLabel: String {
        if isLake { return tr("DWD lake warning") }
        if warningsInEnglish, let english {
            return tr("DWD warning: %@", english.event.prefix(1).uppercased() + english.event.dropFirst())
        }
        return tr("DWD warning: %@", event.capitalized(with: Locale(identifier: "de_DE")))
    }
}
