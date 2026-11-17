import SwiftUI

@main
struct RowFrogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Test hook: `-RWFreshStart YES` forgets everything saved, as after a new
        // install (the tap test of the first start). Launch arguments still apply.
        if UserDefaults.standard.bool(forKey: DefaultsKey.freshStart), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        DiagnosisLog.start()
        // The widgets now keep their forecasts as files (WidgetForecasts).
        WidgetForecasts.dropOldCopies()
        Tutorial.configureTips()
    }

    var body: some Scene {
        WindowGroup {
            if UserDefaults.standard.bool(forKey: DefaultsKey.iconGallery) {
                IconGalleryView()
            } else if UserDefaults.standard.bool(forKey: DefaultsKey.conditionsPreview) {
                ConditionsPreviewView()
            } else if UserDefaults.standard.bool(forKey: DefaultsKey.widgetGallery) {
                WidgetGalleryView(api: APIClient.fromBundle())
            } else {
                RootView(api: APIClient.fromBundle())
            }
        }
    }
}

/// Lets the app turn sideways only while landscape is on in the settings (iPhone only),
/// and names the scene delegate for the Home Screen menu.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.allowed
    }

    /// The Home Screen menu's taps come through the scene delegate (QuickActions).
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

enum Orientation {
    static var allowed: UIInterfaceOrientationMask {
        if isPad { return .all }
        return AppSettings.shared.activeAllowsLandscape ? .allButUpsideDown : .portrait
    }

    /// On the iPad the app runs in a resizable window, where iPadOS ignores an
    /// orientation lock, so the Landscape setting is hidden there.
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Applies a change of the setting at once; turning landscape off brings the app upright.
    static func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: allowed))
        }
    }
}
