#include "nanlm/binary_utm.hpp"
#include "nanlm/binary_tm_compiler.hpp"
#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <map>
#include <utility>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> minsky_table() {
    return {
#include "minsky_table.inc"
    };
}
} // namespace

int main() {
    const auto source = minsky_table();
    const BinaryTm compiled = compile_tm_to_binary(source, 23, 8, 6);
    BinaryUniversalMachine machine;

    const std::vector<std::uint8_t> source_tape{
        0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7};
    const auto bits = encode_binary_tape(source_tape, compiled.block_bits);
    machine.load(compiled, bits, 0, compiled.initial_state);

    std::map<std::int64_t, std::uint8_t> stable;
    for (std::size_t i = 0; i < source_tape.size(); ++i)
        stable[static_cast<std::int64_t>(i)] = source_tape[i];
    std::int64_t shead = 0;
    std::uint8_t sstate = 6;
    std::map<std::pair<std::uint8_t, std::uint8_t>, TmTransition> table;
    for (const auto& t : source) table[{t.from, t.read}] = t;

    for (int step = 0; step < 20; ++step) {
        const auto it = table.find({sstate, stable[shead]});
        CHECK(it != table.end());
        stable[shead] = it->second.write;
        shead += it->second.move;
        sstate = it->second.to;

        CHECK_EQ(machine.run(7), 7u);
        const auto r0 = compiled.r0_state.find(machine.state());
        CHECK(r0 != compiled.r0_state.end());
        if (r0 != compiled.r0_state.end()) CHECK_EQ(r0->second, sstate);
        CHECK_EQ(machine.head(), 3 * shead);
        for (std::size_t i = 0; i < source_tape.size(); ++i) {
            std::uint8_t decoded = 0;
            for (std::uint8_t b = 0; b < 3; ++b) {
                decoded |= static_cast<std::uint8_t>(
                    machine.symbol(static_cast<std::int64_t>(3 * i + b)) << b);
            }
            CHECK_EQ(decoded, stable[static_cast<std::int64_t>(i)]);
        }
    }

    return test_done("compact binary runtime preserves 20 Minsky source steps");
}
