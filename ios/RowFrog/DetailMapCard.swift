import SwiftUI
import TipKit

/// The weather map of a detail view, as a card under the chart (beside it in
/// landscape). It shows the hour of the chart's blue line while linked; the
/// chain button gives it its own time, moved with its own slider and play
/// button. A tap opens the map full screen, with a slim copy of the chart as
/// its time bar. Lightning and fog are live pictures and keep their own time.
struct DetailMapCard: View {
    let layer: WeatherMapLayer
    let club: Club
    let data: ConditionData
    let time: DetailTime
    /// The chart, slim, for the full-screen map.
    let slimChart: AnyView
    var height: CGFloat = 220
    /// The value view's own symbol for the header: the cloud view shows the
    /// visibility map, but under a cloud, not binoculars (detail check 14 Nov 2026).
    var symbol: String? = nil

    @State private var full = Self.hookLayer != nil
    @State private var radar = false
    @State private var playing = false
    private let store = ModelMapStore.shared

    /// The hours the card's slider goes through.
    private var frames: [Date] { layer.links == .none ? [] : store.frames(for: layer) }

    /// The map's time as a date; hours count from the hour the sheet opened at.
    private var mapDate: Date { data.now.time.addingTimeInterval(time.shownMapHour * 3600) }

    private var frameIndex: Int? { layer.frame(in: frames, for: mapDate) }

    /// The hours of the chart that have maps: each model hour, or every hour of UV's days.
    private var mapHours: [Double]? {
        switch layer.links {
        case .none: return nil
        case .hour: return frames.isEmpty ? nil : frames.map { data.x($0) }
        case .day:
            guard let first = frames.first, let last = frames.last else { return nil }
            return Array(stride(from: data.x(first).rounded(.up), through: data.x(last) + 23, by: 1))
        }
    }

    /// The time the panel shows: for rain at the first hour, the latest radar picture.
    private var panelDate: Date {
        layer == .rain && data.isNow && time.shownMapHour == 0 ? .now : mapDate
    }

    /// Whether the rain map shows DWD's radar (an hour back to two ahead) instead of the forecast.
    private var showsRadar: Bool { layer == .rain && RadarWindow.covers(panelDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            WeatherMapPanel(point: club.launchPoint, clubID: club.id, layer: layer, time: panelDate)
                .allowsHitTesting(false)
                .saturation(time.mapOutOfRange ? 0.2 : 1)
                .opacity(time.mapOutOfRange ? 0.6 : 1)
                .overlay(alignment: .bottom) { note }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { open() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(tr("Opens the map full screen"))
            if frames.count > 1 {
                MapTimeControls(time: time, data: data, frames: frames, frameIndex: frameIndex, playing: $playing) {
                    WeatherMapTip().invalidate(reason: .actionPerformed)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: frames) { time.mapHours = mapHours }
        .fullScreenCover(isPresented: $full) {
            WeatherMapScreen(point: club.launchPoint, clubID: club.id, layer: Self.hookLayer ?? layer, start: mapDate,
                             time: layer.links == .none ? nil : Binding<Date?>(get: { mapDate }, set: { date in
                                 if let date { time.setMap(data.x(date).rounded()) }
                             }),
                             chart: layer.links == .none ? nil : slimChart)
                .environment(\.locale, AppSettings.shared.locale)
        }
        .fullScreenCover(isPresented: $radar) {
            RadarMapScreen(point: club.launchPoint, clubID: club.id, reference: nil, step: RadarWindow.step)
                .environment(\.locale, AppSettings.shared.locale)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol ?? layer.symbol).foregroundStyle(.secondary)
            Group {
                if layer.links == .none {
                    Text(tr("Live"))
                } else if showsRadar, let frame = RadarWindow.nearest(panelDate, in: RadarWindow.frames(step: RadarWindow.step)) {
                    Text(tr("Radar %@", Format.time(frame)))
                } else if let i = frameIndex {
                    // Past the radar's two hours the rain map is the forecast, and says so.
                    Text(layer == .rain ? tr("Forecast %@", Format.dayTime(frames[i]))
                         : layer.links == .day ? Format.day(frames[i]) : Format.dayTime(frames[i]))
                }
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if layer.links != .none {
                MapLinkButton(time: time) { playing = false }
            }
            Button {
                open()
                WeatherMapTip().invalidate(reason: .actionPerformed)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel(tr("Opens the map full screen"))
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// Full screen: the radar map while the card shows the radar, else the weather map.
    private func open() {
        if showsRadar {
            radar = true
            RainRadarTip().invalidate(reason: .actionPerformed)
        } else {
            full = true
        }
    }

    /// Past the maps' end or before their start: the map keeps its nearest picture, dimmed.
    @ViewBuilder
    private var note: some View {
        if time.mapOutOfRange, let first = frames.first, let last = frames.last {
            Text(mapDate > last ? tr("The maps end %@; the chart goes on.", Format.dayTime(last))
                                : tr("The maps start %@.", Format.dayTime(first)))
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
                .padding(8)
        }
    }

    /// Screenshot hook: `-RWOpenWeatherMap <layer>` opens the map with that layer.
    private static var hookLayer: WeatherMapLayer? {
        UserDefaults.standard.string(forKey: DefaultsKey.openWeatherMap).flatMap(WeatherMapLayer.init(rawValue:))
    }
}
