import SwiftUI

/// The waves page's map: the lake view's waves layer at the hour of the chart's
/// blue line, in the place the other pages have their weather map (owner,
/// 13 Nov 2026). The weather models draw no waves; the lake view works them out
/// per lake. A tap opens the lake view on its waves layer at that hour.
struct DetailLakeCard: View {
    let lakeID: String
    let clubID: String
    let data: ConditionData
    let time: DetailTime
    var height: CGFloat = ConditionDetailView.mapHeight
    @MainActor private var store: LakeViewStore { .shared }
    @State private var full = false

    /// The hour of the chart's blue line.
    private var date: Date { data.now.time.addingTimeInterval(time.hour * 3600) }

    var body: some View {
        Group {
            if let view = store.views[lakeID, club: clubID], let first = view.hours.first, let last = view.hours.last {
                let hour = view.hours[view.hourIndex(at: date)]
                // Before or after the lake view's hours: the nearest one, greyed, as the weather maps.
                let outside = date < first.time || date >= last.time.addingTimeInterval(3600)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: Condition.waves.symbol).foregroundStyle(.secondary)
                        Text(verbatim: view.name + " · " + Format.dayTime(hour.time))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.tint)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    LakeMiniMap(view: view, hour: hour, clubID: clubID, layer: .waves)
                        .saturation(outside ? 0.2 : 1)
                        .opacity(outside ? 0.6 : 1)
                        .padding([.horizontal, .bottom], 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture { full = true }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(tr("Opens the lake view"))
                // The chart's green band: the hours the lake view has.
                .task(id: view.hours.count) { time.mapHours = view.hours.map { data.x($0.time) } }
                .fullScreenCover(isPresented: $full) {
                    LakeMapScreen(view: view, clubID: clubID, at: hour.time, layer: .waves)
                        .environment(\.locale, AppSettings.shared.locale)
                }
            } else if !store.failed(lakeID) {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .task { await store.load(lakeID) }
    }
}
