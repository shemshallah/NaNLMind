#include "nanlm/boolean_spectrum.hpp"
#include "test_util.hpp"

#include <array>

using namespace nanlm;

int main() {
    for (std::uint8_t truth = 0; truth < 16; ++truth) {
        const BooleanSpectrum s = analyze_boolean(truth);
        CHECK_EQ(truth_from_anf(s.anf), truth);
        CHECK_EQ(s.truth, truth);
        CHECK(s.walsh[0] == 4 - 2 * __builtin_popcount(truth));
    }

    // Symmetry classes are invariant under swap, input negation and output
    // negation. Build the transformed truth table explicitly.
    auto transform_truth = [](std::uint8_t truth, bool swap, bool neg_a,
                              bool neg_b, bool neg_out) {
        std::uint8_t out = 0;
        for (int a = 0; a < 2; ++a) {
            for (int b = 0; b < 2; ++b) {
                const int sa = swap ? b : a;
                const int sb = swap ? a : b;
                const int src = 2 * (sa ^ (neg_a ? 1 : 0)) + (sb ^ (neg_b ? 1 : 0));
                int value = (truth >> src) & 1;
                if (neg_out) value ^= 1;
                out = static_cast<std::uint8_t>(out | (value << (2 * a + b)));
            }
        }
        return out;
    };
    for (std::uint8_t truth = 0; truth < 16; ++truth) {
        const std::uint8_t cls = classify_boolean(truth);
        for (bool swap : {false, true})
            for (bool na : {false, true})
                for (bool nb : {false, true})
                    for (bool no : {false, true})
                        CHECK_EQ(classify_boolean(transform_truth(truth, swap, na, nb, no)), cls);
    }

    // Chart-level class histogram over the 16-function curriculum pattern.
    std::array<std::uint8_t, 256> rules{};
    for (std::uint16_t i = 0; i < 256; ++i) rules[i] = static_cast<std::uint8_t>(i & 15u);
    const auto hist = class_histogram(rules);
    CHECK_EQ(hist[0], 32u); // two constants * 16
    CHECK_EQ(hist[1], 64u); // four literals * 16
    CHECK_EQ(hist[2], 32u); // two xor * 16
    CHECK_EQ(hist[3], 128u); // eight and-family * 16

    // Transpose split: M = (S + A)/2, S symmetric, A antisymmetric.
    Matrix256 m;
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            m.at(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)) =
                static_cast<std::int16_t>((a * 17u + b * 31u) % 97u);
        }
    }
    const Matrix256 t = transpose(m);
    const Matrix256 tt = transpose(t);
    CHECK(tt.values == m.values);
    const Matrix256 s = symmetric_part(m);
    const Matrix256 as = antisymmetric_part(m);
    CHECK(s.values == transpose(s).values);
    for (std::size_t i = 0; i < m.values.size(); ++i) {
        CHECK_EQ(static_cast<int>(s.values[i]) + static_cast<int>(as.values[i]),
                 static_cast<int>(2 * m.values[i]));
    }
    return test_done("Boolean ANF/Walsh/symmetry and transpose split");
}
