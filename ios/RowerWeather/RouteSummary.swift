import SwiftUI

/// What a planned route meets: distance, time, the worst light on the way and
/// where it is roughest, with a bar of the conditions from start to finish.
struct RouteSummary: View {
    let view: LakeView
    let plan: RoutePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("%@ · %@ · finished at %@", Format.distance(plan.distanceM), Format.duration(from: plan.start, to: plan.end), Format.time(plan.end)))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            HStack(spacing: 6) {
                TrafficLightDot(light: plan.worstLight, size: 12)
                Text(plan.worstLight.title).font(.subheadline.weight(.semibold))
                Text(tr("Waves up to %@", Format.waves(plan.maxWaveM)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            RouteBar(plan: plan).frame(height: 8)
            if let rough = plan.roughest, plan.worstLight > .green {
                Text(roughText(rough))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.beyondForecast {
                Label(tr("The forecast ends before you are back."), systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if view.isStale {
                Label(tr("Forecast out of date: from %@. Check the conditions yourself.", Format.dayTime(view.generatedAt)), systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            AdviceOnlyNote()
        }
        .accessibilityElement(children: .combine)
    }

    /// "Roughest at 15:20, North: 0.36 m following sea, 5–8 m/s tailwind".
    private func roughText(_ stop: RoutePlan.Stop) -> String {
        var parts = [Format.waves(stop.waveM) + (stop.relation.map { " " + $0.waves } ?? "")]
        if stop.windMs != nil {
            parts.append(Format.windRange(stop.windMs, stop.gustMs) + (stop.relation.map { " " + $0.wind } ?? ""))
        }
        let zone = view.grid.cellZone.indices.contains(stop.cell) ? view.grid.cellZone[stop.cell] : 0
        let place = view.zones.count > 1 && zone < view.zones.count ? ", " + LakeZoneName.title(view.zones[zone]) : ""
        return tr("Roughest at %@", Format.time(stop.time)) + place + ": " + parts.joined(separator: ", ")
    }
}

/// The route from start to finish as a bar, coloured by the light at each stretch.
struct RouteBar: View {
    let plan: RoutePlan

    var body: some View {
        Canvas { ctx, size in
            guard plan.distanceM > 0 else { return }
            var from = 0.0
            for (i, stop) in plan.stops.enumerated() {
                let to = i + 1 < plan.stops.count ? (stop.distanceM + plan.stops[i + 1].distanceM) / 2 : plan.distanceM
                let rect = CGRect(x: size.width * from / plan.distanceM, y: 0, width: size.width * (to - from) / plan.distanceM + 0.5, height: size.height)
                ctx.fill(Path(rect), with: .color(stop.light.color))
                from = to
            }
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
