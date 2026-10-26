import SwiftUI

/// Official DWD warnings for the location: the lake warning (strong wind or
/// storm, as the shore lights show it) where DWD covers the lake, and the
/// weather warnings for the place. Says plainly when there is none, and when
/// DWD could not be checked. Outside Germany DWD does not warn for the place,
/// so the card names the country's own service instead of saying "no warning".
struct WarningsCard: View {
    let warnings: Warnings
    let lakeName: String?
    let town: String?
    let checkedAt: Date
    /// Opens the shore lights guide from the start, where the card is shown to explain them.
    var guideOpen = false

    var body: some View {
        Card(title: warnings.localChecked && warnings.isDWD ? tr("DWD warnings") : tr("Official warnings"), symbol: "exclamationmark.triangle") {
            if !warnings.checked {
                Label(warnings.isDWD
                      ? tr("Warnings could not be loaded. Check dwd.de or the shore lights before going out.")
                      : tr("Warnings could not be loaded. Check %@ or the shore lights before going out.", warnings.local?.service ?? "DWD"),
                      systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            } else if !warnings.localChecked {
                ForEach(warnings.items.filter(\.isLake)) { WarningRow(warning: $0) }
                NotCheckedNote(local: warnings.local)
                Text(coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if warnings.lakeArea != nil { ShoreLightsGuide(startOpen: guideOpen) }
            } else if warnings.items.isEmpty {
                Label(tr("No warning right now"), systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(coverage + " " + tr("Checked %@.", Format.time(checkedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // The shore lights explained right under the lake warning, before the weather warnings.
                ForEach(warnings.items.filter(\.isLake)) { WarningRow(warning: $0) }
                if warnings.lakeArea != nil { ShoreLightsGuide(startOpen: guideOpen) }
                ForEach(warnings.items.filter { !$0.isLake }) { WarningRow(warning: $0) }
                Text(coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if warnings.checked, warnings.localChecked, warnings.items.isEmpty, warnings.lakeArea != nil {
                ShoreLightsGuide(startOpen: guideOpen)
            }
        }
        .font(.subheadline)
    }

    /// What was checked: the lake warning service where DWD runs one, and the place.
    private var coverage: String {
        if !warnings.localChecked {
            let place = town ?? tr("this place")
            if let area = warnings.lakeArea {
                return tr("Covers the DWD lake warning for %@. Weather warnings for %@ are not checked yet.", area, place)
            }
            return tr("Lake and weather warnings for %@ are not checked yet.", place)
        }
        if !warnings.isDWD {
            let service = warnings.local?.service ?? ""
            let place = town ?? tr("this place")
            if let area = warnings.lakeArea {
                return tr("Covers the DWD lake warning for %@ and the warnings of %@ for %@.", area, service, place)
            }
            return tr("Covers the warnings of %@ for %@. Lake warnings for this water are not published for apps.", service, place)
        }
        let place = town.map { tr("weather warnings for %@", $0) } ?? tr("weather warnings for this place")
        if let area = warnings.lakeArea {
            return tr("Covers the DWD lake warning for %@ and %@.", area, place)
        }
        let water = lakeName.map { tr("for %@", $0) } ?? tr("for this water")
        return tr("DWD has no lake warning service %@. Covers %@.", water, place)
    }
}

/// Outside Germany: the place's own weather service warns, and Row Frog does not read it yet.
private struct NotCheckedNote: View {
    let local: LocalWarnings?

    var body: some View {
        let service = local?.service ?? tr("the national weather service")
        VStack(alignment: .leading, spacing: 6) {
            Label(tr("Row Frog cannot check the weather warnings for this place yet. Check %@ before going out.", service), systemImage: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if let link = local?.url.flatMap(URL.init(string:)) {
                Link(destination: link) {
                    Label(tr("Open the warnings of %@", service), systemImage: "arrow.up.right.square")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
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
                            .accessibilityLabel(tr("Sample warning for the preview, not an official warning"))
                    }
                }
                if warningsInEnglish, let english = warning.english {
                    Text(english.headline).font(.headline)
                    if let period = period {
                        Label(period, systemImage: "clock").font(.caption)
                    }
                    Text(english.description ?? (warning.isDWD
                        ? tr("DWD publishes the details of this warning in German only; see the original below.")
                        : tr("The details of this warning are in German only; see the original below.")))
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

/// What the lake's shore warning lights mean, where DWD runs the lake warning
/// service (Bavarian notice "Sturmwarndienst auf bayerischen Seen", AllMBl. 2010 S. 170).
struct ShoreLightsGuide: View {
    @State private var open: Bool

    init(startOpen: Bool = false) {
        _open = State(initialValue: startOpen || UserDefaults.standard.bool(forKey: "RWShoreLights"))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                row(flashes: 40, color: .orange, title: tr("Strong-wind warning"),
                    text: tr("Wind or gusts of Beaufort 6 to 7 (39 to 61 km/h) are expected. Boats on the water head for the shore; small boats stay ashore. The rowing light is red for small racing and training boats and amber for the others."))
                row(flashes: 90, color: .red, title: tr("Storm warning"),
                    text: tr("Beaufort 8 or more (62 km/h and above). Go ashore at once and do not launch. The rowing light is red for every boat."))
                Text(tr("The lights run from 1 April to 31 October, usually from 7:00 to 22:00; times may vary by lake. Outside these times there is no light, so check the forecast yourself."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Label(tr("What the shore warning lights mean"), systemImage: "light.beacon.max")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func row(flashes: Int, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "light.beacon.max.fill")
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("%@ flashes a minute: %@", "\(flashes)", title)).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// DWD's German text under the English one, for completeness.
private struct GermanOriginal: View {
    let warning: DWDWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(warning.isDWD ? tr("Original from DWD (German)") : tr("Original from %@ (German)", warning.serviceShort), systemImage: "character.book.closed")
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
        let name = warningsInEnglish && english != nil
            ? english!.event.prefix(1).uppercased() + english!.event.dropFirst()
            : event.capitalized(with: Locale(identifier: "de_DE"))
        return isDWD ? tr("DWD warning: %@", name) : tr("%@ warning: %@", serviceShort, name)
    }
}
