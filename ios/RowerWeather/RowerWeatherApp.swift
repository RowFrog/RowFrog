import SwiftUI

@main
struct RowerWeatherApp: App {
    var body: some Scene {
        WindowGroup {
            if UserDefaults.standard.bool(forKey: "RWIconGallery") {
                IconGalleryView()
            } else {
                RootView(api: APIClient.fromBundle())
            }
        }
    }
}
