#include "test_util.hpp"

#include <array>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>

namespace {
constexpr int kBits = 6;
struct Sample { std::uint32_t mask; bool label; };

bool term_true(std::uint32_t mask, const std::array<std::uint8_t, kBits>& term) {
    for (int i = 0; i < kBits; ++i) {
        const std::uint8_t literal = term[i];
        if (literal == 1 && ((mask >> i) & 1u) == 0) return false;
        if (literal == 2 && ((mask >> i) & 1u) != 0) return false;
    }
    return true;
}

std::vector<std::array<std::uint8_t, kBits>> terms_up_to(int degree) {
    std::vector<std::array<std::uint8_t, kBits>> out;
    std::uint32_t total = 1;
    for (int i = 0; i < kBits; ++i) total *= 3;
    for (std::uint32_t code = 0; code < total; ++code) {
        std::array<std::uint8_t, kBits> term{};
        std::uint32_t x = code;
        int d = 0;
        for (int i = 0; i < kBits; ++i) { term[i] = static_cast<std::uint8_t>(x % 3); x /= 3; if (term[i]) ++d; }
        if (d == 0 || d > degree) continue;
        out.push_back(term);
    }
    return out;
}

std::uint32_t lcg(std::uint32_t& s) {
    s = s * 1664525u + 1013904223u;
    return s;
}

} // namespace

int main() {
    constexpr std::uint32_t kSamples = 20000;
    constexpr std::uint32_t kTrain = 16000;
    std::vector<Sample> samples;
    samples.reserve(kSamples);
    for (int depth = 1; depth <= 3; ++depth) {
        std::uint32_t state = 0x12345678u;
        samples.clear();
        for (std::uint32_t i = 0; i < kSamples; ++i) {
            const std::uint32_t mask = lcg(state) & ((1u << kBits) - 1u);
            const bool bird = (mask & 1u) != 0;
            bool exception = false;
            for (int e = 1; e <= depth; ++e) exception |= ((mask >> e) & 1u) != 0;
            samples.push_back({mask, bird && !exception});
        }
        std::cout << "sparse-degree depth=" << depth << " acc=";
        for (int D = 1; D <= 4; ++D) {
            const auto terms = terms_up_to(D);
            std::size_t best_tp = 0, best_fp = 0, best_fn = 0;
            std::array<std::uint8_t, kBits> best{};
            double best_f1 = -1.0;
            for (const auto& term : terms) {
                std::size_t tp = 0, fp = 0, fn = 0;
                for (std::uint32_t i = 0; i < kTrain; ++i) {
                    if (!term_true(samples[i].mask, term)) continue;
                    if (samples[i].label) ++tp; else ++fp;
                }
                const std::size_t pos = [&] {
                    std::size_t n = 0;
                    for (std::uint32_t i = 0; i < kTrain; ++i) if (samples[i].label) ++n;
                    return n;
                }();
                fn = pos - tp;
                const double f1 = (2.0 * tp) / (2.0 * tp + fp + fn + 1e-9);
                if (f1 > best_f1 || (f1 == best_f1 && tp > best_tp)) {
                    best_f1 = f1;
                    best_tp = tp;
                    best_fp = fp;
                    best_fn = fn;
                    best = term;
                }
            }
            std::size_t correct = 0;
            for (std::uint32_t i = kTrain; i < kSamples; ++i) {
                if (term_true(samples[i].mask, best) == samples[i].label) ++correct;
            }
            const double acc = static_cast<double>(correct) / (kSamples - kTrain);
            std::cout << acc << (D < 4 ? "," : "");
            if (D == depth + 1) CHECK(acc >= 0.99);
            if (D < depth + 1) CHECK(acc < 0.99);
            (void)best_fp;
            (void)best_fn;
        }
        std::cout << " terms=" << terms_up_to(4).size() << "\n";
    }
    return test_done("sparse degree-term learner on 20k samples");
}
