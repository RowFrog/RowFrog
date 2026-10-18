import SwiftUI

@main
struct RowerWeatherApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(api: APIClient.fromBundle())
        }
    }
}
