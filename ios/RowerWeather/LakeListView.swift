import SwiftUI

struct LakeListView: View {
    let api: APIClient
    @State private var lakes: [Lake] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
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
        } catch {
            self.error = "Could not load lakes. Pull to retry."
        }
    }
}
