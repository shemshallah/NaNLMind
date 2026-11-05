#include "nanlm/boolean_spectrum.hpp"

namespace nanlm {
namespace {
bool bit(std::uint8_t truth, int index) {
    return ((truth >> index) & 1u) != 0;
}
int parity(int p, int a, int b) {
    return ((p & 1) ? a : 0) ^ ((p & 2) ? b : 0);
}
} // namespace

std::uint8_t truth_from_anf(const std::array<std::int8_t, 4>& anf) {
    const int f00 = anf[0] & 1;
    const int f10 = (anf[0] ^ anf[1]) & 1;
    const int f01 = (anf[0] ^ anf[2]) & 1;
    const int f11 = (anf[0] ^ anf[1] ^ anf[2] ^ anf[3]) & 1;
    return static_cast<std::uint8_t>(f00 | (f01 << 1) | (f10 << 2) | (f11 << 3));
}

BooleanSpectrum analyze_boolean(std::uint8_t truth) {
    BooleanSpectrum s;
    s.truth = truth;
    const int f00 = bit(truth, 0);
    const int f01 = bit(truth, 1);
    const int f10 = bit(truth, 2);
    const int f11 = bit(truth, 3);
    s.anf = {static_cast<std::int8_t>(f00),
             static_cast<std::int8_t>(f00 ^ f10),
             static_cast<std::int8_t>(f00 ^ f01),
             static_cast<std::int8_t>(f00 ^ f10 ^ f01 ^ f11)};
    for (int p = 0; p < 4; ++p) {
        int sum = 0;
        for (int index = 0; index < 4; ++index) {
            const int a = (index >> 1) & 1;
            const int b = index & 1;
            const int sign = (bit(truth, index) ? -1 : 1) *
                             (parity(p, a, b) ? -1 : 1);
            sum += sign;
        }
        s.walsh[p] = static_cast<std::int8_t>(sum);
    }
    s.symmetry_class = classify_boolean(truth);
    s.non_linear = s.anf[3] != 0;
    return s;
}

std::uint8_t classify_boolean(std::uint8_t truth) {
    if (truth == 0x0 || truth == 0xF) return 0;       // constant
    if (truth == 0x3 || truth == 0x5 ||
        truth == 0xA || truth == 0xC) return 1;       // literal
    if (truth == 0x6 || truth == 0x9) return 2;       // xor/xnor
    return 3;                                        // and/or family
}

std::array<std::uint16_t, 4> class_histogram(
    const std::array<std::uint8_t, 256>& rules) {
    std::array<std::uint16_t, 4> out{};
    for (std::uint8_t rule : rules) ++out[classify_boolean(rule & 15u)];
    return out;
}

Matrix256 transpose(const Matrix256& m) {
    Matrix256 out;
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            out.at(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)) =
                m.at(static_cast<std::uint8_t>(b), static_cast<std::uint8_t>(a));
        }
    }
    return out;
}

Matrix256 symmetric_part(const Matrix256& m) {
    Matrix256 out;
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            out.at(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)) =
                static_cast<std::int16_t>(m.at(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)) +
                                         m.at(static_cast<std::uint8_t>(b), static_cast<std::uint8_t>(a)));
        }
    }
    return out;
}

Matrix256 antisymmetric_part(const Matrix256& m) {
    Matrix256 out;
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            out.at(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)) =
                static_cast<std::int16_t>(m.at(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)) -
                                         m.at(static_cast<std::uint8_t>(b), static_cast<std::uint8_t>(a)));
        }
    }
    return out;
}

} // namespace nanlm
