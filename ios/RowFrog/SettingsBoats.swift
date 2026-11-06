import SwiftUI
import TipKit

// Settings > Boats and limits, a boat's page and the New boat sheet. Split off
// SettingsView.swift (5.11.2026, owner's rule for the very large files); the
// code moved unchanged apart from the settings review changes in the same PR.

/// The boats the rowing light can be for: small boats, big boats and the
/// user's own. Each has its own limits, behind ⓘ.
struct RowingLimitsView: View {
    @Binding var path: [SettingsRoute]
    let locations: LocationStore
    @State private var showBoatsTip = false
    /// The boat being added in the New boat sheet; it is kept only when Add is tapped.
    @State private var newBoat: NewBoat?
    private let boatsTip = MyBoatsTip()

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                if showBoatsTip {
                    TipView(boatsTip)
                }
                ForEach(Boat.groups) { boat in
                    BoatRow(boat: boat) { path.append(.boat(boat.id)) }
                }
            } header: {
                SectionTitle(tr("Your boat"), symbol: "figure.rower")
            }
            .surfaceRows()

            Section {
                let boats = settings.myBoats.filter { $0.id != newBoat?.id }
                ForEach(boats) { boat in
                    BoatRow(boat: boat) { path.append(.boat(boat.id)) }
                }
                .onDelete { offsets in
                    for id in offsets.map({ boats[$0].id }) { settings.removeBoat(id) }
                }
                Button {
                    newBoat = NewBoat(id: settings.addBoat(at: locations.homeID).id)
                } label: {
                    Label(tr("Add a boat"), systemImage: "plus.circle")
                }
            } header: {
                SectionTitle(tr("My boats"), symbol: "list.bullet")
            } footer: {
                SectionFooter(tr("Tap a boat to use it for the rowing light, ⓘ for its type and limits. Swipe to remove one."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .tipVisibility(boatsTip, $showBoatsTip)
        .navigationTitle(tr("Boats and limits"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $newBoat) { boat in
            NewBoatSheet(boatID: boat.id, locations: locations)
        }
        .onAppear {
            // Screenshot hook: `-RWNewBoat YES` with `-RWSettingsPage limits` opens the New boat sheet.
            if newBoat == nil, UserDefaults.standard.bool(forKey: "RWNewBoat") {
                newBoat = NewBoat(id: AppSettings.shared.addBoat(at: locations.homeID).id)
            }
        }
    }
}

private struct NewBoat: Identifiable {
    let id: String
}

/// Adding a boat, as creating something in Apple's own apps (a contact, an
/// event, an alarm): a sheet with Cancel and Add, where only Add keeps the boat
/// (owner, 4.11.2026; before, the back arrow saved it). Changing a boat later
/// saves on its own, as in iOS Settings.
private struct NewBoatSheet: View {
    let boatID: String
    let locations: LocationStore
    @Environment(\.dismiss) private var dismiss
    @State private var added = false

    var body: some View {
        let settings = AppSettings.shared
        let named = !(settings.boat(boatID)?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        NavigationStack {
            BoatLimitsView(boatID: boatID, locations: locations, isNew: true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Add")) {
                            added = true
                            dismiss()
                        }
                        .disabled(!named)
                    }
                }
        }
        // Only Cancel and Add close the sheet, so a boat is never kept or lost by a swipe.
        .interactiveDismissDisabled()
        .onDisappear {
            if !added { settings.removeBoat(boatID) }
        }
    }
}

/// A boat to tick, with a button to its limits.
private struct BoatRow: View {
    let boat: Boat
    let openLimits: () -> Void

    var body: some View {
        let settings = AppSettings.shared
        let changed = !(settings.boatLimits[boat.id] ?? [:]).isEmpty
        let ticked = settings.selectedBoat.id == boat.id
        // As Wi-Fi in iOS Settings: the tick on the left, the row picks the boat,
        // and ⓘ opens its details.
        HStack(spacing: 10) {
            Button {
                settings.boatID = boat.id
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .opacity(ticked ? 1 : 0)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boat.title).foregroundStyle(.primary)
                        Text(changed ? tr("%@ · your limits", boat.detail) : boat.detail)
                            .font(.caption)
                            .foregroundStyle(changed ? Color.orange : Color.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(ticked ? .isSelected : [])
            Button(action: openLimits) {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("Limits for %@", boat.title))
        }
    }
}

struct BoatLimitsView: View {
    let boatID: String
    let locations: LocationStore
    /// In the New boat sheet: no Remove button, and the sheet's Cancel and Add.
    var isNew = false
    /// Whether the limit list shows; off, the boat simply uses the app's limits
    /// for its type and size (owner's idea, 4.11.2026).
    @State private var ownLimits: Bool
    @State private var confirmAppLimits = false
    @State private var showColdTip = false
    private let coldTip = ColdWaterTip()
    @Environment(\.dismiss) private var dismiss

    init(boatID: String, locations: LocationStore, isNew: Bool = false) {
        self.boatID = boatID
        self.locations = locations
        self.isNew = isNew
        _ownLimits = State(initialValue: !(AppSettings.shared.boatLimits[boatID] ?? [:]).isEmpty)
    }

    var body: some View {
        @Bindable var settings = AppSettings.shared
        let boat = settings.boat(boatID) ?? .small
        let changed = !(settings.boatLimits[boat.id] ?? [:]).isEmpty
        Form {
            if !boat.isGroup, let index = settings.myBoats.firstIndex(where: { $0.id == boatID }) {
                Section {
                    TextField(tr("Name, e.g. the boat's name"), text: $settings.myBoats[index].name)
                    Picker(tr("Type"), selection: $settings.myBoats[index].type) {
                        ForEach(BoatType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Picker(tr("Size and rigging"), selection: $settings.myBoats[index].boatClass) {
                        ForEach(BoatClass.allCases) { boatClass in
                            Text(boatClass.title).tag(boatClass)
                        }
                    }
                } header: {
                    SectionTitle(tr("Boat"), symbol: "figure.rower")
                } footer: {
                    SectionFooter(boat.type.detail)
                }
                .surfaceRows()

                KeptAtSection(boat: boat, locations: locations)
            }

            Section {
                if showColdTip {
                    TipView(coldTip)
                }
                // As Date & Time > Set Automatically in iOS: the app's limits
                // by default, the list only when the user wants their own.
                Toggle(isOn: Binding {
                    !ownLimits
                } set: { useApp in
                    if !useApp {
                        withAnimation { ownLimits = true }
                    } else if changed {
                        confirmAppLimits = true
                    } else {
                        withAnimation { ownLimits = false }
                    }
                }) {
                    Text(tr("The app's limits for this boat"))
                }
                // While the app's limits are in use they stay in view, greyed, as the
                // time zone under Date & Time > Set Automatically in iOS.
                ForEach(RowingLimit.allCases) { limit in
                    LimitRow(limit: limit, boat: boat, editable: ownLimits)
                }
            } header: {
                SectionTitle(tr("Limits"), symbol: "slider.horizontal.3")
            } footer: {
                SectionFooter(ownLimits
                              ? tr("Warnings, thunderstorms, fog, hail and darkness always count. Below %@ water the light reminds you to take extra care.",
                                   Format.temperature(RowingLimits.coldWaterC))
                              : tr("Turn off to set your own. Below %@ water the app lowers its wind and gust limits by %@.",
                                   Format.temperature(RowingLimits.coldWaterC), Format.wind(RowingLimits.coldWindMarginMs)))
            }
            .surfaceRows()
            .confirmationDialog(tr("Use the app's limits again?"), isPresented: $confirmAppLimits, titleVisibility: .visible) {
                Button(tr("Use the app's limits"), role: .destructive) {
                    settings.boatLimits[boat.id] = nil
                    withAnimation { ownLimits = false }
                }
            } message: {
                Text(tr("The limits you set for this boat are dropped."))
            }

            if !boat.isGroup && !isNew {
                Section {
                    Button(tr("Remove this boat"), role: .destructive) {
                        dismiss()
                        settings.removeBoat(boat.id)
                    }
                }
                .surfaceRows()
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .tipVisibility(coldTip, $showColdTip)
        .navigationTitle(isNew ? tr("New boat") : boat.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The clubs where an own boat is kept: a menu to add one, swipe to remove one
/// (owner's choice A, 30.10.2026). The last club stays.
private struct KeptAtSection: View {
    let boat: Boat
    let locations: LocationStore

    var body: some View {
        let settings = AppSettings.shared
        let others = locations.saved.filter { !boat.clubs.contains($0.id) }
        Section {
            // Swipe to remove a club, as in My boats; a boat keeps at least one.
            ForEach(boat.clubs, id: \.self) { id in
                HStack {
                    Label(locations.name(of: id), systemImage: id == locations.homeID ? "house.fill" : "figure.rower")
                    Spacer(minLength: 8)
                    if id == locations.homeID {
                        Text(tr("Home base")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .deleteDisabled(boat.clubs.count < 2)
            }
            .onDelete { offsets in
                for id in offsets.map({ boat.clubs[$0] }) { settings.unkeep(boat.id, at: id) }
            }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { club in
                        Button(club.displayName) { settings.keep(boat.id, at: club.id) }
                    }
                } label: {
                    Label(tr("Add a club"), systemImage: "plus.circle")
                }
            }
        } header: {
            SectionTitle(tr("Kept at"), symbol: "mappin.and.ellipse")
        } footer: {
            SectionFooter(tr("The boat shows on these clubs' pages. Elsewhere it waits in the boat menu under “At other clubs”."))
        }
        .surfaceRows()
    }
}

/// One limit with buttons to raise or lower it; the app's value is shown beside a changed one.
private struct LimitRow: View {
    let limit: RowingLimit
    let boat: Boat
    /// Off while the app's limits are in use: the value shows greyed, without a stepper.
    var editable = true

    var body: some View {
        let limits = AppSettings.shared.limits(for: boat)
        let value = limits.value(limit)
        let usual = limit.standard(for: boat)
        let mine = limits.isMine(limit)
        if !editable {
            LabeledContent {
                Text(limit.format(usual)).monospacedDigit()
            } label: {
                Label(limit.title, systemImage: limit.symbol)
                    .symbolRenderingMode(.hierarchical)
            }
            .foregroundStyle(.secondary)
        } else {
        Stepper {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(limit.title, systemImage: limit.symbol)
                        .symbolRenderingMode(.hierarchical)
                    Text(mine ? tr("Your limit · the app's: %@", limit.format(usual)) : tr("The app's limit"))
                        .font(.caption)
                        .foregroundStyle(mine ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 4)
                Text(limit.format(value)).monospacedDigit().fontWeight(.semibold)
            }
        } onIncrement: {
            set(value + limit.step)
        } onDecrement: {
            set(value - limit.step)
        }
        }
    }

    private func set(_ new: Double) {
        let settings = AppSettings.shared
        let clamped = min(max((new / limit.step).rounded() * limit.step, limit.range.lowerBound), limit.range.upperBound)
        var custom = settings.boatLimits[boat.id] ?? [:]
        custom[limit] = abs(clamped - limit.standard(for: boat)) < limit.step / 2 ? nil : clamped
        settings.boatLimits[boat.id] = custom.isEmpty ? nil : custom
    }
}
