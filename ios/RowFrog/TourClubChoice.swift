import SwiftUI

// Split off Tutorial.swift (17 Nov 2026, with the tour's new layout, TourLayout.swift).

/// Picking the home base, or adding more clubs: suggestions first, then any
/// club in the catalog by search.
struct ClubChoicePage: View {
    let page: TourPage
    let locations: LocationStore
    let near: Coordinate?
    let reload: () async -> Void
    @State private var search = ""
    @Environment(\.tourColumns) private var columns
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // The same two parts in both arrangements, so the list keeps its place when the device turns.
        let layout = columns.map { AnyLayout(HStackLayout(alignment: .top, spacing: $0.gap)) } ?? AnyLayout(VStackLayout(spacing: 12))
        layout {
            if let columns {
                TourSideColumn(columns: columns, alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        head(compact: false, short: columns.short)
                        searchField
                    }
                    .padding(.top, 8)
                }
            } else {
                // Searching on an iPhone: the icon and the intro step aside while the search has text, so
                // the list keeps room above the keyboard. Text, not focus, as on the website.
                VStack(spacing: 12) {
                    head(compact: sizeClass == .compact && !search.isEmpty, short: false)
                    searchField
                }
                .padding(.horizontal)
            }
            list
                .frame(width: columns?.right)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        // Again once the location is in, so the pick is one of the clubs shown.
        .task(id: near == nil) { await autoPickHome() }
    }

    private func head(compact: Bool, short: Bool) -> some View {
        VStack(alignment: columns == nil ? .center : .leading, spacing: 6) {
            if !compact {
                Image(systemName: page.symbol)
                    .font(.system(size: short ? 28 : 36))
                    .foregroundStyle(page.tint)
                    .accessibilityHidden(true)
            }
            Text(page.title).font(short ? .title3.bold() : .title2.bold())
            if !compact {
                Text(page.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(columns == nil ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: columns == nil ? .center : .leading)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(tr("Club, lake or town"), text: $search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("tour-search-\(page.rawValue)")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel(tr("Cancel"))
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Only this part scrolls; the head and the search above it stay.
    private var list: some View {
        List {
            if locations.catalog.isEmpty {
                if locations.catalogFailed {
                    ContentUnavailableView {
                        Label(tr("No connection"), systemImage: "wifi.slash")
                    } description: {
                        Text(tr("Could not load the rowing locations."))
                    } actions: {
                        Button(tr("Try again")) { Task { await reload() } }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else if search.isEmpty {
                if page == .moreClubs, !locations.saved.isEmpty {
                    Section(tr("In your list")) {
                        ForEach(locations.saved) { row($0) }
                    }
                }
                let suggestions = locations.suggestions(near: near).filter { page == .homeBase || !locations.isSaved($0) }
                Section {
                    ForEach(suggestions) { row($0) }
                } header: {
                    if !suggestions.isEmpty { Text(near == nil ? tr("Suggestions") : tr("Near you")) }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Search by club, lake or town to find any club in Germany, Austria or Switzerland."))
                        Text(tr("Clubs nobody has opened for a while update less often at first. After you add one, it is up to date within about 30 minutes."))
                    }
                }
            } else {
                let results = locations.search(search)
                if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(results.prefix(50)) { row($0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // Room for the page dots.
    }

    /// Screenshot hook: `-RWTourAutoHome YES` picks the first suggestion as home
    /// base once the clubs are in, as a tap on it would.
    private func autoPickHome() async {
        guard page == .homeBase, UserDefaults.standard.bool(forKey: DefaultsKey.tourAutoHome) else { return }
        for _ in 0..<60 {
            if let first = locations.suggestions(near: near).first {
                try? await Task.sleep(for: .seconds(2))
                locations.replaceHome(with: first)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func row(_ club: Club) -> some View {
        let isHome = club.id == locations.homeID
        let saved = locations.isSaved(club)
        return Button {
            if page == .homeBase {
                locations.replaceHome(with: club)
            } else if !saved {
                locations.add(club)
            } else if !isHome {
                locations.remove(club)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name).foregroundStyle(Color.primary)
                    Text([locations.lake(of: club)?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Group {
                    if isHome {
                        Image(systemName: "house.fill").foregroundStyle(.blue)
                            .accessibilityLabel(tr("Home base"))
                    } else if page == .homeBase {
                        Image(systemName: "circle").foregroundStyle(.secondary)
                    } else if saved {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .accessibilityLabel(tr("In your list"))
                    } else {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                            .accessibilityLabel(tr("Add %@", club.displayName))
                    }
                }
                .font(.title3)
            }
        }
        .accessibilityIdentifier("tour-club-\(club.id)")
    }
}

