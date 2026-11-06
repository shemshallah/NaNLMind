#pragma once

#include "nanlm/turing_machine.hpp"

#include <cstdint>
#include <map>
#include <vector>

namespace nanlm {

struct BinaryTransition {
    std::uint16_t from = 0;
    std::uint8_t read = 0;
    std::uint8_t write = 0;
    std::int8_t move = 1;
    std::uint16_t to = 0;
};

struct BinaryTm {
    std::uint16_t states = 0;
    std::uint8_t block_bits = 0;
    std::uint16_t initial_state = 0;
    std::map<std::uint16_t, std::uint8_t> r0_state;
    std::vector<BinaryTransition> transitions;
};

// Compile a finite source TM into a binary TM using fixed-width symbol blocks.
// The source transition table is assumed deterministic and complete for the
// states/symbols that occur.
BinaryTm compile_tm_to_binary(const std::vector<TmTransition>& source,
                              std::uint8_t source_states,
                              std::uint8_t source_symbols,
                              std::uint8_t initial_state);

std::vector<std::uint8_t> encode_binary_tape(
    const std::vector<std::uint8_t>& source_tape, std::uint8_t block_bits);

} // namespace nanlm
