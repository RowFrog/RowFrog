import SwiftUI

/// The parts of the lake in the lake tile as a small table, styled like the
/// 48-hour table: a map symbol over the parts, wind with its direction under
/// one wind symbol (arrow under a compass, speed under the unit), waves and
/// visibility (that order everywhere, owner 13 Nov 2026), one line under the header (owner's H1, 12 Nov 2026). Values
/// that set amber or red show in that colour. A thunderstorm, hail or heavy
/// rain and the "near the shore" note follow a part on their own line. When
/// the table is too wide (narrow phones, larger text) each part falls back to
/// its name over its values.
struct LakeZoneTable: View {
    let view: LakeView
    let hour: LakeHour
    /// Each value column's icon and unit share this width and stand at its right
    /// end, so the unit centres under its icon, as in the 48-hour table.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 20

    private struct Row: Identifiable {
        let id: Int
        let name: String
        let light: Light
        let reading: LakeZoneReading
        let note: String?
    }

    private var rows: [Row] {
        let notes = view.zoneNotes(for: hour)
        return view.zones.indices.compactMap { i in
            guard i < hour.zones.count, let reading = view.zoneReading(i, hour: hour) else { return nil }
            let light = hour.zones[i].light
            let note = i < notes.count && notes[i].light == light ? notes[i].text : nil
            return Row(id: i, name: LakeZoneName.title(view.zones[i], water: view.water), light: light, reading: reading, note: note)
        }
    }

    var body: some View {
        let rows = self.rows
        ViewThatFits(in: .horizontal) {
            table(rows)
            stacked(rows)
        }
    }

    // MARK: Table

    private func table(_ rows: [Row]) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 9, verticalSpacing: 5) {
            header
            Divider()
            ForEach(rows) { row in
                GridRow {
                    HStack(spacing: 6) {
                        TrafficLightDot(light: row.light, size: 10, stale: view.isStale)
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    // Takes the room left over, so the numbers end at the tile's edge.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gridColumnAlignment(.leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(row))
                    // Wind, waves, visibility, as everywhere in the app (owner, 13 Nov 2026).
                    arrow(row.reading)
                    number(row.reading.speedMs.map { "\(Format.windNumber($0))–\(Format.windNumber(row.reading.gustMs))" } ?? "–",
                           row.reading.windLight)
                    number(Format.wavesNumber(row.reading.waveM), row.reading.waveLight)
                    number(Format.distanceNumber(row.reading.visM), row.reading.visLight)
                }
                if row.reading.extra != nil || row.note != nil {
                    GridRow {
                        extraLines(row)
                            .padding(.leading, 16)
                            .gridCellColumns(5)
                            .gridCellAnchor(.leading)
                    }
                }
            }
        }
        .font(.footnote)
    }

    /// Icon over unit for each column, as in the 48-hour table; the wind symbol
    /// stands over both its columns, a compass over the arrows and the unit over the speed.
    @ViewBuilder private var header: some View {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            ConditionIcon(condition: .wind).gridCellColumns(2).gridCellAnchor(.center)
            ConditionIcon(condition: .waves).frame(width: iconWidth)
            ConditionIcon(condition: .visibility).frame(width: iconWidth)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
        GridRow {
            // The map symbol stands for the parts' names, level with the units' row
            // and the icons' row together, as the clock does over the 48-hour table.
            Image(systemName: "map")
                .font(.subheadline)
                .gridColumnAlignment(.leading)
                .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.bottom] + $0.height * 0.2 }
            // Centred over the arrows by its frame, and level with the units by the row's
            // centre line: a cell anchor put it at the middle of the whole row, which
            // the map symbol makes taller, so it sat higher than the units (owner, 13 Nov 2026).
            Image(systemName: "safari").imageScale(.small)
                .frame(maxWidth: .infinity)
                .gridCellUnsizedAxes(.horizontal)
            unit(Condition.wind.unit)
            unit(Condition.waves.unit)
            unit(Condition.visibility.unit)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    /// Centred under its column's icon; a long unit ("mph") reaches past it rather than wrapping.
    private func unit(_ text: String) -> some View {
        Text(text).fixedSize().frame(width: iconWidth)
    }

    private func number(_ text: String, _ light: Light) -> some View {
        Text(text)
            .monospacedDigit()
            .fontWeight(light > .green ? .semibold : .regular)
            .foregroundStyle(light > .green ? AnyShapeStyle(light.color) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func arrow(_ r: LakeZoneReading) -> some View {
        if let from = r.fromDeg {
            Image(systemName: "arrow.up")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(from + 180))
                .foregroundStyle(r.windLight > .green ? AnyShapeStyle(r.windLight.color) : AnyShapeStyle(.secondary))
                .gridCellAnchor(.center)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
    }

    /// The strongest other reason and the "near the shore" note under a part.
    @ViewBuilder private func extraLines(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let extra = row.reading.extra { LakeProbeItemView(item: extra) }
            if let note = row.note {
                Text(note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        // Wraps to whatever width the table has, and never makes the table wider.
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Fallback

    /// Each part's name over its values, which wrap as needed: for narrow
    /// columns and larger text, where the table would not fit.
    private func stacked(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        TrafficLightDot(light: row.light, size: 10, stale: view.isStale)
                        Text(row.name).font(.subheadline.weight(.semibold))
                    }
                    LakeProbeValues(items: items(row.reading))
                        .font(.caption)
                        .padding(.leading, 16)
                    if let note = row.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 16)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(row))
            }
        }
    }

    /// The part's values for the lines; `spoken` names the wind's direction
    /// ("from NE") for VoiceOver, the lines show the table's arrow as a
    /// character, short enough not to be cut at the largest text sizes.
    private func items(_ r: LakeZoneReading, spoken: Bool = false) -> [LakeProbeItem] {
        let from = r.fromDeg.map { " " + (spoken ? tr("from %@", Format.compass($0)) : Self.arrowGlyph(towardDeg: $0 + 180)) } ?? ""
        var items = [
            LakeProbeItem(symbol: Condition.wind.symbol, name: tr("Wind"), text: Format.windRange(r.speedMs, r.gustMs) + from, light: r.windLight),
            LakeProbeItem(symbol: Condition.waves.symbol, name: tr("Waves"), text: Format.waves(r.waveM), light: r.waveLight),
        ]
        if r.visM != nil {
            items.append(LakeProbeItem(symbol: Condition.visibility.symbol, name: tr("Visibility"), text: Format.distance(r.visM), light: r.visLight))
        }
        if let extra = r.extra { items.append(extra) }
        return items
    }

    /// The arrow nearest to where the wind blows: ↑ ↗ → ↘ ↓ ↙ ← ↖.
    static func arrowGlyph(towardDeg: Double) -> String {
        let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
        let i = Int((towardDeg.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45) % 8
        return arrows[i]
    }

    /// "North: wind 2–4 m/s from NE, waves 0.06 m, visibility 17 km", then the light's word,
    /// another reason and the note, for VoiceOver.
    private func label(_ row: Row) -> String {
        var parts = [row.name + ": " + row.light.title(stale: view.isStale)]
        parts += items(row.reading, spoken: true).map { "\($0.name) \($0.text)" }
        if let note = row.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
