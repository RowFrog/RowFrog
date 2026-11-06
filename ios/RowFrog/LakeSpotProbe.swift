import SwiftUI

/// What a tapped spot on the lake map says: the rowing light, then waves, wind
/// and visibility as symbol and value, and the strongest other reason (hail, a
/// thunderstorm or heavy rain) only when it is amber or red. A value at amber
/// or red takes that colour, as on the top tile (owner's E2 and G, 6 Nov 2026).
///
/// Split off LakeMapScreen.swift on 6 Nov 2026 (large-file rule): the spot line
/// used to be built there as one `Text`.
struct LakeSpotProbe: View {
    let light: Light
    let stale: Bool
    let values: [LakeProbeItem]
    let extra: LakeProbeItem?

    var body: some View {
        // E2: one line only where the longest verdict with wide values fits, so
        // the panel never jumps between spots or hours; otherwise two lines.
        ViewThatFits(in: .horizontal) {
            oneLineLayout
            twoLineLayout
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Split into parts so older compilers type-check the body in time.
    private var allItems: [LakeProbeItem] {
        var items = values
        if let extra { items.append(extra) }
        return items
    }

    private var accessibilityText: String {
        let parts: [String] = allItems.map { $0.name + " " + $0.text }
        return ([light.title(stale: stale)] + parts).joined(separator: ", ")
    }

    private var oneLineLayout: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .leading) {
                oneLine(verdict: Self.longestVerdict, values: Self.template).hidden()
                oneLine(verdict: light.title(stale: stale), values: values)
            }
            .fixedSize(horizontal: true, vertical: false)
            if let extra { LakeProbeItemView(item: extra) }
        }
    }

    private var twoLineLayout: some View {
        VStack(alignment: .leading, spacing: 3) {
            verdict(light.title(stale: stale))
            LakeProbeValues(items: allItems)
        }
    }

    private func verdict(_ title: String) -> some View {
        HStack(spacing: 6) {
            TrafficLightDot(light: light, size: 10, stale: stale)
            Text(title).fontWeight(.semibold)
        }
    }

    private func oneLine(verdict title: String, values: [LakeProbeItem]) -> some View {
        HStack(spacing: 6) {
            verdict(title)
            ForEach(values, id: \.self) { item in
                Text("·").foregroundStyle(.secondary)
                LakeProbeItemView(item: item)
            }
        }
    }

    /// The widest the first line gets: the longest verdict and wide values.
    private static var longestVerdict: String {
        ([Light.green, .amber, .red].map(\.title) + [Light.green.title(stale: true)])
            .max { $0.count < $1.count } ?? ""
    }

    private static var template: [LakeProbeItem] {
        [
            LakeProbeItem(symbol: Condition.waves.symbol, name: "", text: Format.waves(0.45), light: .green),
            LakeProbeItem(symbol: Condition.wind.symbol, name: "", text: Format.windRange(12, 18), light: .green),
            LakeProbeItem(symbol: Condition.visibility.symbol, name: "", text: Format.distance(500), light: .green),
        ]
    }
}

/// The values under the verdict, wrapping between whole items, never inside one.
struct LakeProbeValues: View {
    let items: [LakeProbeItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(items).fixedSize(horizontal: true, vertical: false)
            if items.count > 3 {
                VStack(alignment: .leading, spacing: 3) {
                    row(Array(items.prefix(3))).fixedSize(horizontal: true, vertical: false)
                    row(Array(items.dropFirst(3)))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                row(Array(items.prefix(2))).fixedSize(horizontal: true, vertical: false)
                row(Array(items.dropFirst(2)))
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { LakeProbeItemView(item: $0) }
            }
        }
    }

    private func row(_ items: [LakeProbeItem]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Text("·").foregroundStyle(.secondary) }
                LakeProbeItemView(item: item)
            }
        }
    }
}

/// Symbol and value; amber or red in that colour, otherwise grey.
struct LakeProbeItemView: View {
    let item: LakeProbeItem

    private var raised: Bool { item.light > .green }
    private var style: AnyShapeStyle { raised ? AnyShapeStyle(item.light.color) : AnyShapeStyle(.secondary) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: item.symbol).symbolRenderingMode(.hierarchical)
            Text(item.text).monospacedDigit()
        }
        .fontWeight(raised ? .semibold : .regular)
        .foregroundStyle(style)
        .lineLimit(1)
    }
}
