import SwiftUI

struct LakeListView: View {
    let api: APIClient
    @State private var lakes: [Lake] = []
    @State private var error: String?
    @State private var path: [Club] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(lakes) { lake in
                    Section(lake.name) {
                        ForEach(lake.clubs) { club in
                            NavigationLink(value: club) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(club.name)
                                    Text(club.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("RowerWeather")
            .navigationDestination(for: Club.self) { club in
                ClubForecastView(api: api, club: club)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            lakes = try await api.lakes()
            error = nil
            openClubFromLaunchArgument()
        } catch {
            self.error = "Could not load lakes. Pull to retry."
        }
    }

    /// Launching with `-RWOpenClub <club id>` opens that club's forecast straight away (used for screenshots).
    private func openClubFromLaunchArgument() {
        guard path.isEmpty, let id = UserDefaults.standard.string(forKey: "RWOpenClub"),
              let club = lakes.flatMap(\.clubs).first(where: { $0.id == id }) else { return }
        path = [club]
    }
}
