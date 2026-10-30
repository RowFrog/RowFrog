import CoreImage
import SwiftUI
import UIKit

/// A picture that comes with the app, in the style of the app icon.
struct SampleBackground: Identifiable, Hashable {
    let id: String
    let englishTitle: String

    var title: String { tr(englishTitle) }
    var choice: BackgroundChoice { .sample(id) }
}

/// The sample pictures in the app bundle and the user's own pictures,
/// which are copied into the app's files so they stay when removed from Photos.
enum BackgroundLibrary {
    static let samples: [SampleBackground] = [
        SampleBackground(id: "lake-waves", englishTitle: "Lake waves"),
        SampleBackground(id: "soft-waves", englishTitle: "Soft waves"),
        SampleBackground(id: "sunrise-sculler", englishTitle: "Sunrise sculler"),
        SampleBackground(id: "alpine-lake", englishTitle: "Alpine lake"),
        SampleBackground(id: "cloud-shell", englishTitle: "Frog in the cloud shell"),
        SampleBackground(id: "cloud-sculler", englishTitle: "Cloud sculler"),
        SampleBackground(id: "sunny-day", englishTitle: "Sunny day"),
        SampleBackground(id: "morning-mist", englishTitle: "Morning mist"),
        SampleBackground(id: "rain-on-the-lake", englishTitle: "Rain on the lake"),
        SampleBackground(id: "thunderstorm", englishTitle: "Thunderstorm"),
        SampleBackground(id: "winter-ice", englishTitle: "Winter ice"),
        SampleBackground(id: "night-lake", englishTitle: "Night on the lake"),
    ]

    static func sample(_ id: String) -> SampleBackground? {
        samples.first { $0.id == id }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Each saved club's lake and the home base, for the satellite picture;
    /// kept up to date by WidgetBridge whenever the saved clubs change.
    static var lakeByClub: [String: String] = [:]
    static var homeClubID: String?

    /// The picture for a choice, or nil for "no picture" or a missing file.
    /// The satellite picture is the club's lake's (the home base's without a
    /// club) and nil until it has loaded. Thumbnails are scaled down for the picker's grid.
    static func image(for choice: BackgroundChoice, clubID: String? = nil, thumbnail: Bool = false) -> UIImage? {
        let url: URL?
        switch choice {
        case .noPicture: return nil
        case .satellite:
#if WIDGET_EXTENSION
            return nil
#else
            guard let club = clubID ?? homeClubID, let lake = lakeByClub[club] else { return nil }
            return MainActor.assumeIsolated { SatellitePictureStore.shared.backgroundImage(lake) }
#endif
        case let .sample(id): url = Bundle.main.url(forResource: "bg-\(id)", withExtension: "jpg")
        case let .custom(name): url = userDirectory.appending(path: name)
        }
        guard let url else { return nil }
        let key = "\(url.path)|\(thumbnail)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard var image = UIImage(contentsOfFile: url.path) else { return nil }
        if thumbnail {
            image = scaled(image, maxSide: 360)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    static var userDirectory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Backgrounds", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves a picture from Photos, scaled to the screen, and returns its file name.
    static func addUserPicture(_ data: Data) throws -> String {
        guard let original = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let image = scaled(original, maxSide: 2600)
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        let name = "user-\(UUID().uuidString).jpg"
        try jpeg.write(to: userDirectory.appending(path: name), options: .atomic)
        return name
    }

    static func deleteUserPicture(_ name: String) {
        let url = userDirectory.appending(path: name)
        try? FileManager.default.removeItem(at: url)
        cache.removeObject(forKey: "\(url.path)|true" as NSString)
        cache.removeObject(forKey: "\(url.path)|false" as NSString)
    }

    private static let blurredCache = NSCache<UIImage, UIImage>()
    private static let ciContext = CIContext()

    /// The picture blurred once and kept, so the screen does not blur it again
    /// on every frame while pages swipe. Made smaller first: the blur hides
    /// the detail anyway, and a small picture blurs fast and takes little memory.
    static func blurred(_ image: UIImage) -> UIImage {
        if let cached = blurredCache.object(forKey: image) { return cached }
        let small = scaled(image, maxSide: 800)
        guard let cg = small.cgImage else { return image }
        let input = CIImage(cgImage: cg)
        // About the 24 points the screen blurred with, at this size.
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: 22).cropped(to: input.extent)
        guard let result = ciContext.createCGImage(output, from: input.extent) else { return image }
        let picture = UIImage(cgImage: result, scale: small.scale, orientation: small.imageOrientation)
        blurredCache.setObject(picture, forKey: image)
        return picture
    }

    static func scaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let factor = maxSide / side
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// How cards are drawn: plain without a picture; over a picture either
/// frosted (the picture shows through, blurred) or solid (no picture inside).
enum Surface {
    case plain, frosted, solid
}

private struct SurfaceKey: EnvironmentKey {
    static let defaultValue = Surface.plain
}

/// Whether iOS Low Power Mode is on. The app then draws its tiles solid, lets
/// the radar map wait for a tap to play and refreshes the radar less often.
@Observable
@MainActor
final class PowerState {
    static let shared = PowerState()
    private(set) var lowPower = PowerState.isOn
    /// -RWLowPower YES draws the app as in Low Power Mode, for screenshots.
    private static var isOn: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled || UserDefaults.standard.bool(forKey: "RWLowPower") }
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerState.shared.lowPower = PowerState.isOn }
        }
    }
}

