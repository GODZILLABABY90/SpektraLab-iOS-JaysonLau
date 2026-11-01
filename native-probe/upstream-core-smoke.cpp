// Minimal iPhoneOS link-time smoke check against the original upstream spectral setup code.
// This calls real upstream functions; it is not an alternate film renderer.
#include "numeric.hpp"
#include "colour.hpp"
#include <cmath>

extern "C" double spk_ios_upstream_core_smoke(void) {
    static_assert(spk::kNumWavelengths == 81, "Upstream spectral sampling changed");
    const double wavelengths[] = {380.0, 580.0, 780.0};
    const double values[] = {0.1, 0.5, 0.9};
    const double midpoint = spk::interp(480.0, wavelengths, values, 3);
    const double radiant = spk::Colour::blackbody_spectral_radiance(550e-9, 5500.0);
    return (std::isfinite(radiant) && radiant > 0) ? midpoint : -1.0;
}
