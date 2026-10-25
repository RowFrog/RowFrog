import SwiftUI

@main
struct RowFrogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Tutorial.configureTips()
    }

    var body: some Scene {
        WindowGroup {
            if UserDefaults.standard.bool(forKey: "RWIconGallery") {
                IconGalleryView()
            } else if UserDefaults.standard.bool(forKey: "RWConditionsPreview") {
                ConditionsPreviewView()
            } else if UserDefaults.standard.bool(forKey: "RWWidgetGallery") {
                WidgetGalleryView(api: APIClient.fromBundle())
            } else {
                RootView(api: APIClient.fromBundle())
            }
        }
    }
}

/// Lets the app turn sideways only while landscape is on in the settings.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.allowed
    }
}

enum Orientation {
    static var allowed: UIInterfaceOrientationMask {
        AppSettings.shared.allowsLandscape ? .allButUpsideDown : .portrait
    }

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
