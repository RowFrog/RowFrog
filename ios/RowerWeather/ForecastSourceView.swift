import SwiftUI

/// The small line at the bottom of a club page that names the weather model
/// the forecast comes from. Tapping it explains the model chain.
struct ForecastSourceLine: View {
    let source: ForecastSource
    @Environment(\.surface) private var surface
    /// Screenshot hook: `-RWOpenForecastSource YES` opens the details.
    @State private var showDetails = UserDefaults.standard.bool(forKey: "RWOpenForecastSource")

    var body: some View {
        if let first = source.parts.first {
            Button {
                showDetails = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.sun")
                    Text(tr("Forecast: %@", "\(first.providerShort) \(first.model), \(Self.grid(first.resolutionKm))"))
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(surface.hasPicture ? 12 : 0)
                .background(surface.label, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Shows which weather models the forecast comes from."))
            .sheet(isPresented: $showDetails) {
                ForecastSourceSheet(source: source)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    static func grid(_ km: Double) -> String {
        tr("%@ km grid", km.formatted(.number.precision(.fractionLength(0...1)).locale(AppSettings.shared.locale)))
    }
}

private struct ForecastSourceSheet: View {
    let source: ForecastSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(source.parts, id: \.self) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(part.model).font(.headline)
                            Text(part.provider).font(.subheadline)
                            Text(tr("Hours %@ to %@ · %@", "\(part.fromHour)", "\(part.toHour)", ForecastSourceLine.grid(part.resolutionKm)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(tr("Weather models are computer forecasts from national weather services. A finer grid shows more of the lake and the hills around it."))
                }
                Section {
                    Label(tr("The app picks the weather model that does best for this region."), systemImage: "checkmark.seal")
                    Label(tr("The choice is checked regularly against measured wind and temperature."), systemImage: "chart.line.uptrend.xyaxis")
                    Label(tr("Data via Open-Meteo."), systemImage: "server.rack")
                }
                .font(.subheadline)
            }
            .navigationTitle(tr("Where the forecast comes from"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}
