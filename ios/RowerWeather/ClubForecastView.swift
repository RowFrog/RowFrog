import SwiftUI

struct ClubForecastView: View {
    let api: APIClient
    let club: Club
    @State private var forecast: ClubForecast?
    @State private var error: String?

    var body: some View {
        List {
            if let now = forecast?.hours.first {
                Section {
                    HStack(spacing: 12) {
                        TrafficLightDot(light: now.light, size: 28)
                        VStack(alignment: .leading) {
                            Text(now.light.title).font(.title3.bold())
                            if !now.reasons.isEmpty {
                                Text(now.reasons.map(\.label).joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let water = forecast?.waterTemperature {
                        LabeledContent("Water temperature") {
                            Text("\(water.celsius, specifier: "%.1f") °C")
                        }
                    }
                }
            }
            if let forecast {
                Section("Next 48 hours") {
                    ForEach(forecast.hours) { hour in
                        HourRow(hour: hour)
                    }
                }
                Section {
                    ForEach(forecast.attribution, id: \.self) { Text($0) }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(club.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            forecast = try await api.forecast(clubID: club.id)
            error = nil
        } catch {
            self.error = "Could not load the forecast. Pull to retry."
        }
    }
}

private struct HourRow: View {
    let hour: ForecastHour

    var body: some View {
        HStack {
            TrafficLightDot(light: hour.light)
            Text(hour.time, format: .dateTime.weekday(.abbreviated).hour())
                .monospacedDigit()
                .frame(width: 80, alignment: .leading)
            if let wind = hour.windSpeedMs, let gust = hour.windGustMs {
                Text("\(wind, specifier: "%.0f")–\(gust, specifier: "%.0f") m/s")
            }
            Spacer()
            if let wave = hour.waveHeightM {
                Text("\(wave, specifier: "%.2f") m").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}
