import SwiftUI

/// The waves page's map: the lake view's waves layer, in the place the other
/// pages have their weather map (owner, 13 Nov 2026). The weather models draw
/// no waves; the lake view works them out per lake. It looks and works as the
/// weather map cards do (owner's pick B, 17 Nov 2026, decision 0047): Apple's
/// map under the lake with the wind map's arrows on land, the chain button,
/// and play, slider and repeat through the lake view's hours. A tap opens the
/// lake view on its waves layer at the hour shown.
struct DetailLakeCard: View {
    let lakeID: String
    let clubID: String
    let data: ConditionData
    let time: DetailTime
    var height: CGFloat = ConditionDetailView.mapHeight
    @MainActor private var store: LakeViewStore { .shared }
    @State private var full = false
    @State private var playing = false

    /// The hour the map shows: the chart's blue line while linked, else its own.
    private var date: Date { data.now.time.addingTimeInterval(time.shownMapHour * 3600) }

    var body: some View {
        Group {
            if let view = store.views[lakeID, club: clubID], !view.hours.isEmpty {
                card(view)
            } else if !store.failed(lakeID) {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .task { await store.load(lakeID) }
    }

    private func card(_ view: LakeView) -> some View {
        let frames = view.hours.map(\.time)
        let index = view.hourIndex(at: date)
        let hour = view.hours[index]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: Condition.waves.symbol).foregroundStyle(.secondary)
                Text(verbatim: Format.dayTime(hour.time))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                MapLinkButton(time: time) { playing = false }
                Button {
                    full = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(tr("Opens the lake view"))
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            // Before or after the lake view's hours: the nearest one, greyed, as the weather maps.
            LakeMiniMap(view: view, hour: hour, clubID: clubID, layer: .waves, cornerRadius: 0)
                .saturation(time.mapOutOfRange ? 0.2 : 1)
                .opacity(time.mapOutOfRange ? 0.6 : 1)
                .overlay(alignment: .bottom) { note(frames) }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
                .onTapGesture { full = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(tr("Opens the lake view"))
            if frames.count > 1 {
                MapTimeControls(time: time, data: data, frames: frames, frameIndex: index, playing: $playing)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // The chart's green band: the hours the lake view has.
        .task(id: view.hours.count) { time.mapHours = frames.map { data.x($0) } }
        .fullScreenCover(isPresented: $full) {
            LakeMapScreen(view: view, clubID: clubID, at: hour.time, layer: .waves)
                .environment(\.locale, AppSettings.shared.locale)
        }
    }

    /// Past the lake view's end or before its start: the map keeps its nearest hour, dimmed.
    @ViewBuilder
    private func note(_ frames: [Date]) -> some View {
        if time.mapOutOfRange, let first = frames.first, let last = frames.last {
            Text(date > last ? tr("The maps end %@; the chart goes on.", Format.dayTime(last))
                             : tr("The maps start %@.", Format.dayTime(first)))
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
                .padding(8)
        }
    }
}
