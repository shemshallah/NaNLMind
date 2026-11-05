// Exact Boolean-function spectrum for the 16 head functions.
#pragma once

#include <array>
#include <cstdint>

namespace nanlm {

struct BooleanSpectrum {
    std::uint8_t truth = 0;
    std::array<std::int8_t, 4> anf{};   // 1, a, b, ab coefficients
    std::array<std::int8_t, 4> walsh{}; // integer parities
    std::uint8_t symmetry_class = 0;    // 0 constant, 1 literal, 2 xor, 3 and
    bool non_linear = false;
};

std::uint8_t truth_from_anf(const std::array<std::int8_t, 4>& anf);
BooleanSpectrum analyze_boolean(std::uint8_t truth);
std::uint8_t classify_boolean(std::uint8_t truth);
std::array<std::uint16_t, 4> class_histogram(
    const std::array<std::uint8_t, 256>& rules);

// A 256x256 chart as a matrix. Transpose is an involution; the symmetric and
// antisymmetric parts are the two directed rails in matrix form.
struct Matrix256 {
    std::array<std::int16_t, 65536> values{};

    std::int16_t& at(std::uint8_t a, std::uint8_t b) {
        return values[static_cast<std::size_t>(a) * 256u + b];
    }
    std::int16_t at(std::uint8_t a, std::uint8_t b) const {
        return values[static_cast<std::size_t>(a) * 256u + b];
    }
};

Matrix256 transpose(const Matrix256& m);
Matrix256 symmetric_part(const Matrix256& m);
Matrix256 antisymmetric_part(const Matrix256& m);

} // namespace nanlm
