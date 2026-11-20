import SwiftUI

/// When a lake's storm lights run, from data/shore-lights.json via the forecast
/// file (warnings.shoreLightsSeason): 1 April to 31 October on most Bavarian
/// lakes, all year on Lake Constance. Unknown seasons keep the summer wording.
enum ShoreLightsSeason: Equatable {
    case aprilToOctober
    case allYear
    case unknown

    init(_ name: String?) {
        switch name {
        case "apr-oct": self = .aprilToOctober
        case "all-year": self = .allYear
        default: self = .unknown
        }
    }

    /// What the card says on a date: the rule is in testdata/states/shore-lights-season.json,
    /// which the website's tests read too. The date counts in German time.
    enum State: String { case on, off, soon }

    func state(at date: Date) -> State {
        guard self == .aprilToOctober else { return .on }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        if (4...10).contains(month) { return .on }
        if month == 3 && day >= 15 { return .soon }
        return .off
    }
}

/// What the lake's shore warning lights mean, where DWD runs the lake warning
/// service (Bavarian notice "Sturmwarndienst auf bayerischen Seen", AllMBl. 2010 S. 170).
/// Out of season the row says first that the lights are off (owner, 20 Nov 2026,
/// decision 0052), and still opens the explanation.
struct ShoreLightsGuide: View {
    let season: ShoreLightsSeason
    let now: Date
    @State private var open: Bool

    init(startOpen: Bool = false, season: ShoreLightsSeason = .unknown, now: Date = .now) {
        self.season = season
        self.now = now
        _open = State(initialValue: startOpen || UserDefaults.standard.bool(forKey: DefaultsKey.shoreLights))
    }

    var body: some View {
        let state = season.state(at: now)
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                if state != .on {
                    Text(tr("From November to March nothing flashes on the shore, even in a storm. Check the warnings here and the forecast yourself."))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    row(flashes: 40, color: .orange, title: tr("Strong-wind warning"),
                        text: tr("Wind or gusts of Beaufort 6 to 7 (39 to 61 km/h) are expected. Boats on the water head for the shore; small boats stay ashore. The rowing light is red for small racing and training boats and amber for the others."))
                    row(flashes: 90, color: .red, title: tr("Storm warning"),
                        text: tr("Beaufort 8 or more (62 km/h and above). Go ashore at once and do not launch. The rowing light is red for every boat."))
                }
                .opacity(state == .on ? 1 : 0.6)
                Text(season == .allYear
                     ? tr("The lights here run all year, for shorter hours in winter. Outside these times there is no light, so check the forecast yourself.")
                     : tr("The lights run from 1 April to 31 October, usually from 7:00 to 22:00; times may vary by lake. Outside these times there is no light, so check the forecast yourself."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            switch state {
            case .on:
                Label(tr("What the shore warning lights mean"), systemImage: "light.beacon.max")
                    .font(.subheadline.weight(.semibold))
            case .off, .soon:
                Label {
                    Text(state == .off ? tr("Storm lights off until 1 April") : tr("Storm lights back on from 1 April"))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "light.beacon.min")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
            }
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
