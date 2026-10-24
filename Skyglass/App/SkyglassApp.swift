import SwiftUI

@main
struct SkyglassApp: App {
    @State private var model = SkyModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.rose)
        }
    }
}
