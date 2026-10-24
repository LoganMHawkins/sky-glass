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
                    RootView().environment(model)
                }
                #else
                RootView().environment(model)
                #endif
            }
            .preferredColorScheme(.dark)
            .tint(Theme.rose)
        }
    }
}
