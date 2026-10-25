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

    /// The picture for a choice, or nil for "no picture" or a missing file.
    /// Thumbnails are scaled down for the picker's grid.
    static func image(for choice: BackgroundChoice, thumbnail: Bool = false) -> UIImage? {
        let url: URL?
        switch choice {
        case .noPicture: return nil
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

    private static func scaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
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
    case plain, frosted, glass, solid
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
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerState.shared.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }
}

extension AppSettings {
    /// The tiles over a picture as drawn: solid in Low Power Mode, since blurred
    /// and Liquid Glass tiles are drawn again on every frame the page scrolls.
    @MainActor var tileSurface: Surface { PowerState.shared.lowPower ? .solid : tileStyle.surface }
}

private struct CurrentPageKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
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

    /// A card's background.
    var card: AnyShapeStyle {
        switch self {
        case .frosted, .glass: AnyShapeStyle(.regularMaterial)
        case .plain, .solid: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
        }
    }

    /// A tile inside a card. Tiles in a glass card stay a light shade, since
    /// glass on glass looks muddy.
    var tile: AnyShapeStyle {
        switch self {
        case .frosted, .glass: AnyShapeStyle(Color(.tertiarySystemGroupedBackground).opacity(0.55))
        case .plain, .solid: AnyShapeStyle(Color(.tertiarySystemGroupedBackground))
        }
    }

    /// For text that sits on the picture itself, like a page's title.
    var label: AnyShapeStyle {
        hasPicture ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear)
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
            shape.fill(.regularMaterial).overlay(shape.fill(tint.opacity(0.22)))
        case .glass:
            Color.clear.glass(tint: tint.opacity(0.3), in: shape)
        }
    }
}

extension View {
    /// A card's background: Liquid Glass when the tiles are set to it, else
    /// the surface's usual card style.
    func cardBackground(_ surface: Surface, cornerRadius: CGFloat = 16) -> some View {
        modifier(CardBackground(surface: surface, cornerRadius: cornerRadius))
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

private struct CardBackground: ViewModifier {
    let surface: Surface
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if surface == .glass {
            content.glass(in: shape)
        } else {
            content.background(surface.card, in: shape)
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

    func body(content: Content) -> some View {
        let settings = AppSettings.shared
        let image = BackgroundLibrary.image(for: settings.background(for: page, clubID: clubID))
        content
            .environment(\.surface, image == nil ? .plain : settings.tileSurface)
            .background {
                if drawsPicture {
                    PagePicture(image: image, blurred: settings.blurBackground)
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

    var body: some View {
        if let image {
            BackgroundPicture(image: image, blurred: blurred)
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
            .accessibilityHidden(true)
    }
}
