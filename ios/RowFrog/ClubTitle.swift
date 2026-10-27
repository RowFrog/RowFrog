import SwiftUI

/// A club's name on one line: the long name with the short one in brackets
/// where it fits ("Münchener Ruder-Club von 1880 e.V. (MRC 1880)"), else the
/// short name alone, shrunk a little before it is cut. Never wraps.
struct ClubTitle: View {
    let club: Club

    var body: some View {
        if let full = club.fullTitle {
            ViewThatFits(in: .horizontal) {
                Text(full).lineLimit(1)
                short
            }
        } else {
            short
        }
    }

    private var short: some View {
        Text(club.displayName).lineLimit(1).minimumScaleFactor(0.7)
    }
}
