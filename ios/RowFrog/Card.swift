import SwiftUI

// Moved unchanged out of LocationPageView.swift (large-file rule, 6 Nov 2026).

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    /// Shows an ⓘ in the title row that opens this part of the legend.
    var legend: LegendPart? = nil
    /// The whole card opens something (the lake view): a › at the end of the title
    /// row, as on the value tiles, instead of a text link (owner, 13 Nov 2026).
    /// The title row opens it too.
    var opens: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.surface) private var surface
    /// A one-time tip about this card, under its title (TipPlacement.swift, rule R1).
    @Environment(\.cardTip) private var cardTip
    @State private var showingLegend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    Label(title.uppercased(), systemImage: symbol ?? "")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if legend != nil {
                        Spacer(minLength: 0)
                        LegendButton(showing: $showingLegend)
                    } else if opens != nil {
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { opens?() }
                if let cardTip { cardTip }
            }
            // A card inside this one gets no tip of its own from here.
            content
                .environment(\.cardTip, nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(surface)
        .sheet(isPresented: $showingLegend) {
            if let legend { LegendSheet(part: legend) }
        }
    }
}

/// The ⓘ that opens a card's part of the legend.
struct LegendButton: View {
    @Binding var showing: Bool

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle").font(.subheadline)
                .tapArea(12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel(tr("What the symbols mean"))
    }
}
