// Calls the upstream GPL-licensed C++ core through an unmangled C ABI.
// The V0.2 renderer is not switched to the original spectral pipeline yet.
@_silgen_name("spektralab_ios_blackbody_radiance")
private func spk_ios_blackbody_sample(_ wavelengthNanometers: Double, _ temperatureKelvin: Double) -> Double

enum UpstreamCore {
    static func verifiedSpectralFunction() -> Bool {
        let radiance = spk_ios_blackbody_sample(550.0, 6500.0)
        return radiance.isFinite && radiance > 0
    }
}
