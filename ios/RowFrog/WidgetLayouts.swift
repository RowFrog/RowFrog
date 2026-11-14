import SwiftUI
import WidgetKit

// The widget redesign (owner's picks, 6 and 11 Nov 2026, mock-ups
// https://claude.ai/artifact/KEYD6DbB4vvcJfxbHDfn8q): one layout across the sizes,
// the top line with the club and the forecast's time, the light with its reason,
// values as symbol and value with the one that sets the light coloured, hours with
// marked dots and the good rowing times as day bars. Each widget can show fewer
// values or all six of the top tile ("Layout"), with or without marks ("Marks").

/// How much a home-screen widget shows beside the rowing light.
enum WidgetLayout: String, CaseIterable, Codable {
    /// Small: the ring only. Medium and large: temperature, wind, waves and visibility on the right.
    case fewer
    /// All six values of the top tile in two columns on the right; the light then uses its short words.
    case beside
    /// Large: the six values in a row under the light. Small and medium show `beside` instead.
    case below
}

/// One value as the widget shows it: symbol, words, and the light it sets, if any.
struct WidgetValue: Equatable {
    let condition: Condition
    let symbol: String
    let text: String
    /// Amber or red while this value sets the light (see `Condition.cause(in:)`).
    var light: Light? = nil
    /// The grey line under it in the extra large widget.
    var note: String = ""
}

/// One day of the good rowing times: its daylight hours as lights, and the first good stretch.
struct WidgetDay: Equatable {
    let label: String
    let lights: [Light]
    /// Hours already gone, drawn faint.
    let past: [Bool]
    /// "Now–15:00" or "11:00–15:00", nil when the day has no good hour left.
    let good: String?
    /// Daylight hours past the forecast's end: the last day often has only its
    /// first hour or two. They keep their place in the bar, empty, and the day
    /// without a good stretch reads "Not known yet" instead of "Not good".
    var missing = 0
}

/// The words of the new layouts, worked out here so the tests can read them.
extension RowingSnapshot {
    /// The light in one or two words, for the small widget, the "all values" layouts and the lock screen.
    var shortTitle: String {
        guard let light = current?.light else { return "–" }
        if isStale && light == .green { return tr("Out of date") }
        switch light {
        case .green: return tr("Good")
        case .amber: return tr("Caution")
        case .red: return tr("Stay ashore", key: "Stay ashore (short)")
        }
    }

    /// While green: the start of the first hour that is no longer green.
    var goodUntil: Date? {
        guard let hour = current, hour.light == .green, !isStale else { return nil }
        return hours.first { $0.time > date && ($0.light != .green || $0.sunUp == false) }?.time
    }

    /// While amber or red: the start of the first hour with a better light.
    var betterFrom: Date? {
        guard let hour = current, hour.light != .green else { return nil }
        return hours.first { $0.time > date && $0.light < hour.light }?.time
    }

    /// The short line under the light: "Until 16:00", "Better from 14:00", or the reason.
    var shortWhy: String {
        guard let hour = current else { return "" }
        if isStale, let forecast { return tr("As of %@", Format.dayTime(forecast.generatedAt)) }
        if let until = goodUntil { return tr("Until %@", Format.time(until)) }
        if let better = betterFrom { return tr("Better from %@", Format.time(better)) }
        return detailLine(hour)
    }

    /// When the forecast was made, after the club in the top line: "10:50", or "Tue 10:50" on another day.
    var forecastTime: String? {
        guard let made = forecast?.generatedAt else { return nil }
        return Calendar.current.isDate(made, inSameDayAs: date) ? Format.time(made) : Format.dayTime(made)
    }

    /// "Good until 16:00" on the lock screen, else the short words.
    var lockTitle: String {
        if let until = goodUntil { return tr("Good until %@", Format.time(until)) }
        return shortTitle
    }

