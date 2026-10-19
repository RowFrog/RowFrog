import SwiftUI
import UIKit

/// An app icon the user can pick in the settings. The numbers match the
/// icon comparison sheet the owner chose from.
struct AppIconOption: Identifiable, Hashable {
    let number: Int
    /// Asset suffix: the icon set is `AppIcon-<name>`, the picker preview `IconPreview-<name>`.
    let name: String
    let englishTitle: String

    var id: String { name }
    var title: String { tr(englishTitle) }
    /// `nil` for the primary icon, as `UIApplication.setAlternateIconName` expects.
    var alternateIconName: String? { self == AppIcons.primary ? nil : "AppIcon-\(name)" }
    var previewImage: Image { Image("IconPreview-\(name)") }
}

enum AppIcons {
    static let all: [AppIconOption] = [
        AppIconOption(number: 1, name: "SunriseSculler", englishTitle: "Sunrise sculler"),
        AppIconOption(number: 2, name: "CloudCrossedOars", englishTitle: "Cloud and crossed oars"),
        AppIconOption(number: 3, name: "AlpineLake", englishTitle: "Alpine lake"),
        AppIconOption(number: 4, name: "BladeAndWind", englishTitle: "Blade and wind"),
        AppIconOption(number: 5, name: "RowingLightGauge", englishTitle: "Rowing-light gauge"),
        AppIconOption(number: 6, name: "AvatarFrog", englishTitle: "Frog in the cloud shell"),
        AppIconOption(number: 7, name: "BladeTrafficLight", englishTitle: "Blade rowing light"),
        AppIconOption(number: 8, name: "ShellTrafficLight", englishTitle: "Single from above"),
        AppIconOption(number: 9, name: "CoxedDouble", englishTitle: "Coxed double"),
        AppIconOption(number: 10, name: "CoxedPair", englishTitle: "Coxed pair"),
        AppIconOption(number: 11, name: "FrogGauge", englishTitle: "Frog and rowing light"),
    ]

    /// The icon the app ships with (set `AppIcon` in the asset catalog).
    static let primary = all.first { $0.name == "CoxedDouble" }!

    /// The icon shown on the home screen now.
    @MainActor static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return primary }
        return all.first { $0.alternateIconName == name } ?? primary
    }

    /// Switches the home-screen icon. iOS confirms the change with its own alert.
    @MainActor static func select(_ option: AppIconOption) async throws {
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != option.alternateIconName else { return }
        try await UIApplication.shared.setAlternateIconName(option.alternateIconName)
    }
}
