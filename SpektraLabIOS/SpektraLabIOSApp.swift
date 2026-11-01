import SwiftUI

@main
struct SpektraLabIOSApp: App {
    init() {
        // Exercise the linked original C++ spectral primitive at launch.
        // This is not yet a film-render pipeline integration.
        _ = UpstreamCore.verifiedSpectralFunction()
    }
    var body: some Scene {
        WindowGroup {
            EditorView()
        }
    }
}