    /// The lock screen's second line: a storm or rain coming while green, else why and until when.
    var lockDetail: String {
        guard let hour = current else { return tr("Open Row Frog to load the forecast.") }
        if hour.light == .green, !isStale {
            if let storm = stormAhead {
                return storm.time <= date ? tr("Thunderstorm") : tr("%@ from %@", tr("Thunderstorm"), Format.time(storm.time))
            }
            if let radar = rainAhead { return radarLine(radar) }
            return feelsLine(hour)
        }
        return shortWhy
    }

    /// "3° · Feels like 0°".
    func feelsLine(_ hour: ForecastHour) -> String {
        let air = Format.degrees(hour.temperatureC)
        guard let feels = hour.apparentTemperatureC else { return air }
        return "\(air) · \(tr("Feels like %@", Format.degrees(feels)))"
    }

    /// The radar in a short, concrete sentence: "Light rain from 14:30", "Dry from 15:10".
    func radarLine(_ radar: RainRadar) -> String {
        if radar.rainingNow {
            if let dry = radar.dryAgain { return tr("Dry from %@", Format.time(dry.time)) }
            return tr("%@ for the next 2 hours", RainRadar.intensity(radar.peak))
        }
        guard let first = radar.firstRain else { return tr("Dry") }
        return tr("%@ from %@", RainRadar.intensity(radar.peak), Format.time(first.time))
    }

    // MARK: Values

    func value(_ condition: Condition) -> WidgetValue {
        let hour = current
        let cause = hour.flatMap { condition.cause(in: $0) }
        let nearby = hour?.nearbyCondition == condition ? tr("Nearby") : nil
        switch condition {
        case .temperature:
            let sky = hour.map { Sky(hour: $0).symbol(night: $0.sunUp == false) } ?? Condition.temperature.symbol
            return WidgetValue(condition: condition, symbol: sky, text: Format.degrees(hour?.temperatureC),
                               note: hour?.apparentTemperatureC.map { tr("Feels like %@", Format.degrees($0)) } ?? "")
        case .feelsLike:
            return WidgetValue(condition: condition, symbol: Condition.feelsLike.symbol, text: Format.degrees(hour?.apparentTemperatureC))
        case .waterTemperature:
            if let measured = forecast?.waterTemperature {
                return WidgetValue(condition: condition, symbol: condition.symbol, text: Format.degrees(measured.celsius, digits: 1),
                                   note: tr("Measured %@", Format.time(measured.measuredAt)))
            }
            if let estimate = forecast?.estimatedWaterC {
                return WidgetValue(condition: condition, symbol: condition.symbol, text: "≈ " + Format.degrees(estimate), note: tr("Estimated"))
            }
            return WidgetValue(condition: condition, symbol: condition.symbol, text: "–")
        case .wind:
            let wind = hour?.shownWind
            return WidgetValue(condition: condition, symbol: condition.symbol, text: Format.windRange(wind?.speed, wind?.gust),
                               light: cause, note: nearby ?? hour?.windFromDeg.map { tr("from %@", Format.compass($0)) } ?? "")
        case .waves:
            return WidgetValue(condition: condition, symbol: condition.symbol, text: Format.waves(hour?.shownWaveHeightM),
                               light: cause, note: nearby ?? "")
        case .visibility:
            return WidgetValue(condition: condition, symbol: condition.symbol, text: Format.distance(hour?.shownVisibilityM),
                               light: cause, note: nearby ?? "")
        default:
            return rainValue
        }
    }

    /// The first of the next six hours in which a thunderstorm sets the light.
    var stormAhead: ForecastHour? {
        hours.prefix(6).first { Condition.thunderstorm.cause(in: $0) != nil }
    }

