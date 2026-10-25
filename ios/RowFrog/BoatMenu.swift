import SwiftUI

/// Picks the boat the rowing light is worked out for, right on a club page:
/// from the "For small boats" line in the top tile and the boat button in the
/// page bar. Each boat shows the light it would get at this club now, so the
/// one that would be fine stands out. The choice is the one in the settings,
/// for every club and the widgets.
struct BoatMenu<MenuLabel: View>: View {
    /// The hour the lights are worked out for; without it each boat shows its kind.
    var hour: ForecastHour?
    var waterC: Double?
    @ViewBuilder let label: () -> MenuLabel
    @Environment(\.openBoatSettings) private var openBoatSettings

    var body: some View {
        let settings = AppSettings.shared
        Menu {
            Section(tr("Rowing light for")) {
                ForEach(Boat.groups) { row($0) }
            }
            if !settings.myBoats.isEmpty {
                Section(tr("My boats")) {
                    ForEach(settings.myBoats) { row($0) }
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
            get: { settings.boatID == boat.id },
            set: { if $0 { settings.boatID = boat.id } }
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
    /// The boat's name for the page bar: "Small", "Big", its own name, or its
    /// class, as "4x", when it has none. The bar cuts long names short.
    var shortName: String {
        switch id {
        case Self.small.id: tr("Small")
        case Self.big.id: tr("Big")
        default:
            name.trimmingCharacters(in: .whitespaces).isEmpty ? boatClass.rawValue : name.trimmingCharacters(in: .whitespaces)
        }
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

private struct OpenBoatSettingsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens Settings > Boats and limits; nil where the settings cannot open from here.
    var openBoatSettings: (() -> Void)? {
        get { self[OpenBoatSettingsKey.self] }
        set { self[OpenBoatSettingsKey.self] = newValue }
    }
}
