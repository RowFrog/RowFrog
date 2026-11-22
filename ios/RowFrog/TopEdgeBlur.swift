import SwiftUI
import UIKit

/// The soft blur at the top of the swiping club pages while a page is scrolled (owner's
/// pick, way 4, 22 Nov 2026): strongest under the clock, weaker step by step and gone a
/// little below the top buttons and the small name, with no line where it ends. It is
/// the same method as the website's `.soft-edge` (#572): four blurs stacked over each
/// other, each faded out by a gradient a little higher than the one before, plus a
/// light tint. It replaces the navigation stack per page (#546), whose soft edge ended
/// in a hard cut on the device and whose bars crashed the app on quick swipes.
/// It lies over the page column only (the TabView), never over the list beside it.
struct TopEdgeBlur: View {
    /// Where on screen the cards should be hidden completely: below the clock, or
    /// below the small name and the top buttons.
    let edge: CGFloat
    /// How far below `edge` the blur runs out.
    static let runOut: CGFloat = 24

    var body: some View {
        // Fractions of the whole height, as the website's (style.css .soft-edge).
        let height = edge + Self.runOut
        ZStack {
            BlurLayers()
            LinearGradient(stops: [
                .init(color: Color(.systemBackground).opacity(0.45), location: 0),
                .init(color: Color(.systemBackground).opacity(0.2), location: 0.4),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// UIKit blur views with gradient masks: SwiftUI materials under a gradient mask did not
/// blur on the owner's iPad (#439, 17 Nov 2026: the text behind only dimmed).
private struct BlurLayers: UIViewRepresentable {
    func makeUIView(context: Context) -> BlurLayersView { BlurLayersView() }
    func updateUIView(_ view: BlurLayersView, context: Context) {}
}

final class BlurLayersView: UIView {
    /// Each blur is full down to `full` and gone at `clear` (fractions of the height);
    /// the lower ones reach further down, so the blur grows towards the top.
    private static let layers: [(style: UIBlurEffect.Style, full: CGFloat, clear: CGFloat)] = [
        (.systemUltraThinMaterial, 0.55, 1.0),
        (.systemUltraThinMaterial, 0.35, 0.8),
        (.systemUltraThinMaterial, 0.2, 0.62),
        (.systemThinMaterial, 0.05, 0.45),
    ]

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for layer in Self.layers {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: layer.style))
            blur.mask = FadeMask(full: layer.full, clear: layer.clear)
            addSubview(blur)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for blur in subviews {
            blur.frame = bounds
            blur.mask?.frame = blur.bounds
        }
    }
}

/// Opaque down to `full`, clear from `clear`: the mask of one blur layer.
private final class FadeMask: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(full: CGFloat, clear: CGFloat) {
        super.init(frame: .zero)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        gradient.locations = [0, NSNumber(value: Double(full)), NSNumber(value: Double(clear))]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
