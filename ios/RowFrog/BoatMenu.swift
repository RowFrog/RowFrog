import SwiftUI

/// Picks the boat the rowing light is worked out for, right on a club page:
/// from the "For small boats" line in the top tile and the boat button in the
/// page bar. Each boat shows the light it would get at this club now, so the
/// one that would be fine stands out. The choice is the one in the settings,
/// for every club and the widgets. Own boats kept at other clubs come last,
/// with one tap to take them to this club too (owner's choice A, 30.10.2026).
struct BoatMenu<MenuLabel: View>: View {
    /// The club whose page shows the menu.
    var clubID: String?
    /// The hour the lights are worked out for; without it each boat shows its kind.
    var hour: ForecastHour?
    var waterC: Double?
    @ViewBuilder let label: () -> MenuLabel
    @Environment(\.openBoatSettings) private var openBoatSettings
    @Environment(\.clubName) private var clubName

    var body: some View {
        let settings = AppSettings.shared
        let away = settings.myBoats.filter { !settings.isKept($0, at: clubID) }
        Menu {
            Section(tr("Rowing light for")) {
                ForEach(Boat.groups) { row($0) }
            }
            let here = settings.boats(keptAt: clubID)
            if !here.isEmpty {
                Section(away.isEmpty ? tr("My boats") : tr("Your boats here")) {
                    ForEach(here) { row($0) }
                }
            }
            if let clubID, !away.isEmpty {
                Section(tr("At other clubs")) {
                    ForEach(away) { boat in
                        Button {
                            settings.keep(boat.id, at: clubID)
                            settings.pick(boat.id, at: clubID)
                        } label: {
                            Label(boat.title, systemImage: "arrow.down.circle")
                            Text(tr("At %@ · tap to take it here", boat.clubs.map(clubName).formatted(.list(type: .and))))
                        }
                    }
                }
            }
            if let openBoatSettings {
                Section {
                    Button(action: openBoatSettings) {
                        Label(tr("Boats and limits…"), systemImage: "slider.horizontal.3")
                    }
                }
            }
        } label: {
            label()
        }
    }

    /// A tick at the boat in use; under its name the light it gets now.
    private func row(_ boat: Boat) -> some View {
        let settings = AppSettings.shared
        return Toggle(isOn: Binding(
            get: { settings.boat(at: clubID).id == boat.id },
            set: { if $0 { settings.pick(boat.id, at: clubID) } }
        )) {
            Text(boat.title)
            Text(subtitle(boat))
        }
    }

    private func subtitle(_ boat: Boat) -> String {
        guard let hour else { return boat.detail }
        let light = hour.applying(AppSettings.shared.limits(for: boat), waterC: waterC).light
        return "\(light.emoji) \(light.title)"
    }
}

extension Boat {
    /// The boat's class for the page bar, as rowers write it: "2x", "4+".
    /// The two groups have none of their own, so they show their seats.
    var classTag: String {
        switch id {
        case Self.small.id: "1–2"
        case Self.big.id: "4–8"
        default: boatClass.rawValue
        }
    }
}

/// The boat button's symbol: the class in a small frame, dashed for the two
/// groups, in the accent colour for one of the user's own boats.
struct BoatClassTag: View {
    let boat: Boat

    var body: some View {
        Text(boat.classTag)
            .font(.system(size: boat.classTag.count > 2 ? 11 : 13, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(minWidth: 30, minHeight: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.6, dash: boat.isGroup ? [3, 2.2] : []))
            }
            .foregroundStyle(boat.isGroup ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
    }
}

extension Light {
    /// For menus, where a coloured symbol shows in one colour.
    var emoji: String {
        switch self {
        case .green: "🟢"
        case .amber: "🟠"
        case .red: "🔴"
        }
    }
}

private struct ClubNameKey: EnvironmentKey {
    static let defaultValue: (String) -> String = { $0 }
}

private struct OpenBoatSettingsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens Settings > Boats and limits; nil where the settings cannot open from here.
    var openBoatSettings: (() -> Void)? {
        get { self[OpenBoatSettingsKey.self] }
        set { self[OpenBoatSettingsKey.self] = newValue }
    }

    /// A club's name from its id, for "At MRC 1880" in the boat menu.
    var clubName: (String) -> String {
        get { self[ClubNameKey.self] }
        set { self[ClubNameKey.self] = newValue }
    }
}
