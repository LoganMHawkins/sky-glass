import SwiftUI

@main
struct SkyglassApp: App {
    @State private var model = SkyModel()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-artGallery") {
                    ArtGallery()
                } else {
                    RootView().boringMode().environment(model)
                }
                #else
                RootView().boringMode().environment(model)
                #endif
            }
            .preferredColorScheme(model.appearance.scheme)
            .tint(Theme.rose)
        }
    }
}
