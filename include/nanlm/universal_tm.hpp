// Universal Turing-machine runtime: the machine description and the simulated
// tape live on chart pages. One fixed step() scans the encoded description.
#pragma once

#include "nanlm/turing_machine.hpp"
#include "nanlm/tm_description.hpp"

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
    bool load_machine_symbols(const std::vector<TmTransition>& transitions,
                              const std::vector<std::uint8_t>& initial_tape,
                              std::int64_t head);
    bool load_description(const TmDescription& description,
                          const std::string& initial_tape, std::int64_t head);
    bool load_description_symbols(const TmDescription& description,
                                  const std::vector<std::uint8_t>& initial_tape,
                                  std::int64_t head);
    void set_state(std::uint8_t state);
    bool load_encoded_description(const std::uint8_t* data, std::size_t len,
                                  const std::string& initial_tape, std::int64_t head);
    bool step();
    std::size_t run(std::size_t max_steps = 1000000);
    bool halted() const;
    std::uint8_t state() const;
    std::int64_t head() const;
    std::uint8_t symbol(std::int64_t position) const {
        return tape_.read(kWorkingTapeBase + position);
    }
    std::string tape(std::int64_t begin, std::int64_t end) const;
    std::size_t tape_pages() const { return tape_.pages(); }
    const TuringTape& tape_store() const { return tape_; }
    TuringTape& tape_store() { return tape_; }
    std::vector<std::uint8_t> serialize_tape() const { return tape_.serialize(); }
    bool restore_tape(const std::uint8_t* data, std::size_t len) { return tape_.restore(data, len); }

private:
    std::uint8_t description_count() const;
    Universe* universe_;
    TuringTape tape_;
};

} // namespace nanlm
