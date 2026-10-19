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
    case plain, frosted, solid
}

private struct SurfaceKey: EnvironmentKey {
    static let defaultValue = Surface.plain
}

extension EnvironmentValues {
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
        case .frosted: AnyShapeStyle(.regularMaterial)
        case .plain, .solid: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
        }
    }

    /// A tile inside a card.
    var tile: AnyShapeStyle {
        switch self {
        case .frosted: AnyShapeStyle(Color(.tertiarySystemGroupedBackground).opacity(0.55))
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
        }
    }
}

/// Puts the page's background picture, or the plain grouped background, behind
/// the content, and tells the cards how to draw themselves over it.
struct PageBackground: ViewModifier {
    let page: PageKind
    var clubID: String? = nil

    func body(content: Content) -> some View {
        let settings = AppSettings.shared
        let image = BackgroundLibrary.image(for: settings.background(for: page, clubID: clubID))
        content
            .environment(\.surface, image == nil ? .plain : (settings.tileStyle == .frosted ? .frosted : .solid))
            .background {
                if let image {
                    BackgroundPicture(image: image, blurred: settings.blurBackground)
                } else {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
            }
    }
}

extension View {
    func pageBackground(_ page: PageKind, clubID: String? = nil) -> some View {
        modifier(PageBackground(page: page, clubID: clubID))
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: blurred ? 24 : 0, opaque: true)
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
