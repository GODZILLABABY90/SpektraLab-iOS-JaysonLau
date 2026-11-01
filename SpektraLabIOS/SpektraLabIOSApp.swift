import SwiftUI

@main
struct SpektraLabIOSApp: App {
    init() {
        // Exercise the linked original C++ spectral primitive at launch.
        // This is not yet a film-render pipeline integration.
        let nativeCore = UpstreamCore.verifiedSpectralFunction()
        let assets = OriginalEngineAssets.check()
        NSLog("SpektraLab iOS original core=%@, profiles=%@, Metal=%@",
              nativeCore.description, assets.resources.description, assets.metal.description)
    }
    var body: some Scene {
        WindowGroup {
            EditorView()
        }
    }
}
