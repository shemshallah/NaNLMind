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
    CHECK(compiled.block_bits == 3);
    CHECK(compiled.states > 500);
    CHECK(compiled.transitions.size() >= 1000u);

    std::map<std::pair<std::uint16_t, std::uint8_t>, BinaryTransition> bt;
    for (const auto& t : compiled.transitions) bt[{t.from, t.read}] = t;

    const std::vector<std::uint8_t> source_tape{
        0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7};
    const auto bits = encode_binary_tape(source_tape, compiled.block_bits);
    std::map<std::int64_t, std::uint8_t> btape;
    for (std::size_t i = 0; i < bits.size(); ++i) btape[static_cast<std::int64_t>(i)] = bits[i];
    std::int64_t bhead = 0;
    std::uint16_t bstate = compiled.initial_state;

    std::map<std::int64_t, std::uint8_t> stable;
    for (std::size_t i = 0; i < source_tape.size(); ++i)
        stable[static_cast<std::int64_t>(i)] = source_tape[i];
    std::int64_t shead = 0;
    std::uint8_t sstate = 6;

    auto source_read = [&](std::int64_t p) {
        const auto it = stable.find(p);
        return it == stable.end() ? 2 : it->second;
    };
    auto binary_read = [&](std::int64_t p) {
        const auto it = btape.find(p);
        return it == btape.end() ? 0 : it->second;
    };
    std::map<std::pair<std::uint8_t, std::uint8_t>, TmTransition> source_table;
    for (const auto& t : source) source_table[{t.from, t.read}] = t;

    for (int step = 0; step < 20; ++step) {
        // One source step.
        const auto it = source_table.find({sstate, source_read(shead)});
        CHECK(it != source_table.end());
        const auto& st = it->second;
        stable[shead] = st.write;
        shead += st.move;
        sstate = st.to;

        // One binary cell cycle: read 3 bits, write 3 bits, move 3 bits.
        for (int micro = 0; micro < 7; ++micro) {
            const auto e = bt.find({bstate, binary_read(bhead)});
            CHECK(e != bt.end());
            btape[bhead] = e->second.write;
            bhead += e->second.move;
            bstate = e->second.to;
        }
        const auto r0 = compiled.r0_state.find(bstate);
        CHECK(r0 != compiled.r0_state.end());
        CHECK_EQ(r0->second, sstate);
        CHECK_EQ(bhead, 3 * shead);
        for (std::size_t i = 0; i < source_tape.size(); ++i) {
            std::uint8_t decoded = 0;
            for (std::uint8_t b = 0; b < 3; ++b) {
                decoded |= static_cast<std::uint8_t>(
                    binary_read(static_cast<std::int64_t>(3 * i + b)) << b);
            }
            CHECK_EQ(decoded, stable[static_cast<std::int64_t>(i)]);
        }
    }

    return test_done("TM-to-binary compiler preserves 20 Minsky source steps");
}
