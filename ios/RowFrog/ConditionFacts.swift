import SwiftUI

/// The facts under a value view's chart: label and value in two columns, or for
/// the views with many short facts in a two-wide grid of label over value.
/// (Split off ConditionsCard.swift, 14 Nov 2026.)
struct ConditionFacts: View {
    let facts: [(String, String)]
    var twoColumns = false
    /// The label column takes what it needs up to this width and then wraps at
    /// spaces; squeezed narrower, iOS broke long German words with a hyphen
    /// ("Wind-richtung", detail check 14 Nov 2026). Grows with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 150

    var body: some View {
        if twoColumns {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 8) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fact.0).font(.caption).foregroundStyle(.secondary)
                        Text(fact.1).font(.subheadline.weight(.semibold))
                    }
                }
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    GridRow {
                        Text(fact.0)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: labelWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Text(fact.1).fontWeight(.semibold)
                    }
                }
            }
            .font(.subheadline)
        }
    }
}
