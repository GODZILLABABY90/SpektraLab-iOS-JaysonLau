// GPL-3.0-or-later integration glue for upstream SpektraLab C++ core.
// Uses the upstream implementation; this does NOT render full film photographs.
#include "colour.hpp"

extern "C" double spektralab_ios_blackbody_radiance(double wavelength_nm,
                                                       double temperature_kelvin) {
    if (wavelength_nm <= 0.0 || temperature_kelvin <= 0.0) return 0.0;
    return spk::Colour::blackbody_spectral_radiance(wavelength_nm * 1.0e-9,
                                                   temperature_kelvin);
}
