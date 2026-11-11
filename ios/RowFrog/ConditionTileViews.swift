import SwiftUI

/// The small tiles of Current conditions and their graphics, split off ConditionsCard.swift
/// (owner's large-file rule): the tile, its graphic, the storm level and the sun path.

struct ConditionTile: View {
    let condition: Condition
    let data: ConditionData
    @Environment(\.surface) private var surface

    private var hour: ForecastHour { data.now }
    /// The ice tile outside November to April: greyed out, still opens its detail.
    private var offSeason: Bool { condition == .ice && IceSeason.isOff(data.forecast.ice) }

    var body: some View {
        Group {
            if condition == .daylight {
                sunTile
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    header(condition.title)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(cause ?? .primary)
                                .accessibilityLabel(light == nil ? value : value + ", " + tr("Sets the light: %@", light?.title ?? ""))
                            detailLine.font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                        // Every graphic gets the same height, so all tiles are as tall.
                        ConditionGraphic(condition: condition, data: data).frame(height: Self.graphicHeight)
                    }
                }
                .opacity(offSeason ? 0.45 : 1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .topLeading)
        // Before the tile's own background, so the wash sits on top of it.
        .causeHighlight(cause)
        .background(surface.tile.opacity(offSeason ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    static let graphicHeight: CGFloat = 44

    private var light: Light? { condition.cause(in: hour) }
    /// Amber or red while this value sets the light; its value then takes that colour.
    private var cause: Color? {
        light?.causeTint ?? (condition == .waterTemperature
            ? ColdWaterKit.valueTint(waterC: data.water?.celsius ?? data.estimatedWater, limits: data.limits) : nil)
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: 4) {
            ConditionIcon(condition: condition).frame(width: 16)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if condition == .precipitation {
                // Whether the bars below come from the radar. Only for now: a picked
                // later hour is past the radar's two hours anyway.
                if data.radarAhead != nil {
                    RadarMark()
                } else if let status = data.radarStatus, data.isNow {
                    RadarMark(status: status)
                }
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    var value: String {
        switch condition {
        case .temperature: Format.degrees(hour.temperatureC)
        case .feelsLike: Format.degrees(hour.apparentTemperatureC)
        case .humidity: hour.humidityPct.map { "\(Format.number($0)) %" } ?? "–"
        case .wind: Format.wind(hour.windSpeedMs)
        case .waves: Format.waves(hour.waveHeightM)
        case .waterTemperature:
            if data.water == nil, let estimate = data.estimatedWater { "≈ " + Format.degrees(estimate, digits: 0) } else { Format.degrees(data.water?.celsius, digits: 1) }
        case .precipitation:
            data.rainLines.value
        case .visibility: Format.distance(hour.visibilityM)
        case .cloudCover: "\(Format.number(hour.cloudCoverPct)) %"
        case .pressure: Format.pressureNumber(hour.pressureHpa)
        case .thunderstorm: stormLevel(hour.light(for: condition.reasonNames))
        case .uvIndex: Format.number(hour.uvIndex)
        case .ice: iceGuess.value
        case .daylight: ""
        }
    }

    /// The short line under the value; rain read from the radar starts with the radar's symbol.
    var detailLine: Text {
        guard condition == .precipitation, data.rainLines.fromRadar else { return Text(detail) }
        return Text("\(Image(systemName: "dot.radiowaves.left.and.right")) \(detail)")
    }

    var detail: String {
        switch condition {
        case .temperature:
            let temps = data.next24.compactMap(\.temperatureC)
            guard let hi = temps.max(), let lo = temps.min() else { return "" }
            return tr("High %@ · low %@", Format.degrees(hi), Format.degrees(lo))
        case .feelsLike:
            return feelsLikeNote(hour) ?? ""
        case .humidity:
            return hour.dewPointC.map { tr("Dew point %@", Format.degrees($0)) } ?? ""
        case .wind:
            let gust = tr("Gusts %@", Format.windNumber(hour.windGustMs))
            return hour.windFromDeg.map { gust + " · " + tr("from %@", Format.compass($0)) } ?? gust
        case .waves:
            return data.wavesDetail
        case .waterTemperature:
            if data.water == nil, data.estimatedWater != nil {
                return data.satelliteWater != nil ? tr("Satellite estimate") : tr("Estimated, not measured")
            }
            return data.water.map { tr("Measured %@", Format.time($0.measuredAt)) } ?? tr("No lake station")
        case .precipitation:
            return data.rainLines.detail
        case .visibility:
            return data.visibilityDetail
        case .cloudCover:
            return hour.cloudCoverLowPct.map { tr("Low cloud %@ %%", Format.number($0)) } ?? ""
        case .pressure:
            let unit = AppSettings.shared.pressureUnit.symbol
            guard let change = data.forecast.pressureChange(after: hour) else { return unit }
            return unit + " · " + PressureTrend(change: change).title.lowercased()
        case .thunderstorm:
            guard data.warningsChecked else { return tr("Warnings not checked") }
            return data.warnings(["GEWITTER"]).isEmpty ? tr("No warning") : tr("Official warning")
        case .uvIndex:
            guard let top = data.next24.filter({ $0.uvIndex != nil }).max(by: { $0.uvIndex! < $1.uvIndex! }) else { return "" }
            return tr("Max %@ · %@", Format.number(top.uvIndex), Format.day(top.time))
        case .ice:
            return iceGuess.detail
        case .daylight:
            return ""
        }
    }

    /// Until the ice estimate is in the app: warm water cannot freeze over.
    private var iceGuess: (value: String, detail: String) {
        if offSeason { return (tr("Off season"), tr("Nov–Apr")) }
        if let ice = data.forecast.ice, ice.status != "unavailable" {
            return (ice.title, ice.detail)
        }
        if let c = data.water?.celsius, c >= 8 {
            return (tr("No ice"), tr("Water too warm"))
        }
        return (tr("No data yet"), tr("Check the lake yourself"))
    }

    private var sunTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch data.forecast.sunState(at: data.moment) {
            case let .up(sunrise, sunset)?:
                header(tr("Sunset"))
                sunLine(Format.time(sunset), tr("Sunrise %@", Format.time(sunrise)), sunrise: sunrise, sunset: sunset, at: data.moment)
            case let .down(sunrise, sunset)?:
                header(tr("Sunrise"))
                sunLine(Format.time(sunrise), tr("Sunset %@", Format.time(sunset)), sunrise: sunrise, sunset: sunset, at: data.moment)
            case nil:
                header(condition.title)
                Text("–").font(.title3.weight(.semibold))
            }
        }
    }

    /// Laid out like the other tiles: value and detail on the left, the sun path on the right.
    private func sunLine(_ value: String, _ detail: String, sunrise: Date, sunset: Date, at: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            SunPath(sunrise: sunrise, sunset: sunset, at: at, lineWidth: 2).frame(width: 64, height: Self.graphicHeight)
        }
    }
}

/// A value's small graphic: on its tile, and larger at the top of its detail view.
struct ConditionGraphic: View {
    let condition: Condition
    let data: ConditionData

    private var hour: ForecastHour { data.now }

    var body: some View {
        switch condition {
        case .temperature:
            ScaleBar(fraction: ((hour.temperatureC ?? 0) + 10) / 45, colors: [.blue, .teal, .green, .orange, .red])
        case .feelsLike:
            ScaleBar(fraction: ((hour.apparentTemperatureC ?? 0) + 10) / 45, colors: [.blue, .teal, .green, .orange, .red])
        case .humidity:
            HStack(spacing: 0) {
                SymbolFill(outline: "drop", filled: "drop.fill", fraction: (hour.humidityPct ?? 0) / 100, color: .teal, size: 18)
                if let air = hour.temperatureC, let dew = hour.dewPointC {
                    DewGap(air: air, dewPoint: dew)
                }
            }
        case .wind:
            if let from = hour.windFromDeg {
                WindDial(speed: Format.windNumber(hour.windSpeedMs), fromDeg: from, unit: AppSettings.shared.windUnit.symbol)
                    .frame(width: 44, height: 44)
            }
        case .waves:
            let userLimits = data.limits
            let top = userLimits.value(.waveRed) * 4 / 3
            ScaleBar(fraction: (hour.waveHeightM ?? 0) / top,
                     zones: [(0, .green), (userLimits.value(.waveAmber) / top, .orange), (userLimits.value(.waveRed) / top, .red)])
        case .waterTemperature:
            if let c = data.water?.celsius {
                // Blues for cold water: it calls for a life jacket, not a warning colour.
                ScaleBar(fraction: c / 25, zones: [(0, ColdWaterKit.deep), (0.16, ColdWaterKit.color),
                                                   (0.4, ColdWaterKit.color.opacity(0.45)), (0.6, .green)])
            }
        case .precipitation:
            if let radar = data.radarAhead {
                RadarSparkBars(radar: radar.steps.map(\.mmPerHour),
                               forecast: data.future.filter { $0.time >= radar.end }.prefix(4).map { $0.precipitationMm ?? 0 })
            } else {
                SparkBars(values: data.future.prefix(8).map { $0.precipitationMm ?? 0 })
            }
        case .visibility:
            // 100 m at the left to 40 km at the right, stretched at the bottom.
            ScaleBar(fraction: log10(max(hour.visibilityM ?? 40_000, 100) / 100) / log10(400),
                     zones: [(0, .red), (0.27, .orange), (0.384, .green)])
        case .cloudCover:
            HStack(spacing: 0) {
                SymbolFill(outline: "cloud", filled: "cloud.fill", fraction: (hour.cloudCoverPct ?? 0) / 100, color: .gray, size: 18)
                if let high = hour.cloudCoverHighPct, let mid = hour.cloudCoverMidPct, let low = hour.cloudCoverLowPct {
                    CloudLayers(layers: [(tr("H"), high / 100), (tr("M"), mid / 100), (tr("L"), low / 100)])
                }
            }
        case .pressure:
            PressureGauge(hpa: hour.pressureHpa, trend: data.forecast.pressureChange(after: hour).map(PressureTrend.init(change:)))
                .frame(width: 44, height: 44)
        case .thunderstorm:
            LevelSegments(level: stormRank(hour.light(for: condition.reasonNames)), colors: [.green, .orange, .red])
        case .uvIndex:
            ScaleBar(fraction: (hour.uvIndex ?? 0) / 11, colors: uvColors)
        case .ice, .daylight:
            EmptyView()
        }
    }
}

private let uvColors: [Color] = [.green, .yellow, .orange, .red, .purple]

private func stormRank(_ light: Light?) -> Int {
    switch light {
    case .red: 3
    case .amber: 2
    default: 1
    }
}

func stormLevel(_ light: Light?) -> String {
    switch light {
    case .red: tr("High")
    case .amber: tr("Possible")
    default: tr("Low")
    }
}

/// The sun path for one day from its sunrise and sunset, with the sun at
/// the shown time: now, or the hour picked in the 48 hours.
struct SunPath: View {
    let sunrise: Date, sunset: Date
    var at: Date = .now
    var lineWidth: CGFloat = 3

    var body: some View {
        let rise = clock(sunrise), down = clock(sunset)
        SunPathGraph(firstLight: rise, sunrise: rise, noon: (rise + down) / 2, sunset: down, lastLight: down,
                     now: clock(at), lineWidth: lineWidth)
    }

    private func clock(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
}
