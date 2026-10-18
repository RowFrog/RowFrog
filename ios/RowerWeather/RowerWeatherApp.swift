import SwiftUI

@main
struct RowerWeatherApp: App {
    var body: some Scene {
        WindowGroup {
            LakeListView(api: APIClient.fromBundle())
        }
    }
}
