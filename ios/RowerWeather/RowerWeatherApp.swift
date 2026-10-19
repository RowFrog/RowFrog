import SwiftUI

@main
struct RowerWeatherApp: App {
    var body: some Scene {
        WindowGroup {
            if UserDefaults.standard.bool(forKey: "RWIconGallery") {
                IconGalleryView()
            } else if UserDefaults.standard.bool(forKey: "RWWidgetGallery") {
                WidgetGalleryView(api: APIClient.fromBundle())
            } else {
                RootView(api: APIClient.fromBundle())
            }
        }
    }
}
