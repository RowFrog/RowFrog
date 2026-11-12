import Foundation

/// What makes a part of the lake amber or red, and whether that holds near the
/// shore or out on open water while the rest is better (owner, 12 Nov 2026:
/// fog along both shores turned all three parts red while the middle of the
/// lake was clear, and the lines named only the waves).
struct LakeZoneNote: Equatable {
    enum Place: Equatable {
        /// The worse squares lie along the shore; the open water is better.
        case shore
        /// The worse squares lie out on open water; near the shore is better.
        case openWater
        /// Both mixed, or the whole part alike.
        case parts
    }

    /// The light of the part: its worst square.
    let light: Light
    /// "Fog", "Wind", "Waves", "Thunderstorm" ...: what makes the most of the worst squares that light.
    let cause: String?
    /// Where the worst squares lie, when at least `minBetterShare` of the part is better.
    let place: Place?
    /// The light of the better squares: green or amber.
    let rest: Light

    /// Below this share of better squares, the part counts as alike all over.
    static let minBetterShare = 0.1

    /// "Fog near the shore, open water clear", or just "Fog"; nil while green.
    var text: String? {
        guard light > .green else { return nil }
        guard let cause else { return nil }
        switch (place, rest) {
        case (.shore?, .green): return tr("%@ near the shore, open water clear", cause)
        case (.shore?, _): return tr("%@ near the shore, open water: row with care", cause)
        case (.openWater?, .green): return tr("%@ on open water, near the shore clear", cause)
        case (.openWater?, _): return tr("%@ on open water, near the shore: row with care", cause)
        case (.parts?, _): return tr("%@ on part of the water", cause)
        case (nil, _): return cause
        }
    }
}

extension LakeView {
    /// How many squares each water cell lies from land: 1 along the shore,
    /// rising towards the middle. The edge of the grid counts as land.
    func shoreDistance() -> [Int] {
        let index = Dictionary(uniqueKeysWithValues: grid.cells.enumerated().map { ($1, $0) })
        var distance = [Int](repeating: 0, count: grid.cells.count)
        var queue: [Int] = []
        func neighbours(_ flat: Int) -> [Int?] {
            let row = flat / grid.cols, col = flat % grid.cols
            return [(row - 1, col), (row + 1, col), (row, col - 1), (row, col + 1)].map { r, c in
                (0..<grid.rows).contains(r) && (0..<grid.cols).contains(c) ? index[r * grid.cols + c] : nil
            }
        }
        for (i, flat) in grid.cells.enumerated() where neighbours(flat).contains(where: { $0 == nil }) {
            distance[i] = 1
            queue.append(i)
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            for case let n? in neighbours(grid.cells[i]) where distance[n] == 0 {
                distance[n] = distance[i] + 1
                queue.append(n)
            }
        }
        return distance
    }

    /// What makes a square its light: the strongest other reason, then fog,
    /// wind and waves, as on a tapped spot.
    func cause(ofCell i: Int, hour: LakeHour) -> String? {
        let light = hour.lights[i]
        guard light > .green else { return nil }
        let found = probe(cell: i, hour: hour, limits: limits)
        if let extra = found.extra, extra.light == light { return extra.name }
        let byName = Dictionary(found.values.map { ($0.name, $0.light) }, uniquingKeysWith: { Swift.max($0, $1) })
        if byName[tr("Visibility")] == light { return tr("Fog") }
        if byName[tr("Wind")] == light { return tr("Wind") }
        if byName[tr("Waves")] == light { return tr("Waves") }
        return nil
    }

    /// One note per part of the lake (same order as `zones`), plus one for the
    /// whole lake as the last entry.
    func zoneNotes(for hour: LakeHour) -> [LakeZoneNote] {
        let n = hour.lights.count
        guard n > 0, grid.cellZone.count == n else { return [] }
        let distance = shoreDistance()
        func note(_ cells: [Int]) -> LakeZoneNote {
            let light = cells.map { hour.lights[$0] }.max() ?? .green
            guard light > .green else { return LakeZoneNote(light: light, cause: nil, place: nil, rest: .green) }
            let worse = cells.filter { hour.lights[$0] == light }
            let better = cells.filter { hour.lights[$0] < light }
            let causes = Dictionary(grouping: worse.compactMap { cause(ofCell: $0, hour: hour) }, by: { $0 })
            let cause = causes.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
            guard !cells.isEmpty, Double(better.count) / Double(cells.count) >= LakeZoneNote.minBetterShare else {
                return LakeZoneNote(light: light, cause: cause, place: nil, rest: light)
            }
            let mean = { (c: [Int]) in Double(c.map { distance[$0] }.reduce(0, +)) / Double(c.count) }
            let gap = mean(worse) - mean(better)
            let place: LakeZoneNote.Place = gap <= -0.5 ? .shore : gap >= 0.5 ? .openWater : .parts
            return LakeZoneNote(light: light, cause: cause, place: place, rest: better.map { hour.lights[$0] }.max() ?? .green)
        }
        var notes = zones.indices.map { z in note((0..<n).filter { grid.cellZone[$0] == z }) }
        notes.append(note(Array(0..<n)))
        return notes
    }
}
