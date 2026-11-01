// Portable C ABI connecting iOS Swift to original SpektraLab core functions.
// Source implementation: JamesQiu2005/SpektraLab, GPL-3.0-or-later.
// This symbol verifies linking against the upstream C++ static library.
// It is NOT the full film rendering entry point.
#include "colour.hpp"
#include <cmath>

extern "C" double spk_ios_blackbody_sample(double wavelength_nm, double temperature_kelvin) {
    if (!std::isfinite(wavelength_nm) || !std::isfinite(temperature_kelvin) ||
        wavelength_nm < 380.0 || wavelength_nm > 780.0 ||
        temperature_kelvin < 1000.0) {
        return 0.0;
    }
    return spk::Colour::blackbody_spectral_radiance(wavelength_nm * 1.0e-9,
                                                     temperature_kelvin);
}
