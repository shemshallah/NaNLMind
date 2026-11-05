// 2CM whose counters are multi-limb stores (chart or atlas).
#pragma once

#include "nanlm/limb_counter.hpp"
#include "nanlm/two_counter.hpp"

#include <cstdint>
#include <vector>

namespace nanlm {

class TwoCounterMachineLimb {
public:
    TwoCounterMachineLimb(Universe& universe, LimbStore& c0, LimbStore& c1,
                          std::uint16_t state_base = 0x0200,
                          std::uint16_t program_base = 0x0400);

    void load_program(const std::vector<TwoCounterInstruction>& program);
    void reset();
    bool step();
    std::size_t run(std::size_t max_steps = 1000000);
    bool halted() const;
    std::uint64_t counter(std::uint8_t which) const;
    std::uint32_t ip() const;
    std::size_t limbs(std::uint8_t which) const;

private:
    Universe* universe_;
    LimbCounter c0_;
    LimbCounter c1_;
    std::uint16_t state_base_;
    std::uint16_t program_base_;
    std::size_t program_size_ = 0;
};

} // namespace nanlm
