import SwiftUI
import UIKit

// The full-screen background picture and where a picture lies when it fills an
// area; split out of Backgrounds.swift (21 Nov 2026).

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
                let shown = blurred ? BackgroundLibrary.blurred(image) : image
                if let focus = BackgroundLibrary.focus(of: image) {
                    GeometryReader { geometry in
                        let place = PicturePlace.rect(for: image.size, filling: geometry.size, focus: focus)
                        Image(uiImage: shown)
                            .resizable()
                            .frame(width: place.width, height: place.height)
                            .offset(x: place.minX, y: place.minY)
                            .accessibilityHidden(true)
                    }
                } else {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
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
    /// As `BackgroundLibrary.focus(of:)` for the clear picture.
    var focus: UnitPoint? = nil

    static func == (a: FrostPicture, b: FrostPicture) -> Bool { a.image === b.image && a.frame == b.frame && a.focus == b.focus }
}

/// Where a picture lies when it fills an area: scaled to cover it, with its
/// focus point as near the area's middle as the picture's edges allow
/// (centred without a focus, as scaledToFill).
enum PicturePlace {
    static func rect(for picture: CGSize, filling area: CGSize, focus: UnitPoint?) -> CGRect {
        guard picture.width > 0, picture.height > 0 else { return CGRect(origin: .zero, size: area) }
        let scale = max(area.width / picture.width, area.height / picture.height)
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)
        let focus = focus ?? .center
        let x = min(0, max(area.width - size.width, area.width / 2 - focus.x * size.width))
        let y = min(0, max(area.height - size.height, area.height / 2 - focus.y * size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
