#include "nanlm/transform_chain.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>

using namespace nanlm;

int main() {
    const std::array<NanType, 4> types{
        NanType::QuietPositive, NanType::SignalPositive,
        NanType::QuietNegative, NanType::SignalNegative};
    std::uint32_t phases = 0;
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto address = static_cast<std::uint16_t>(i);
        for (NanType type : types) {
            const std::uint16_t f = TransformChain::forward(address, type);
            const std::uint16_t b = TransformChain::inverse(f, type);
            CHECK_EQ(b, address);
            ++phases;
        }
    }
    CHECK_EQ(phases, 65536u * 4u);
    CHECK_EQ(TransformChain::phase_for(NanType::QuietPositive), 0u);
    CHECK_EQ(TransformChain::phase_for(NanType::SignalPositive), 1u);
    CHECK_EQ(TransformChain::phase_for(NanType::QuietNegative), 2u);
    CHECK_EQ(TransformChain::phase_for(NanType::SignalNegative), 3u);
    return test_done("four-NaN transform chain");
}
