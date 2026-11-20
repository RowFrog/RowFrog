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
    /// True when DWD did not answer the last check and an earlier one is shown: its time is then given.
    var earlierCheck = false
    /// Opens the shore lights guide from the start, where the card is shown to explain them.
    var guideOpen = false
    /// The moment "now" and "later" are told apart; nil follows the clock, minute by
    /// minute, and the screenshots can fix it.
    var checkedNow: Date? = nil

    var body: some View {
        // Grouped again every minute, and warnings that have ended left out: a gust
        // warning until 17:00 still stood under "Later" at 17:02, because the card
        // took "now" once, when it was drawn, and kept every warning the file had
        // (owner's screenshot, 17 Nov 2026).
        TimelineView(.everyMinute) { context in
            card(now: checkedNow ?? context.date)
        }
    }

    private func card(now checkedNow: Date) -> some View {
        let warnings = self.warnings.current(at: checkedNow)
        return Card(title: tr("Official warnings"), symbol: "exclamationmark.triangle") {
            if !warnings.checked {
                Label(warnings.isDWD
                      ? tr("Warnings could not be loaded. Check dwd.de or the shore lights before going out.")
                      : tr("Warnings could not be loaded. Check %@ or the shore lights before going out.", warnings.local?.service ?? "DWD"),
                      systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            } else if !warnings.localChecked {
                ForEach(warnings.items.filter(\.isLake)) { WarningRow(warning: $0) }
                NotCheckedNote(local: warnings.local)
                lightsInfo(now: checkedNow)
                Text(coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if warnings.items.isEmpty {
                Label(tr("No warning right now"), systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                lightsInfo(now: checkedNow)
                Text(coverage + " " + tr("Checked %@.", Format.time(checkedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // One order in every state (owner, 20 Nov 2026, decision 0052): the warnings,
                // then the shore lights, then what was checked. The lake warning itself
                // says how many times the lights flash.
                ForEach(warnings.items.filter(\.isLake)) { WarningRow(warning: $0) }
                let local = warnings.items.filter { !$0.isLake }
                let now = local.filter { $0.isActive(at: checkedNow) }
                let later = local.filter { !$0.isActive(at: checkedNow) }.sorted { ($0.onset ?? .distantPast) < ($1.onset ?? .distantPast) }
                // "Now" and "Later" so a warning for tonight is not read as one for this hour.
                if !now.isEmpty && !later.isEmpty { SectionLabel(text: tr("Now")) }
                ForEach(now) { WarningRow(warning: $0) }
                if !later.isEmpty { SectionLabel(text: tr("Later")) }
                ForEach(later) { WarningRow(warning: $0) }
                lightsInfo(now: checkedNow)
                Text(earlierCheck ? coverage + " " + tr("Checked %@.", Format.time(checkedAt)) : coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    /// The shore lights explained where the lake has them; where DWD warns for the
    /// lake without lights (e.g. the Alster), one line saying so instead.
    @ViewBuilder private func lightsInfo(now: Date) -> some View {
        if warnings.lakeArea != nil {
            if warnings.shoreLights ?? true {
                ShoreLightsGuide(startOpen: guideOpen, season: ShoreLightsSeason(warnings.shoreLightsSeason), now: now)
            } else {
                Label(tr("This lake has no storm warning lights on the shore. DWD's lake warning shows here in the app."), systemImage: "light.beacon.min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

/// "Now" or "Later" above the warnings it groups.
private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
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
                if warning.isInfoOnly {
                    Label(warning.isSlippery
                          ? tr("Not part of the rowing light. The jetty and boat area may be slippery.")
                          : tr("Not part of the rowing light: it is not about the water."),
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SourceLinks(warning: warning)
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

/// Where the warning can be read at the service that issued it. No service has a
/// page for a single warning, so this opens its page for the place: DWD's town page
/// (or inland lake page), GeoSphere's map at the launch point, MeteoSwiss's hazards
/// page, which the MeteoSwiss app opens itself where it is installed. DWD's
/// WarnWetter app cannot be opened at a place, so it is offered via the App Store.
struct SourceLinks: View {
    let warning: DWDWarning

    var body: some View {
        if let url = warning.sourceURL {
            VStack(alignment: .leading, spacing: 4) {
                Link(destination: url) {
                    Label(warning.source == "meteoswiss"
                          ? tr("Show in the MeteoSwiss app or website")
                          : tr("Show on the %@ website", warning.serviceShort),
                          systemImage: "arrow.up.right.square")
                }
                if warning.isDWD {
                    Link(destination: DWDWarning.warnWetterAppStore) {
                        Label(tr("DWD WarnWetter app in the App Store"), systemImage: "arrow.down.app")
                    }
                    .font(.caption)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 2)
        }
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

    /// Over at `date`: its end has passed.
    func hasEnded(at date: Date) -> Bool { expires.map { $0 <= date } ?? false }

    /// In force at `date`: begun (or no start given) and not yet expired.
    func isActive(at date: Date) -> Bool {
        (onset ?? .distantPast) <= date && date < (expires ?? .distantFuture)
    }

    /// The issuing service's page for the warning's place, in the app's language.
    var sourceURL: URL? {
        guard let links else { return nil }
        return (links[warningsInEnglish ? "en" : "de"] ?? links["de"]).flatMap(URL.init(string:))
    }

    /// DWD's WarnWetter app (App Store id 986420993); the store shows "Open" where it is installed.
    static let warnWetterAppStore = URL(string: "https://apps.apple.com/de/app/id986420993")!

    /// Changes the rowing light: lake warnings and weather warnings about the water.
    var counts: Bool { !isInfoOnly }

    /// "23:00" today, else "Tomorrow 08:00", for "from …" in short lines.
    var startText: String? {
        guard let onset else { return nil }
        return Calendar.current.isDateInToday(onset) ? Format.time(onset) : Format.dayTime(onset)
    }

    /// Short label for the location list, e.g. "DWD lake warning" or "DWD warning: Wind gusts".
    var shortLabel: String {
        if isLake { return tr("DWD lake warning") }
        return isDWD ? tr("DWD warning: %@", eventName) : tr("%@ warning: %@", serviceShort, eventName)
    }

    /// The event alone, e.g. "Frost" or "Wind gusts".
    var eventName: String {
        if isLake { return tr("DWD lake warning") }
        return warningsInEnglish && english != nil
            ? english!.event.prefix(1).uppercased() + english!.event.dropFirst()
            : event.capitalized(with: Locale(identifier: "de_DE"))
    }
}

/// How a warning shows in the short lines (club list, top tile): "now, later, info only".
enum WarningUrgency {
    /// Counts for the rowing light and is in force now: amber or red.
    case now
    /// Counts and starts within the next hours: amber, with its start time.
    case soon
    /// Starts later, or is about frost, heat and the like: grey, with an info sign.
    case info
}

extension Warnings {
    /// The same warnings without those that have ended by `date`: the file can be up
    /// to half an hour old (or 3 h with an earlier check), the clock moves on.
    func current(at date: Date) -> Warnings {
        var copy = self
        copy.items = items.filter { !$0.hasEnded(at: date) }
        return copy
    }

    /// Counting warnings starting within this many hours already show amber in the list.
    static let soonHours: Double = 3

    /// The one warning the short lines show, and how: in force and counting first,
    /// then counting soon, then the earliest other one.
    func headline(at date: Date = .now) -> (warning: DWDWarning, urgency: WarningUrgency)? {
        let current = items.filter { $0.expires.map { $0 > date } ?? true }
        let rank = ["extreme", "severe", "moderate", "minor"]
        func worst(_ list: [DWDWarning]) -> DWDWarning? {
            list.min { (rank.firstIndex(of: $0.severity) ?? 4) < (rank.firstIndex(of: $1.severity) ?? 4) }
        }
        if let w = worst(current.filter { $0.counts && $0.isActive(at: date) }) { return (w, .now) }
        let soonEnd = date.addingTimeInterval(Self.soonHours * 3600)
        if let w = worst(current.filter { $0.counts && ($0.onset ?? date) < soonEnd }) { return (w, .soon) }
        if let w = current.min(by: { ($0.onset ?? date) < ($1.onset ?? date) }) { return (w, .info) }
        return nil
    }
}

extension DWDWarning {
    /// The list's line: "DWD warning: Frost" while in force, else "DWD warning: Frost from 23:00".
    func shortLabel(at date: Date) -> String {
        if isActive(at: date) { return shortLabel }
        return startText.map { tr("%@ from %@", shortLabel, $0) } ?? shortLabel
    }

    /// For the list's narrow column: "Frost from 23:00", the event and its start only.
    func compactLabel(at date: Date) -> String {
        if isActive(at: date) { return eventName }
        return startText.map { tr("%@ from %@", eventName, $0) } ?? eventName
    }
}
