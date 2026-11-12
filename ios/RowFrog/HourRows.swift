import SwiftUI

// Split off LocationPageView.swift (owner's large-file rule, 4 Nov 2026): the rows of the
// 48-hour table, an hour (HourRow) and a folded night (NightRow). Moved unchanged apart from
// dropping `private`, in the change that gave HourRow its half-and-half dot.

struct HourRow: View {
    let hour: ForecastHour
    var stale = false
    /// Half and half when the light changes in this hour (sunset to the minute, DaylightRule).
    var halves: DotHalves?
    /// From a coarser model than the first hours (the night after the 48 hours): "≈" before the time.
    var coarser = false

    var body: some View {
        let dark = hour.sunUp == false
        HStack(spacing: 6) {
            Text((coarser ? "≈" : "") + Format.time(hour.time))
                .frame(width: HourColumn.time, alignment: .leading)
            TrafficLightDot(light: hour.light, size: 12, stale: stale, halves: halves).frame(width: HourColumn.light)
            SkyIcon(sky: Sky(hour: hour), night: dark)
                .font(.callout)
                .frame(width: HourColumn.sky)
            cell(Format.degrees(hour.temperatureC).replacingOccurrences(of: "°", with: ""))
            cell(Format.degrees(hour.apparentTemperatureC).replacingOccurrences(of: "°", with: ""))
                .foregroundStyle(.secondary)
            cell(hour.windSpeedMs.map { "\(Format.windNumber($0))–\(Format.windNumber(hour.windGustMs))" } ?? "–")
            cell(Format.wavesNumber(hour.waveHeightM))
            cell(Format.rainNumber(hour.precipitationMm))
                .foregroundStyle((hour.precipitationMm ?? 0) >= 0.1 ? Color.blue : .primary)
            cell(Format.distanceNumber(hour.visibilityM))
                .foregroundStyle(hour.light(for: ["fog"]).map(\.color) ?? .primary)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(dark ? 0.6 : 1)
        .padding(.vertical, 2)
        // One element for VoiceOver, read as a sentence instead of ten loose numbers;
        // it also keeps the page's accessibility tree small enough for the UI tests
        // to read on the slower simulators (48 rows of ten values each).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [Format.time(hour.time), halves.map { tr("%@, then %@", $0.start.title, $0.end.title) } ?? hour.light.title]
        parts.append(Sky(hour: hour).title)
        parts.append(Format.degrees(hour.temperatureC))
        parts.append(tr("Feels like %@", Format.degrees(hour.apparentTemperatureC)))
        if let wind = hour.windSpeedMs { parts.append(tr("wind %@", Format.wind(wind))) }
        if let gust = hour.windGustMs { parts.append(tr("gusts up to %@", Format.wind(gust))) }
        if hour.waveHeightM != nil { parts.append(tr("waves %@", Format.waves(hour.waveHeightM))) }
        parts.append((hour.precipitationMm ?? 0) >= 0.1 ? tr("%@ rain", Format.rain(hour.precipitationMm)) : tr("dry"))
        if hour.visibilityM != nil { parts.append(tr("visibility %@", Format.distance(hour.visibilityM))) }
        if coarser { parts.append(tr("coarser model")) }
        return parts.joined(separator: ", ")
    }

    private func cell(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A folded night as one row of the table: its hours, a chevron and the moon in the
/// first three columns, then under each column the night's worst: lowest temperatures,
/// strongest wind and gust, highest waves, all its rain and its poorest visibility.
struct NightRow: View {
    let night: NightFold.Night
    let opened: Bool
    /// The table starts in this night (after the current hour's row), or is cut off in it.
    var startsTable = false
    var endsTable = false
    /// Where the night's later hours come from a coarser model (after the 48 hours): from
    /// when and which, said in a second line inside the night line (owner, 12 Nov 2026).
    var coarser: (from: Date, part: ForecastSource.Part)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            values
            if let coarser {
                Text(Self.coarserText(from: coarser.from, part: coarser.part))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, -6)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(opened ? tr("Opened") : tr("Folded"))
        .accessibilityHint(opened ? tr("Folds the night hours") : tr("Shows the night hours"))
        .accessibilityAddTraits(.isButton)
    }

    /// "≈ from 00:00 coarser model: ICON-EU, 7 km grid"
    static func coarserText(from: Date, part: ForecastSource.Part) -> String {
        "≈ " + tr("from %@ coarser model: %@", Format.time(from), "\(part.model), \(ForecastSourceLine.grid(part.resolutionKm))")
    }

    private var values: some View {
        HStack(spacing: 6) {
            Text(range)
                .fontWeight(.semibold)
                .minimumScaleFactor(0.7)
                .frame(width: HourColumn.time, alignment: .leading)
            Image(systemName: opened ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: HourColumn.light)
            Image(systemName: "moon.stars.fill")
                .font(.callout)
                .frame(width: HourColumn.sky)
            HStack(spacing: 1) {
                if night.frost { Image(systemName: "snowflake").font(.caption2) }
                Text(Format.degrees(night.lowestC).replacingOccurrences(of: "°", with: ""))
            }
            .foregroundStyle(night.frost ? Color.blue : .primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            cell(Format.degrees(night.lowestFeelsLikeC).replacingOccurrences(of: "°", with: ""))
                .foregroundStyle(.secondary)
            cell(night.strongestWindMs.map { "\(Format.windNumber($0))–\(Format.windNumber(night.strongestGustMs))" } ?? "–")
            cell(Format.wavesNumber(night.highestWavesM))
            cell(Format.rainNumber(night.rainMm))
                .foregroundStyle((night.rainMm ?? 0) >= 0.1 ? Color.blue : .primary)
            cell(Format.distanceNumber(night.poorestVisibilityM))
                .foregroundStyle(night.fogLight.map(\.color) ?? .primary)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "17–07"; "–07" when the table starts in the night, "17–" when it ends in it.
    private var range: String {
        let from = startsTable ? "" : hour(night.start)
        let to = endsTable ? "" : hour(night.end)
        return "\(from)–\(to)"
    }

    private func hour(_ date: Date) -> String {
        AppSettings.shared.activeTimeFormat.hour(from: date)
    }

    private var accessibilityText: String {
        var parts = [tr("Night from %@ to %@", Format.time(night.start), Format.time(night.end))]
        parts.append(tr("lowest %@", Format.degrees(night.lowestC)))
        if night.frost { parts.append(tr("frost")) }
        if let gust = night.strongestGustMs { parts.append(tr("gusts up to %@", Format.wind(gust))) }
        parts.append((night.rainMm ?? 0) >= 0.1 ? tr("%@ rain", Format.rain(night.rainMm)) : tr("dry"))
        if night.fogLight != nil { parts.append(tr("fog, visibility down to %@", Format.distance(night.poorestVisibilityM))) }
        if let coarser { parts.append(String(Self.coarserText(from: coarser.from, part: coarser.part).dropFirst(2))) }
        return parts.joined(separator: ", ")
    }

    private func cell(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .trailing)
    }
}