extension AppSettings {
    /// The tiles over a picture as drawn: solid in Low Power Mode, since blurred
    /// tiles are drawn again on every frame the page scrolls.
    @MainActor var tileSurface: Surface { PowerState.shared.lowPower ? .solid : tileStyle.surface }
}

/// How far each swiping club page is scrolled, for the top of the screen: as
/// in iOS's own bars, it stays clear at the top of a page, blurs once cards
/// scroll under the clock, and shows the club's name once its title is gone.
@MainActor @Observable
final class PageScroll {
    static let shared = PageScroll()
    /// Club pages with cards under the clock.
    private(set) var scrolled: Set<String> = []
    /// Club pages whose big title has gone under the top.
    private(set) var titleGone: Set<String> = []

    func update(_ clubID: String, scrolled isScrolled: Bool) {
        if scrolled.contains(clubID) != isScrolled { scrolled.formSymmetricDifference([clubID]) }
    }

    func update(_ clubID: String, titleGone gone: Bool) {
        if titleGone.contains(clubID) != gone { titleGone.formSymmetricDifference([clubID]) }
    }
}

private struct PageMarginsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

private struct CurrentPageKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// What a swiping club page keeps clear of at its edges (the clock, the
    /// floating page bar), as the pages themselves reach under both.
    var pageMargins: EdgeInsets {
        get { self[PageMarginsKey.self] }
        set { self[PageMarginsKey.self] = newValue }
    }

    /// Whether this club page is the one in front. Pages beside it stay alive
    /// in the swiping TabView and stop their timers.
    var isCurrentPage: Bool {
        get { self[CurrentPageKey.self] }
        set { self[CurrentPageKey.self] = newValue }
    }

    var surface: Surface {
        get { self[SurfaceKey.self] }
        set { self[SurfaceKey.self] = newValue }
    }
}

extension Surface {
    var hasPicture: Bool { self != .plain }

    /// A tile inside a card. Tiles in a frosted card stay a light shade, since
    /// frost on frost looks muddy.
    var tile: AnyShapeStyle {
        switch self {
        case .frosted: AnyShapeStyle(Color(.tertiarySystemGroupedBackground).opacity(0.55))
        case .plain, .solid: AnyShapeStyle(Color(.tertiarySystemGroupedBackground))
        }
    }

}

/// A card shaded in a rowing-light colour, as in the location list: over a
/// picture either frosted glass with a lighter shade, or solid with the full shade.
struct TintedCardBackground: View {
    let tint: Color
    var cornerRadius: CGFloat = 16
    @Environment(\.surface) private var surface

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        switch surface {
        case .plain:
            shape.fill(tint.opacity(0.18))
        case .solid:
            // Opaque, so the picture does not change the shading.
            shape.fill(Color(.systemGroupedBackground)).overlay(shape.fill(tint.opacity(0.18)))
        case .frosted:
            FrostedFill(shape: shape).overlay(shape.fill(tint.opacity(0.22)))
        }
    }
}