    /// The rain value, as the app's rain tile: from the radar while it sees rain within its two
    /// hours ("From 11:20", "Until 11:40"), else the forecast's amount, or "Dry". A thunderstorm
    /// that sets the light within the next six hours takes its place, as on the lake map.
    var rainValue: WidgetValue {
        if let storm = stormAhead {
            let text = storm.time <= date ? tr("Now") : tr("From %@", Format.time(storm.time))
            return WidgetValue(condition: .thunderstorm, symbol: "cloud.bolt.fill", text: text,
                               light: Condition.thunderstorm.cause(in: storm), note: tr("Thunderstorm"))
        }
        let cause = current.flatMap { Condition.precipitation.cause(in: $0) }
        if let radar = rainAhead {
            let text: String
            if radar.rainingNow {
                text = radar.dryAgain.map { tr("Until %@", Format.time($0.time)) } ?? tr("Now")
            } else {
                text = radar.firstRain.map { tr("From %@", Format.time($0.time)) } ?? tr("Dry")
            }
            return WidgetValue(condition: .precipitation, symbol: "cloud.rain", text: text, light: cause, note: tr("Radar"))
        }
        guard let hour = current else { return WidgetValue(condition: .precipitation, symbol: "cloud.rain", text: "–") }
        let mm = hour.precipitationMm ?? 0
        let kind = Sky(hour: hour).precipitationKind
        if mm >= 0.1 {
            return WidgetValue(condition: .precipitation, symbol: "cloud.rain", text: Format.rain(mm), light: cause, note: kind ?? "")
        }
        if let kind { return WidgetValue(condition: .precipitation, symbol: "cloud.drizzle", text: kind, light: cause) }
        return WidgetValue(condition: .precipitation, symbol: "cloud", text: tr("Dry"))
    }

    // MARK: Good rowing times

