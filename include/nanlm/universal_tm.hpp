// Universal Turing-machine runtime: the machine description and the simulated
// tape live on chart pages. One fixed step() scans the encoded description.
#pragma once

#include "nanlm/turing_machine.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

class UniversalTuringMachine {
public:
    static constexpr std::uint16_t kControlBase = 0x0A00;
    static constexpr std::int64_t kDescriptionBase = 0;
    static constexpr std::int64_t kWorkingTapeBase = 1 << 20;

    explicit UniversalTuringMachine(Universe& universe) : universe_(&universe) {}

    bool load_machine(const std::vector<TmTransition>& transitions,
                      const std::string& initial_tape, std::int64_t head);
    bool step();
    std::size_t run(std::size_t max_steps = 1000000);
    bool halted() const;
    std::uint8_t state() const;
    std::int64_t head() const;
    std::string tape(std::int64_t begin, std::int64_t end) const;
    std::size_t tape_pages() const { return tape_.pages(); }

private:
    std::uint8_t description_count() const;
    Universe* universe_;
    TuringTape tape_;
};

} // namespace nanlm