extension View {
    /// A card's background in the surface's card style.
    func cardBackground(_ surface: Surface, cornerRadius: CGFloat = 16) -> some View {
        cardBackground(surface, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// A card's background in any shape: frosted from the page's picture, or plain.
    func cardBackground(_ surface: Surface, in shape: some Shape) -> some View {
        background {
            if surface == .frosted {
                FrostedFill(shape: shape)
            } else {
                shape.fill(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    /// Behind text that sits on the picture itself, like a page's title: a thin
    /// frost over a picture, nothing over the plain background.
    func labelBackground(_ surface: Surface, in shape: some Shape) -> some View {
        background {
            if surface.hasPicture {
                FrostedFill(shape: shape, veil: 0.25)
            }
        }
    }

    /// Liquid Glass in the shape, optionally tinted; frosted glass with the
    /// tint on top before iOS 26 or when built with an older Xcode.
    @ViewBuilder
    func glass(tint: Color? = nil, in shape: some Shape) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            frostedGlass(tint: tint, in: shape)
        }
#else
        frostedGlass(tint: tint, in: shape)
#endif
    }

    private func frostedGlass(tint: Color?, in shape: some Shape) -> some View {
        background {
            shape.fill(.regularMaterial).overlay(shape.fill(tint ?? .clear))
        }
    }
}

/// Puts the page's background picture, or the plain grouped background, behind
/// the content, and tells the cards how to draw themselves over it.
struct PageBackground: ViewModifier {
    let page: PageKind
    var clubID: String? = nil
    /// Off where the picture is drawn further out, as behind the swiping club pages.
    var drawsPicture = true
    /// Where the picture lies when it is drawn further out.
    @Environment(\.pictureFrame) private var outerFrame
    @State private var ownFrame = CGRect.zero

    func body(content: Content) -> some View {
        let settings = AppSettings.shared
        let image = BackgroundLibrary.image(for: settings.background(for: page, clubID: clubID), clubID: clubID)
        let frame = drawsPicture ? ownFrame : outerFrame
        content
            .environment(\.surface, image == nil ? .plain : settings.tileSurface)
            .environment(\.frostPicture, image.flatMap { frame.isEmpty ? nil : FrostPicture(image: BackgroundLibrary.blurred($0), frame: frame) })
            .background {
                if drawsPicture {
                    PagePicture(image: image, blurred: settings.blurBackground) { ownFrame = $0 }
                }
            }
    }
}

extension View {
    func pageBackground(_ page: PageKind, clubID: String? = nil, drawsPicture: Bool = true) -> some View {
        modifier(PageBackground(page: page, clubID: clubID, drawsPicture: drawsPicture))
    }
}

/// A page's picture filling the screen, or the plain grouped background.
struct PagePicture: View {
    let image: UIImage?
    var blurred = false
    /// Where the picture lies on screen, for the frosted cards over it.
    var onFrame: ((CGRect) -> Void)? = nil

    var body: some View {
        if let image {
            BackgroundPicture(image: image, blurred: blurred, onFrame: onFrame)
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }
}

/// A picture filling the screen, clear or blurred, a little darker in dark mode
/// and lighter under the status and navigation bars so their text stays readable.
struct BackgroundPicture: View {
    let image: UIImage
    var blurred = false
    var onFrame: ((CGRect) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: blurred ? BackgroundLibrary.blurred(image) : image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay {
                if colorScheme == .dark {
                    Color.black.opacity(0.3)
                }
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color(.systemBackground).opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
            }
            .ignoresSafeArea()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                onFrame?(frame)
            }
            .accessibilityHidden(true)
    }
}

/// The picture behind a page, blurred once, and where it lies on screen.
struct FrostPicture: Equatable {
    let image: UIImage
    let frame: CGRect

    static func == (a: FrostPicture, b: FrostPicture) -> Bool { a.image === b.image && a.frame == b.frame }
}

private struct FrostPictureKey: EnvironmentKey {
    static let defaultValue: FrostPicture? = nil
}

private struct PictureFrameKey: EnvironmentKey {
    static let defaultValue = CGRect.zero
}

extension EnvironmentValues {
    /// The page's picture for frosted cards; nil over the plain background.
    var frostPicture: FrostPicture? {
        get { self[FrostPictureKey.self] }
        set { self[FrostPictureKey.self] = newValue }
    }

    /// Where a picture drawn behind several pages lies, as behind the swiping club pages.
    var pictureFrame: CGRect {
        get { self[PictureFrameKey.self] }
        set { self[PictureFrameKey.self] = newValue }
    }
}

/// Frosted glass made from the page's picture, blurred once: each card shows
/// its own piece of it, lined up with the picture behind. A live material
/// blurs again on every frame and has iOS rebuild every blur when the app
/// comes back, which with a dozen cards a page held up the return to the app.
struct FrostedFill<S: Shape>: View {
    let shape: S
    /// The light (or dark) wash over the picture, as a material has.
    var veil: Double = 0.55
    @Environment(\.frostPicture) private var picture
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let picture {
            let frame = picture.frame
            Color.clear
                .overlay(alignment: .topLeading) {
                    Image(uiImage: picture.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frame.width, height: frame.height)
                        .clipped()
                        .overlay {
                            if colorScheme == .dark { Color.black.opacity(0.3) }
                        }
                        // Placed by where the card is on screen, without a new
                        // layout pass when the page scrolls.
                        .visualEffect { content, proxy in
                            let origin = proxy.frame(in: .global).origin
                            return content.offset(x: frame.minX - origin.x, y: frame.minY - origin.y)
                        }
                }
                .overlay(Color(.systemBackground).opacity(colorScheme == .dark ? veil * 0.8 : veil))
                .clipShape(shape)
        } else {
            shape.fill(Color(.secondarySystemGroupedBackground))
        }
    }
}

extension View {
    /// A button floating over a picture or a map (the page bar, the lake map's
    /// buttons): Liquid Glass (frosted before iOS 26), as Apple's guide keeps
    /// glass for controls, and solid in Low Power Mode, which draws nothing live.
    @ViewBuilder
    func floatingControl(_ shape: some Shape) -> some View {
        if PowerState.shared.lowPower {
            background(shape.fill(Color(.secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.15), radius: 6, y: 2))
        } else {
            glass(in: shape)
        }
    }
}

extension View {
    /// Lets a tap land this far around a small control (Apple's guide asks for
    /// 44 × 44 pt), without changing how it looks or where things sit. Put it
    /// on a button's label, so the button takes the larger shape.
    func tapArea(_ insets: EdgeInsets) -> some View {
        padding(insets)
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -insets.top, leading: -insets.leading, bottom: -insets.bottom, trailing: -insets.trailing))
    }

    /// The same, equally on every side.
    func tapArea(_ inset: CGFloat) -> some View {
        tapArea(EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset))
    }
}
