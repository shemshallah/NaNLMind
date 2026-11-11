// Native seven-credit ablation harness.
//
// All seven credit calculations and the ablation are executed by the raw
// NaN16 guest through RawFieldVM.  This host program only supplies deterministic
// test observations and prints the guest's Q16.16 outputs as JSON.
#include "nanlm/raw_field.hpp"

#include <array>
#include <cstdint>
#include <iostream>
#include <string>

using namespace nanlm;

int main(int argc, char** argv) {
    const std::string driver = argc > 1 ? argv[1] : "build/field_driver.nan";
    RawFieldVM vm(driver);
    if (!vm.ready()) {
        std::cerr << "raw driver unavailable: " << vm.error() << "\n";
        return 2;
    }

    CreditBundleState state;
    // Deterministic native demonstration observations, not corpus claims.
    state.cft = {12000, 18000, 24000, 3000, 6553};
    state.trail = {7000, 9000, 11000, 13000, 15000, 17000,
                   19000, 21000, 23000, 32768, 32768};
    state.holo = {5000, 15000, 25000};
    state.ring_shift = 37;
    for (std::size_t i = 0; i < state.ring_phases.size(); ++i)
        state.ring_phases[i] = static_cast<std::uint16_t>((i * 997u) & 0xFFFFu);
    state.leaf = {4000, 6000, 8000};
    state.tca = {10000, 8000, 12000};
    state.flux = {3000, 5000, 7000, 9000};

    std::array<std::int32_t, 7> credits{};
    if (!vm.credit_bundle(state, credits)) {
        std::cerr << "credit bundle failed: " << vm.error() << "\n";
        return 3;
    }

    const std::array<std::int32_t, 7> coefficients =
        {65536, 65536, 65536, 65536, 65536, 65536, 65536};
    std::array<std::int32_t, 8> ablation{};
    if (!vm.credit_ablation(state, coefficients, ablation)) {
        std::cerr << "credit ablation failed: " << vm.error() << "\n";
        return 4;
    }

    std::cout << "{\"schema\":\"nanlm.credit-ablation/1\",\"order\":["
                 "\"CFT\",\"TRAIL\",\"HOLO\",\"RING\",\"LEAF\",\"TCA\",\"FLUX\"],"
                 "\"credits_q16\":[";
    for (std::size_t i = 0; i < credits.size(); ++i)
        std::cout << (i ? "," : "") << credits[i];
    std::cout << "],\"combined_q16\":" << ablation[0]
              << ",\"ablation_zero_channel_q16\":[";
    for (std::size_t i = 1; i < ablation.size(); ++i)
        std::cout << (i > 1 ? "," : "") << ablation[i];
    std::cout << "]}\n";
    return 0;
}
