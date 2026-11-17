import SwiftUI
import TipKit

/// The chain button over a detail view's map. Linked, the map follows the
/// chart's blue line; unlinked, it keeps its own time. The weather maps and
/// the waves page's lake map share it, so both look and work alike (owner,
/// 17 Nov 2026).
struct MapLinkButton: View {
    let time: DetailTime
    /// Called before the switch, e.g. to stop playing.
    var willToggle: () -> Void = {}

    var body: some View {
        Button {
            willToggle()
            MapLinkTip().invalidate(reason: .actionPerformed)
            withAnimation(.easeInOut(duration: 0.2)) { time.setLinked(!time.linked) }
        } label: {
            Label(time.linked ? tr("Linked") : tr("Own time"), systemImage: "link")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(time.linked ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    if !time.linked { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.4)) }
                }
                .foregroundStyle(time.linked ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Map follows the chart"))
        .accessibilityValue(time.linked ? tr("Linked") : tr("Own time"))
        .popoverTip(MapLinkTip(), arrowEdge: .top)
    }
}

/// Play, slider and repeat under a detail view's map, through `frames` (the
/// hours that have a picture). Linked, the chart follows. With repeat on,
/// playing goes round 3 times, as on the full-screen maps, then stops on the
/// hour it started from.
struct MapTimeControls: View {
    let time: DetailTime
    let data: ConditionData
    let frames: [Date]
    /// The frame shown now, if any.
    let frameIndex: Int?
    @Binding var playing: Bool
    /// Called on a tap of play, e.g. to close a tip.
    var didPlay: () -> Void = {}
    /// The same repeat switch as the full-screen maps'.
    @AppStorage(DefaultsKey.radarLoop) private var loops = true

    var body: some View {
        HStack(spacing: 10) {
            Button {
                playing.toggle()
                didPlay()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(playing ? tr("Pause") : tr("Play"))
            Slider(value: Binding(get: { Double(frameIndex ?? 0) }, set: { value in
                playing = false
                let i = Int(value.rounded())
                if frames.indices.contains(i) { time.setMap(data.x(frames[i]).rounded()) }
            }), in: 0...Double(max(frames.count - 1, 1)), step: 1)
            .opacity(time.mapOutOfRange ? 0.4 : 1)
            Button {
                loops.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(loops ? Color.accentColor : .secondary)
                    .padding(5)
                    .background(loops ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Play 3 times"))
            .accessibilityAddTraits(loops ? .isSelected : [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .task(id: playing) { await play() }
    }

    /// Plays through the frames from the shown one; linked, the chart follows.
    private func play() async {
        guard playing else { return }
        var i = frameIndex ?? 0
        if time.mapOutOfRange || i >= frames.count - 1 { i = 0 }
        let from = i
        var rounds = 0
        while playing, !Task.isCancelled, frames.indices.contains(i) {
            time.setMap(data.x(frames[i]).rounded())
            try? await Task.sleep(for: .milliseconds(i == frames.count - 1 ? 1400 : 700))
            guard playing, !Task.isCancelled else { return }
            if i < frames.count - 1 {
                i += 1
            } else if loops, rounds < 2 {
                rounds += 1
                i = 0
            } else {
                playing = false
                if loops { time.setMap(data.x(frames[from]).rounded()) }
            }
        }
    }
}
