import Foundation
import Metal

// Validates packaged ORIGINAL engine resources and the iPhone GPU kernel library.
// Full photographic rendering still requires the upstream pipeline/session C ABI.
enum OriginalEngineAssets {
    static func check() -> (resources: Bool, metal: Bool) {
        let resourceDir = "OriginalEngineResources"
        let constants = Bundle.main.url(forResource: "spektrafilm_constants",
                                        withExtension: "bin", subdirectory: resourceDir)
        let metalURL = Bundle.main.url(forResource: "spektrafilm",
                                       withExtension: "metallib", subdirectory: resourceDir)
        let resourcesReady = constants.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        guard let device = MTLCreateSystemDefaultDevice(), let metalURL else {
            return (resourcesReady, false)
        }
        do {
            let library = try device.makeLibrary(URL: metalURL)
            return (resourcesReady, !library.functionNames.isEmpty)
        } catch {
            NSLog("Original SpektraLab iOS metallib load failed: %@", String(describing: error))
            return (resourcesReady, false)
        }
    }
}
