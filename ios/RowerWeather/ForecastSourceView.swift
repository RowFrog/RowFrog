import SwiftUI

/// The small line at the bottom of a club page that names the weather model
/// the forecast comes from. Tapping it explains the model chain. With the
/// developer options on, the details also let the user pick another model.
struct ForecastSourceLine: View {
    let source: ForecastSource
    var choices: [ModelChoice] = []
    /// The model the user picked for this club; nil = automatic.
    var selected: String? = nil
    /// The picked model has no forecast yet, so the automatic one is shown.
    var pickedModelMissing = false
    /// Picks a model (nil = automatic) and reloads the forecast.
    var pick: @MainActor (String?) async -> Void = { _ in }
    @Environment(\.surface) private var surface
    /// Screenshot hook: `-RWOpenForecastSource YES` opens the details.
    @State private var showDetails = UserDefaults.standard.bool(forKey: "RWOpenForecastSource")

    var body: some View {
        if let first = source.parts.first {
            Button {
                showDetails = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: source.picked == nil ? "cloud.sun" : "slider.horizontal.3")
                    Text(tr("Forecast: %@", "\(first.providerShort) \(first.model), \(Self.grid(first.resolutionKm))"))
                    if source.picked != nil {
                        Text(tr("(your choice)"))
                    }
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
                ForecastSourceSheet(source: source, choices: choices, selected: selected, pickedModelMissing: pickedModelMissing, pick: pick)
                    // The model picker needs the whole height.
                    .presentationDetents(AppSettings.shared.developerOptions && !choices.isEmpty ? [.large] : [.medium, .large])
            }
        }
    }

    static func grid(_ km: Double) -> String {
        tr("%@ km grid", km.formatted(.number.precision(.fractionLength(0...1)).locale(AppSettings.shared.locale)))
    }
}

private struct ForecastSourceSheet: View {
    let source: ForecastSource
    let choices: [ModelChoice]
    let selected: String?
    let pickedModelMissing: Bool
    let pick: @MainActor (String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false

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
                if AppSettings.shared.developerOptions, !choices.isEmpty {
                    ModelPickerSection(
                        choices: choices,
                        picked: selected,
                        pickedModelMissing: pickedModelMissing,
                        loading: loading
                    ) { model in
                        loading = true
                        await pick(model)
                        loading = false
                    }
                }
                Section {
                    if source.picked == nil {
                        Label(tr("The app picks the weather model that does best for this region."), systemImage: "checkmark.seal")
                    }
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

/// Lets the user pick another weather model for this club, with advice for each.
private struct ModelPickerSection: View {
    let choices: [ModelChoice]
    let picked: String?
    let pickedModelMissing: Bool
    let loading: Bool
    let pick: @MainActor (String?) async -> Void

    var body: some View {
        Section {
            row(id: nil, title: tr("Automatic"), detail: tr("Recommended. The model that does best here, checked against measurements."), warning: false)
            ForEach(choices) { choice in
                row(
                    id: choice.id,
                    title: "\(choice.model) · \(choice.provider)",
                    detail: "\(ForecastSourceLine.grid(choice.resolutionKm)) · \(tr("%@ hours ahead", "\(choice.hours)"))\n\(tr(choice.note))",
                    warning: choice.notAdvised
                )
            }
        } header: {
            HStack {
                Text(tr("Weather model (test)"))
                if loading { ProgressView().controlSize(.small) }
            }
        } footer: {
            if pickedModelMissing {
                Text(tr("This model's forecast is not published yet, so the automatic one is shown."))
            } else {
                Text(tr("A test in the developer options. Other models can be better or worse here; the automatic one is checked against measurements."))
            }
        }
    }

    private func row(id: String?, title: String, detail: String, warning: Bool) -> some View {
        Button {
            Task { await pick(id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: picked == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked == id ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    if warning {
                        Label(tr("Not advised for rowing"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityAddTraits(picked == id ? .isSelected : [])
    }
}