    /// Today (while it has daylight left) and the next days, each with its daylight hours.
    func days(_ count: Int, calendar: Calendar = .current) -> [WidgetDay] {
        guard let forecast else { return [] }
        let daylight = forecast.hours.filter { $0.sunUp != false }
        var result: [WidgetDay] = []
        var day = calendar.startOfDay(for: date)
        for _ in 0..<(count + 1) where result.count < count {
            let hours = daylight.filter { calendar.isDate($0.time, inSameDayAs: day) }
            let past = hours.map { $0.time.addingTimeInterval(3600) <= date }
            if !hours.isEmpty, past.contains(false) {
                let label = calendar.isDateInToday(day) || calendar.isDateInTomorrow(day)
                    ? Format.day(day, calendar: calendar)
                    : day.formatted(.dateTime.weekday(.abbreviated).day().locale(Format.locale))
                result.append(WidgetDay(label: label, lights: hours.map(\.light), past: past,
                                        good: isStale ? nil : goodStretch(hours),
                                        missing: missingHours(after: forecast.hours.last?.time, on: day, calendar: calendar)))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// The daylight hours of `day` after the forecast's last hour (`end`), from the day's sunrise and sunset.
    private func missingHours(after end: Date?, on day: Date, calendar: Calendar) -> Int {
        guard let end, let sun = forecast?.daylight?.first(where: { calendar.isDate($0.sunrise, inSameDayAs: day) }) else { return 0 }
        let from = max(end.addingTimeInterval(3600), sun.sunrise)
        guard sun.sunset > from else { return 0 }
        return Int((sun.sunset.timeIntervalSince(from) / 3600).rounded(.up))
    }

    /// The first stretch of at least an hour of green from now on, "Now–15:00" or "11:00–15:00".
    private func goodStretch(_ hours: [ForecastHour]) -> String? {
        var start: Date?
        var end: Date?
        for hour in hours where hour.time.addingTimeInterval(3600) > date {
            if hour.light == .green {
                if start == nil { start = max(hour.time, date) }
                end = hour.time.addingTimeInterval(3600)
            } else if let s = start, let e = end {
                if e.timeIntervalSince(s) >= 3600 { break }
                start = nil
                end = nil
            }
        }
        guard let s = start, let e = end, e.timeIntervalSince(s) >= 3600 else { return nil }
        // Already good: "Now–16:00", not the minute the widget last drew (owner, 11 Nov 2026).
        return "\(s <= date ? tr("Now") : Format.time(s))–\(Format.time(e))"
    }

    // MARK: Lock screen ring

    /// The daylight ring: today's daylight hours, or tomorrow's once the sun is down.
    var ringDay: WidgetDay? { days(1).first }

    /// Where now is on the ring, 0 at sunrise to 1 at sunset; nil while the sun is down.
    var ringNow: Double? {
        guard case let .up(sunrise, sunset)? = forecast?.sunState(at: date), sunset > sunrise else { return nil }
        return min(max(date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise), 0), 1)
    }
}

extension Light {
    /// The mark inside the small widget's ring and the lock screen: a check, "!" or "×".
    func plainMark(stale: Bool) -> String {
        if stale && self == .green { return "clock" }
        switch self {
        case .green: return "checkmark"
        case .amber: return "exclamationmark"
        case .red: return "xmark"
        }
    }
}

// MARK: Parts and layouts

extension RowingWidgetView {
    /// The marks show when the widget's own option says so, and always with
    /// iOS's Differentiate Without Colour on.
    var showMarks: Bool { marks || withoutColor }

    /// The colour a value takes while it sets the light: lighter shades on the
    /// pictures and skies, so they stay readable on dark and mid tones.
    func tint(_ light: Light?) -> Color? {
        guard let light, light != .green else { return nil }
        if plain || family.isAccessory { return light.color }
        return light == .amber ? Color(red: 1, green: 0.7, blue: 0.25) : Color(red: 1, green: 0.45, blue: 0.4)
    }

    var rule: some View { Divider().overlay(plain ? Color.secondary.opacity(0.4) : .white.opacity(0.35)) }

    /// The club, the home symbol and the forecast's time.
    var topLine: some View {
        HStack(spacing: 4) {
            Text(snapshot.clubName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if snapshot.isHome {
                Image(systemName: "location.fill").font(.caption2)
            }
            if let time = snapshot.forecastTime {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                    Text(time)
                }
                .font(.caption2.weight(.medium))
                .opacity(0.8)
                .padding(.leading, 4)
                .layoutPriority(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("As of %@", time))
            }
            Spacer(minLength: 0)
        }
    }

    /// The light as a dot; with marks, the dot carries a check, "!" or "×".
    /// `hour`: a dot in the hours row. With an out-of-date forecast every hour's dot is plain
    /// grey, amber and red too, so none looks like fresh data (owner's pick, 11 Nov 2026).
    func lightDot(_ light: Light, size: CGFloat, hour: Bool = false) -> some View {
        let stale = snapshot.isStale
        let grey = hour && stale
        let color = grey ? Color.gray : light.color(stale: stale)
        return Group {
            if showMarks && !grey {
                ZStack {
                    Circle().fill(color)
                    Image(systemName: light.plainMark(stale: stale))
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundStyle(.white)
                }
            } else {
                Circle().fill(color)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(grey ? tr("Forecast out of date") : light.title(stale: stale))
    }

    /// The big ring of the small widget, always with its mark.
    func ring(_ light: Light, size: CGFloat) -> some View {
        let stale = snapshot.isStale
        return ZStack {
            Circle().stroke(light.color(stale: stale), lineWidth: max(4, size * 0.1))
            Image(systemName: light.plainMark(stale: stale))
                .font(.system(size: size * 0.42, weight: .bold))
        }
        .padding(max(2, size * 0.05))
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(light.title(stale: stale))
    }

    var coldWaterKit: ColdWaterKit? {
        ColdWaterKit(waterC: snapshot.forecast?.waterTemperature?.celsius ?? snapshot.forecast?.estimatedWaterC,
                     limits: AppSettings.shared.limits(at: snapshot.forecast?.clubId))
    }

    func coldWaterSymbol(_ kit: ColdWaterKit) -> some View {
        Image(systemName: ColdWaterKit.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(plain ? AnyShapeStyle(ColdWaterKit.color) : AnyShapeStyle(Color.white))
            .padding(4)
            .background(plain ? ColdWaterKit.color.opacity(0.15) : ColdWaterKit.color.opacity(0.75), in: Circle())
            .accessibilityLabel(kit.title)
    }

    /// The light with its words and the reason under it: the full sentence, or the short words.
    func verdict(_ hour: ForecastHour, full: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                lightDot(hour.light, size: 17)
                Text(full ? hour.light.title(stale: snapshot.isStale) : snapshot.shortTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let kit = coldWaterKit { coldWaterSymbol(kit) }
            }
            Text(full ? snapshot.detailLine(hour) : snapshot.shortWhy)
                .font(.caption.weight(.medium))
                .opacity(0.9)
                .lineLimit(full ? 1 : 2)
                .minimumScaleFactor(0.85)
        }
    }

    /// Symbol and value, coloured while it sets the light.
    func valueLine(_ value: WidgetValue, font: Font = .caption) -> some View {
        HStack(spacing: 3) {
            Image(systemName: value.symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(minWidth: 14)
            Text(value.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(font.weight(.semibold))
        .modifier(TintedIf(color: tint(value.light)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.condition.title) \(value.text)")
    }

    /// Air with the sky's symbol, and feels like smaller beside it.
    func airLine(font: Font = .caption) -> some View {
        let air = snapshot.value(.temperature)
        let feels = snapshot.value(.feelsLike)
        return HStack(spacing: 3) {
            Image(systemName: air.symbol)
                .symbolRenderingMode(.multicolor)
                .frame(minWidth: 14)
            Text(air.text)
            if feels.text != "–" {
                HStack(spacing: 1) {
                    Image(systemName: feels.symbol).imageScale(.small)
                    Text(feels.text)
                }
                .opacity(0.8)
                .padding(.leading, 3)
            }
        }
        .font(font.weight(.semibold))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Air temperature %@", air.text) + ", " + tr("Feels like %@", feels.text))
    }

    /// Fewer values: air with feels like, wind, waves and visibility, one under the other.
    var rightColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            airLine()
            valueLine(snapshot.value(.wind))
            valueLine(snapshot.value(.waves))
            valueLine(snapshot.value(.visibility))
        }
        .fixedSize()
    }

    /// All six values in two columns: air, water, rain | wind, waves, visibility.
    func sixGrid(font: Font = .caption) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            GridRow {
                airLine(font: font)
                valueLine(snapshot.value(.wind), font: font)
            }
            GridRow {
                valueLine(snapshot.value(.waterTemperature), font: font)
                valueLine(snapshot.value(.waves), font: font)
            }
            GridRow {
                valueLine(snapshot.rainValue, font: font)
                valueLine(snapshot.value(.visibility), font: font)
            }
        }
        .fixedSize()
    }

    /// All six values in a row of three, twice, as the top tile has them.
    func tileRow(font: Font = .subheadline) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                airLine(font: font)
                valueLine(snapshot.value(.waterTemperature), font: font)
                valueLine(snapshot.value(.wind), font: font)
            }
            GridRow {
                valueLine(snapshot.value(.waves), font: font)
                valueLine(snapshot.rainValue, font: font)
                valueLine(snapshot.value(.visibility), font: font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The extra large widget's six values, each with its name and grey line.
    var bigGrid: some View {
        let values: [WidgetValue] = [
            snapshot.value(.temperature), snapshot.value(.waterTemperature), snapshot.value(.wind),
            snapshot.value(.waves), snapshot.rainValue, snapshot.value(.visibility),
        ]
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(values[(row * 3)..<(row * 3 + 3)], id: \.condition) { value in
                        VStack(alignment: .leading, spacing: 1) {
                            Label(shortName(value.condition),
                                  systemImage: value.condition == .temperature ? Condition.temperature.symbol : value.symbol)
                                .font(.caption2.weight(.semibold))
                                .opacity(0.8)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(value.text)
                                .font(.title3.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .modifier(TintedIf(color: tint(value.light)))
                            Text(value.note.isEmpty ? " " : value.note)
                                .font(.caption2)
                                .opacity(0.75)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// One word per value, so the names fit the extra large widget's columns.
    private func shortName(_ condition: Condition) -> String {
        switch condition {
        case .temperature: tr("Air")
        case .waterTemperature: tr("Water")
        case .wind: tr("Wind")
        case .waves: tr("Waves")
        case .visibility: tr("Visibility")
        case .thunderstorm: tr("Thunderstorm")
        default: tr("Rain")
        }
    }

    /// The lines under the hours' temperatures in the larger sizes.
    enum HourLine: CaseIterable {
        case wind, waves, visibility

        var condition: Condition {
            switch self {
            case .wind: .wind
            case .waves: .waves
            case .visibility: .visibility
            }
        }

        /// The unit the legend names, in the user's units.
        var unit: String {
            let settings = AppSettings.shared
            return switch self {
            case .wind: settings.windUnit.symbol
            case .waves: settings.waveUnit.symbol
            case .visibility: settings.distanceUnit.symbol
            }
        }

        /// The number alone; the legend names the unit. Wind as mean–gust.
        func text(_ hour: ForecastHour) -> String {
            switch self {
            case .wind:
                let wind = hour.shownWind
                return "\(Format.windNumber(wind.speed))–\(Format.windNumber(wind.gust))"
            case .waves: return Format.wavesNumber(hour.shownWaveHeightM)
            case .visibility: return Format.distanceNumber(hour.shownVisibilityM)
            }
        }
    }

    /// The next hours: time, sky, light, temperature, and in the larger sizes
    /// the given lines. With `legend` a first column names each line's unit, and
    /// the temperatures go without "°", as in the 48 h table (owner, 13 Nov 2026).
    /// With lines, the temperatures are one of them, in the same small style (owner, 14 Nov 2026);
    /// without `temperature` (medium) only time, symbol and light show.
    func hourRow(count: Int, lines: [HourLine], legend: Bool = false, big: Bool = false, temperature: Bool = true) -> some View {
        let hours = Array(snapshot.hours.prefix(count))
        return Grid(horizontalSpacing: 0, verticalSpacing: big ? 5 : 4) {
            GridRow {
                if legend { Color.clear.frame(width: 0, height: 0) }
                ForEach(Array(hours.enumerated()), id: \.element.time) { index, hour in
                    Text(index == 0 ? tr("Now") : Format.time(hour.time))
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            GridRow {
                if legend { Color.clear.frame(width: 0, height: 0) }
                ForEach(hours, id: \.time) { hour in
                    // Fixed heights, so a taller rain symbol never squeezes the time above it.
                    skyIcon(hour)
                        .font(big ? .title3 : .subheadline)
                        .frame(height: big ? 26 : 20)
                        .frame(maxWidth: .infinity)
                }
            }
            GridRow {
                if legend { Color.clear.frame(width: 0, height: 0) }
                ForEach(hours, id: \.time) { hour in
                    lightDot(hour.light, size: big ? 16 : 13, hour: true)
                        .frame(maxWidth: .infinity)
                }
            }
            if temperature {
                GridRow {
                    if legend { legendLabel(Condition.temperature.symbol, AppSettings.shared.temperatureUnit.symbol) }
                    ForEach(hours, id: \.time) { hour in
                        let text = Text(legend ? Format.temperatureNumber(hour.temperatureC) : Format.degrees(hour.temperatureC))
                        if lines.isEmpty {
                            text
                                .font((big ? Font.subheadline : .caption).weight(.semibold))
                                .frame(maxWidth: .infinity)
                        } else {
                            text
                                .font(.caption2)
                                .opacity(0.85)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .modifier(TintedIf(color: tint(Condition.temperature.cause(in: hour))))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            ForEach(lines, id: \.self) { line in
                GridRow {
                    if legend { legendLabel(line.condition.symbol, line.unit) }
                    ForEach(hours, id: \.time) { hour in
                        Text(line.text(hour))
                            .font(.caption2)
                            .opacity(0.85)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .modifier(TintedIf(color: tint(line.condition.cause(in: hour))))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// The legend's symbol and unit at the start of an hour line.
    private func legendLabel(_ symbol: String, _ unit: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).imageScale(.small)
            Text(unit)
        }
        .font(.caption2)
        .opacity(0.75)
        .lineLimit(1)
        .fixedSize()
        .gridColumnAlignment(.leading)
        .padding(.trailing, 4)
        .accessibilityHidden(true)
    }

    /// The good rowing times as one bar per day: green, amber (striped with marks)
    /// and red (an outline with marks), past hours faint, and the first good stretch.
    func dayBars(_ count: Int, header: Bool, big: Bool) -> some View {
        let days = snapshot.days(count)
        return VStack(alignment: .leading, spacing: big ? 8 : 4) {
            if header {
                Label(tr("Good to row"), systemImage: "figure.rower")
                    .font(.caption.weight(.semibold))
            }
            if days.isEmpty {
                Text(snapshot.noWindowsText).font(.caption).opacity(0.85)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                HStack(spacing: 8) {
                    Text(day.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: big ? 64 : 54, alignment: .leading)
                    HStack(spacing: 2) {
                        ForEach(Array(day.lights.enumerated()), id: \.offset) { index, light in
                            segment(light, past: day.past[index])
                        }
                        // Not forecast yet: room kept, a faint dashed outline.
                        ForEach(0..<day.missing, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .opacity(0.35)
                        }
                    }
                    .frame(height: big ? 10 : 8)
                    .accessibilityHidden(true)
                    Text(day.good ?? (snapshot.isStale ? "–" : day.missing > 0 ? tr("Not known yet") : tr("Not good")))
                        .font(.caption.monospacedDigit())
                        .opacity(day.good == nil ? 0.75 : 1)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func segment(_ light: Light, past: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let faint = plain ? Color.secondary.opacity(0.25) : Color.white.opacity(0.22)
        if past {
            shape.fill(faint)
        } else if snapshot.isStale {
            // Out of date: grey, not even amber or red, as the hours row.
            shape.fill(Color.gray)
        } else if showMarks && light == .red {
            shape.strokeBorder(Light.red.color, lineWidth: 1.5)
        } else if showMarks && light == .amber {
            shape.fill(Light.amber.color)
                .overlay(Stripes().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                .clipShape(shape)
        } else {
            shape.fill(light.color(stale: snapshot.isStale))
        }
    }

    // MARK: Layouts

    /// C1: the ring with the short words; C6: a smaller ring and all six values.
    func smallLayout(_ hour: ForecastHour) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            topLine
            if layout == .fewer {
                Spacer(minLength: 0)
                ring(hour.light, size: 54)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(snapshot.shortTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        if let kit = coldWaterKit { coldWaterSymbol(kit) }
                    }
                    Text(snapshot.shortWhy)
                        .font(.caption.weight(.medium))
                        .opacity(0.9)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            } else {
                HStack(spacing: 8) {
                    ring(hour.light, size: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.shortTitle).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(snapshot.shortWhy)
                            .font(.caption2.weight(.medium))
                            .opacity(0.9)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
                sixGrid(font: .caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The top of the medium and large widgets: club, time and light on the left,
    /// the values on the right; all six make the light use its short words.
    func head(_ hour: ForecastHour) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                topLine
                verdict(hour, full: layout == .fewer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if layout == .fewer { rightColumn } else { sixGrid() }
        }
    }

    func mediumLayout(_ hour: ForecastHour) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            head(hour)
            Spacer(minLength: 0)
            switch focus {
            // Time, symbol and light only: the values under the dots are left out (owner, 14 Nov 2026).
            case .hourly: hourRow(count: 6, lines: [], temperature: false)
            case .windows: dayBars(2, header: false, big: false)
            case .conditions: tileRow(font: .caption)
            }
        }
    }

    /// R, T or 6 on top, then the hours and the next three days. The hours show
    /// wind, waves and visibility with a legend where they fit, else the wind alone,
    /// so the widget never runs over (owner's pick B with legend, 13 Nov 2026).
    func largeLayout(_ hour: ForecastHour) -> some View {
        ViewThatFits(in: .vertical) {
            largeStack(hour, lines: HourLine.allCases, legend: true)
            largeStack(hour, lines: [.wind], legend: false)
        }
    }

    private func largeStack(_ hour: ForecastHour, lines: [HourLine], legend: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if layout == .below {
                VStack(alignment: .leading, spacing: 6) {
                    topLine
                    verdict(hour, full: true)
                }
                tileRow()
            } else {
                head(hour)
            }
            rule
            hourRow(count: 6, lines: lines, legend: legend, big: true)
            rule
            Spacer(minLength: 0)
            dayBars(3, header: true, big: true)
            Spacer(minLength: 0)
        }
    }

    /// The light and the six values with their names on the left; eight hours and three days on the right.
    func extraLargeLayout(_ hour: ForecastHour) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                topLine
                verdict(hour, full: true)
                rule
                bigGrid
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .vertical) {
                extraLargeHours(lines: HourLine.allCases, legend: true)
                extraLargeHours(lines: [.wind], legend: false)
            }
        }
    }
}

extension RowingWidgetView {
    /// The extra large widget's right side: eight hours, then three days.
    fileprivate func extraLargeHours(lines: [HourLine], legend: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            hourRow(count: 8, lines: lines, legend: legend, big: true)
            rule
            Spacer(minLength: 0)
            dayBars(3, header: true, big: true)
            Spacer(minLength: 0)
        }
    }
}

/// Diagonal stripes for amber in the day bars, so it differs from green without colour.
struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return path
    }
}

/// The lock screen's round widget: the daylight of today as a ring of hours, bright where
/// it is good to row, dim where amber, faint where red or gone, a dot at now, and the
/// light's mark in the middle (owner's pick D, 6 Nov 2026).
struct DaylightRing: View {
    let day: WidgetDay?
    let now: Double?
    let mark: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Canvas { context, size in
                guard let day, !day.lights.isEmpty else { return }
                let radius = min(size.width, size.height) / 2 - 6
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                // From the lower left over the top to the lower right, open at the bottom.
                let start = 135.0, sweep = 270.0, gap = 3.0
                func point(_ degrees: Double) -> CGPoint {
                    let a = degrees * .pi / 180
                    return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
                }
                let n = Double(day.lights.count)
                for (index, light) in day.lights.enumerated() {
                    let from = start + sweep * Double(index) / n + gap / 2
                    let to = start + sweep * Double(index + 1) / n - gap / 2
                    var path = Path()
                    path.move(to: point(from))
                    for step in 1...8 { path.addLine(to: point(from + (to - from) * Double(step) / 8)) }
                    var width: CGFloat = 3
                    var opacity = 0.2
                    if !day.past[index] && light == .green {
                        width = 6
                        opacity = 1
                    } else if !day.past[index] && light == .amber {
                        width = 3.5
                        opacity = 0.6
                    }
                    context.stroke(path, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                }
                if let now {
                    let p = point(start + sweep * now)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(.white))
                }
            }
            Image(systemName: mark)
                .font(.system(size: 22, weight: .bold))
        }
    }
}

/// Colours a view only when there is a colour, so it otherwise keeps the widget's own.
struct TintedIf: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(self)
    }
}
