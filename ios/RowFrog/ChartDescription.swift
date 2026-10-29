import Accessibility
import SwiftUI

/// What VoiceOver reads for a chart, and what its audio graph plays: each line
/// as a series over time, the values in the chart's unit.
struct ChartDescription: AXChartDescriptorRepresentable {
    struct Series {
        let name: String
        let points: [(Date, Double)]
        /// False for bars (rain per hour), true for lines.
        var continuous = true
    }

    let title: String
    let unit: String
    let series: [Series]
    var summary: String? = nil
    var digits = 1

    func makeChartDescriptor() -> AXChartDescriptor {
        let times = series.flatMap { $0.points.map { $0.0.timeIntervalSince1970 } }
        let values = series.flatMap { $0.points.map(\.1) }
        let t0 = times.min() ?? 0, v0 = values.min() ?? 0
        let x = AXNumericDataAxisDescriptor(title: tr("Time"), range: t0...max(times.max() ?? t0, t0 + 1),
                                            gridlinePositions: []) { Format.dayTime(Date(timeIntervalSince1970: $0)) }
        let y = AXNumericDataAxisDescriptor(title: unit, range: v0...max(values.max() ?? v0, v0 + 1),
                                            gridlinePositions: []) { value(for: $0) }
        return AXChartDescriptor(title: title, summary: summary, xAxis: x, yAxis: y, additionalAxes: [],
                                 series: series.map { s in
            AXDataSeriesDescriptor(name: s.name, isContinuous: s.continuous,
                                   dataPoints: s.points.map { AXDataPoint(x: $0.0.timeIntervalSince1970, y: $0.1) })
        })
    }

    private func value(for y: Double) -> String {
        Format.number(y, digits: digits) + (unit.isEmpty ? "" : " " + unit)
    }
}
