import SwiftUI

/// The parts of the lake in the lake tile as a small table, styled like the
/// 48-hour table: a map symbol over the parts, waves, wind with its direction
/// under one wind symbol (arrow under a compass, speed under the unit) and
/// visibility, one line under the header (owner's H1, 12 Nov 2026). Values
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
                    number(Format.wavesNumber(row.reading.waveM), row.reading.waveLight)
                    arrow(row.reading)
                    number(row.reading.speedMs.map { "\(Format.windNumber($0))–\(Format.windNumber(row.reading.gustMs))" } ?? "–",
                           row.reading.windLight)
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
            ConditionIcon(condition: .waves).frame(width: iconWidth)
            ConditionIcon(condition: .wind).gridCellColumns(2).gridCellAnchor(.center)
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
                .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.bottom] }
            unit(Condition.waves.unit)
            Image(systemName: "safari").imageScale(.small).gridCellAnchor(.center)
            unit(Condition.wind.unit)
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

    private func items(_ r: LakeZoneReading) -> [LakeProbeItem] {
        let from = r.fromDeg.map { " " + tr("from %@", Format.compass($0)) } ?? ""
        var items = [
            LakeProbeItem(symbol: Condition.waves.symbol, name: tr("Waves"), text: Format.waves(r.waveM), light: r.waveLight),
            LakeProbeItem(symbol: Condition.wind.symbol, name: tr("Wind"), text: Format.windRange(r.speedMs, r.gustMs) + from, light: r.windLight),
        ]
        if r.visM != nil {
            items.append(LakeProbeItem(symbol: Condition.visibility.symbol, name: tr("Visibility"), text: Format.distance(r.visM), light: r.visLight))
        }
        if let extra = r.extra { items.append(extra) }
        return items
    }

    /// "North: waves 0.06 m, wind 2–4 m/s from NE, visibility 17 km", then the light's word,
    /// another reason and the note, for VoiceOver.
    private func label(_ row: Row) -> String {
        var parts = [row.name + ": " + row.light.title(stale: view.isStale)]
        parts += items(row.reading).map { "\($0.name) \($0.text)" }
        if let note = row.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
