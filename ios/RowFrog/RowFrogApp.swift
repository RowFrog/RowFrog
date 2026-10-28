import SwiftUI

@main
struct RowFrogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        DiagnosisLog.start()
        Tutorial.configureTips()
    }

    var body: some Scene {
        WindowGroup {
            if UserDefaults.standard.bool(forKey: "RWIconGallery") {
                IconGalleryView()
            } else if UserDefaults.standard.bool(forKey: "RWConditionsPreview") {
                ConditionsPreviewView()
            } else if UserDefaults.standard.bool(forKey: "RWHeadlinePreview") {
                HeadlinePreviewView()
            } else if UserDefaults.standard.bool(forKey: "RWWidgetGallery") {
                WidgetGalleryView(api: APIClient.fromBundle())
            } else {
                RootView(api: APIClient.fromBundle())
            }
        }
    }
}

/// Lets the app turn sideways only while landscape is on in the settings (iPhone only).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.allowed
    }
}

enum Orientation {
    static var allowed: UIInterfaceOrientationMask {
        if isPad { return .all }
        return AppSettings.shared.allowsLandscape ? .allButUpsideDown : .portrait
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
