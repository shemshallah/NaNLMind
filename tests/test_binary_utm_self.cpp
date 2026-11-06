#include "nanlm/binary_utm.hpp"
#include "nanlm/binary_tm_compiler.hpp"
#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <map>
#include <string>
#include <utility>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> minsky_table() {
    return {
#include "minsky_table.inc"
    };
}
std::uint8_t sym(char c) {
    switch (c) {
        case '0': return 0; case '1': return 1; case 'A': return 2;
        case 'B': return 3; case 'X': return 4; case 'Y': return 5;
        case 'M': return 6; case 'S': return 7; default: return 2;
    }
}
std::vector<std::uint8_t> symbols(const std::string& s) {
    std::vector<std::uint8_t> out;
    for (char c : s) out.push_back(sym(c));
    return out;
}
} // namespace

int main() {
    const std::string initial =
        "001111YBAAXAAAAAAAXAABAAAASM000000Y001X0000001X0010110X0100011X0110100Y00";
    const auto source_symbols = symbols(initial);

    Universe u(0x53454C42);
    TuringMachine source(u);
    CHECK(source.load(minsky_table()));
    source.set_tape_symbols(source_symbols, 38);
    source.set_state(5);

    const BinaryTm compiled = compile_tm_to_binary(minsky_table(), 23, 8, 5);
    const auto bits = encode_binary_tape(source_symbols, compiled.block_bits);
    BinaryUniversalMachine binary;
    binary.load(compiled, bits, 3 * 38, compiled.initial_state);

    for (int step = 0; step < 100; ++step) {
        const bool alive = source.step();
        CHECK_EQ(binary.run(7), 7u);
        const auto r0 = compiled.r0_state.find(binary.state());
        CHECK(r0 != compiled.r0_state.end());
        if (r0 == compiled.r0_state.end()) break;
        CHECK_EQ(r0->second, source.state());
        CHECK_EQ(binary.head(), 3 * source.head());
        for (std::int64_t i = 0; i < static_cast<std::int64_t>(initial.size()); ++i) {
            std::uint8_t decoded = 0;
            for (std::uint8_t b = 0; b < 3; ++b) {
                decoded |= static_cast<std::uint8_t>(binary.symbol(3 * i + b) << b);
            }
            CHECK_EQ(decoded, source.symbol(i));
        }
        if (!alive) break;
    }

    return test_done("compiled binary Minsky table tracks the source Minsky trace");
}
