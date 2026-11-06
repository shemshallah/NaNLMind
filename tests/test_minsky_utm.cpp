#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> minsky_table() {
    return {
    { 0, 0, 2, -1, 2, false },
    { 0, 1, 3, 1, 3, false },
    { 0, 2, 2, 1, 0, false },
    { 0, 3, 3, 1, 0, false },
    { 0, 4, 4, 1, 0, false },
    { 0, 5, 5, 1, 0, false },
    { 0, 6, 6, 1, 0, false },
    { 0, 7, 7, 1, 0, false },
    { 1, 0, 0, 1, 1, false },
    { 1, 1, 1, 1, 1, false },
    { 1, 2, 0, 1, 0, false },
    { 1, 3, 1, 1, 4, false },
    { 1, 4, 4, 1, 6, false },
    { 1, 5, 5, 1, 1, false },
    { 1, 6, 6, 1, 1, false },
    { 1, 7, 7, 1, 1, false },
    { 2, 0, 0, -1, 2, false },
    { 2, 1, 1, -1, 2, false },
    { 2, 2, 2, -1, 2, false },
    { 2, 3, 3, -1, 2, false },
    { 2, 4, 4, -1, 2, false },
    { 2, 5, 5, 1, 1, false },
    { 2, 6, 6, -1, 2, false },
    { 2, 7, 7, -1, 2, false },
    { 3, 0, 0, 1, 3, false },
    { 3, 1, 1, 1, 3, false },
    { 3, 2, 2, 1, 3, false },
    { 3, 3, 3, 1, 3, false },
    { 3, 4, 4, -1, 5, false },
    { 3, 5, 5, 0, 0, true },
    { 3, 6, 6, 1, 3, false },
    { 3, 7, 7, 1, 3, false },
    { 4, 0, 2, 1, 3, false },
    { 4, 1, 3, -1, 2, false },
    { 4, 2, 2, 1, 4, false },
    { 4, 3, 3, 1, 4, false },
    { 4, 4, 4, 1, 4, false },
    { 4, 5, 5, 1, 4, false },
    { 4, 6, 6, 1, 4, false },
    { 4, 7, 7, 1, 4, false },
    { 5, 0, 2, -1, 5, false },
    { 5, 1, 3, -1, 5, false },
    { 5, 2, 2, -1, 5, false },
    { 5, 3, 3, -1, 5, false },
    { 5, 4, 4, -1, 5, false },
    { 5, 5, 5, 1, 1, false },
    { 5, 6, 6, -1, 5, false },
    { 5, 7, 7, -1, 5, false },
    { 6, 0, 2, -1, 8, false },
    { 6, 1, 3, -1, 7, false },
    { 6, 2, 2, 1, 6, false },
    { 6, 3, 3, 1, 6, false },
    { 6, 4, 4, 1, 6, false },
    { 6, 5, 5, 1, 6, false },
    { 6, 6, 6, 1, 6, false },
    { 6, 7, 7, 1, 6, false },
    { 7, 0, 0, -1, 7, false },
    { 7, 1, 1, -1, 7, false },
    { 7, 2, 2, -1, 7, false },
    { 7, 3, 3, -1, 7, false },
    { 7, 4, 4, -1, 7, false },
    { 7, 5, 5, 1, 9, false },
    { 7, 6, 6, -1, 7, false },
    { 7, 7, 7, -1, 7, false },
    { 8, 0, 0, -1, 8, false },
    { 8, 1, 1, -1, 8, false },
    { 8, 2, 2, -1, 8, false },
    { 8, 3, 3, -1, 8, false },
    { 8, 4, 4, -1, 8, false },
    { 8, 5, 5, 1, 10, false },
    { 8, 6, 6, -1, 8, false },
    { 8, 7, 7, -1, 8, false },
    { 9, 0, 3, 1, 11, false },
    { 9, 1, 3, 1, 11, false },
    { 9, 2, 2, 1, 9, false },
    { 9, 3, 3, 1, 9, false },
    { 9, 4, 4, -1, 12, false },
    { 9, 5, 5, 1, 9, false },
    { 9, 6, 6, 1, 9, false },
    { 9, 7, 7, 1, 9, false },
    { 10, 0, 2, 1, 11, false },
    { 10, 1, 2, 1, 11, false },
    { 10, 2, 2, 1, 10, false },
    { 10, 3, 3, 1, 10, false },
    { 10, 4, 4, -1, 13, false },
    { 10, 5, 5, 1, 10, false },
    { 10, 6, 6, 1, 10, false },
    { 10, 7, 7, 1, 10, false },
    { 11, 0, 0, 1, 11, false },
    { 11, 1, 1, 1, 11, false },
    { 11, 2, 2, 1, 11, false },
    { 11, 3, 3, 1, 11, false },
    { 11, 4, 4, 1, 6, false },
    { 11, 5, 5, 1, 11, false },
    { 11, 6, 6, 1, 11, false },
    { 11, 7, 7, 1, 11, false },
    { 12, 0, 0, -1, 12, false },
    { 12, 1, 1, -1, 12, false },
    { 12, 2, 2, -1, 12, false },
    { 12, 3, 3, -1, 12, false },
    { 12, 4, 4, -1, 12, false },
    { 12, 5, 5, -1, 12, false },
    { 12, 6, 3, 1, 14, false },
    { 12, 7, 7, -1, 12, false },
    { 13, 0, 0, -1, 13, false },
    { 13, 1, 1, -1, 13, false },
    { 13, 2, 2, -1, 13, false },
    { 13, 3, 3, -1, 13, false },
    { 13, 4, 4, -1, 13, false },
    { 13, 5, 5, -1, 13, false },
    { 13, 6, 2, 1, 14, false },
    { 13, 7, 7, -1, 13, false },
    { 14, 0, 0, 1, 14, false },
    { 14, 1, 1, 1, 14, false },
    { 14, 2, 0, 1, 14, false },
    { 14, 3, 1, 1, 14, false },
    { 14, 4, 4, 1, 15, false },
    { 14, 5, 5, 1, 14, false },
    { 14, 6, 6, 1, 14, false },
    { 14, 7, 7, 1, 14, false },
    { 15, 0, 0, -1, 16, false },
    { 15, 1, 1, -1, 16, false },
    { 15, 2, 2, 1, 15, false },
    { 15, 3, 3, 1, 15, false },
    { 15, 4, 4, 1, 15, false },
    { 15, 5, 5, 1, 15, false },
    { 15, 6, 6, 1, 15, false },
    { 15, 7, 7, 1, 15, false },
    { 16, 0, 7, -1, 21, false },
    { 16, 1, 7, -1, 22, false },
    { 16, 2, 0, -1, 16, false },
    { 16, 3, 1, -1, 16, false },
    { 16, 4, 4, -1, 16, false },
    { 16, 5, 5, -1, 16, false },
    { 16, 6, 6, -1, 16, false },
    { 16, 7, 7, -1, 16, false },
    { 17, 0, 0, 1, 17, false },
    { 17, 1, 1, 1, 17, false },
    { 17, 2, 2, 1, 17, false },
    { 17, 3, 3, 1, 17, false },
    { 17, 4, 4, 1, 17, false },
    { 17, 5, 5, 1, 17, false },
    { 17, 6, 6, 1, 17, false },
    { 17, 7, 2, -1, 5, false },
    { 18, 0, 0, 1, 18, false },
    { 18, 1, 1, 1, 18, false },
    { 18, 2, 2, 1, 18, false },
    { 18, 3, 3, 1, 18, false },
    { 18, 4, 4, 1, 18, false },
    { 18, 5, 5, 1, 18, false },
    { 18, 6, 6, 1, 18, false },
    { 18, 7, 3, -1, 5, false },
    { 19, 0, 6, 1, 17, false },
    { 19, 1, 6, 1, 18, false },
    { 19, 2, 2, 1, 19, false },
    { 19, 3, 3, 1, 19, false },
    { 19, 4, 4, 1, 19, false },
    { 19, 5, 5, 1, 19, false },
    { 19, 6, 6, 1, 19, false },
    { 19, 7, 7, 1, 19, false },
    { 20, 0, 6, 1, 17, false },
    { 20, 1, 6, 1, 18, false },
    { 20, 2, 2, -1, 20, false },
    { 20, 3, 3, -1, 20, false },
    { 20, 4, 4, -1, 20, false },
    { 20, 5, 5, -1, 20, false },
    { 20, 6, 6, -1, 20, false },
    { 20, 7, 7, -1, 20, false },
    { 21, 0, 0, -1, 21, false },
    { 21, 1, 1, -1, 21, false },
    { 21, 2, 0, -1, 20, false },
    { 21, 3, 0, 1, 19, false },
    { 21, 4, 4, -1, 21, false },
    { 21, 5, 5, -1, 21, false },
    { 21, 6, 6, -1, 21, false },
    { 21, 7, 7, -1, 21, false },
    { 22, 0, 0, -1, 22, false },
    { 22, 1, 1, -1, 22, false },
    { 22, 2, 1, -1, 20, false },
    { 22, 3, 1, 1, 19, false },
    { 22, 4, 4, -1, 22, false },
    { 22, 5, 5, -1, 22, false },
    { 22, 6, 6, -1, 22, false },
    { 22, 7, 7, -1, 22, false },
    };
}

std::uint8_t sym(char c) {
    switch (c) {
        case '0': return 0;
        case '1': return 1;
        case 'A': return 2;
        case 'B': return 3;
        case 'X': return 4;
        case 'Y': return 5;
        case 'M': return 6;
        case 'S': return 7;
        default: return 2;
    }
}

std::vector<std::uint8_t> symbols(const std::string& s) {
    std::vector<std::uint8_t> out;
    out.reserve(s.size());
    for (char c : s) out.push_back(sym(c));
    return out;
}
} // namespace

int main() {
    const auto table = minsky_table();
    CHECK_EQ(table.size(), 184u);

    Universe u(0x4D494E53);
    TuringMachine tm(u);
    CHECK(tm.load(table));
    tm.set_tape_symbols(symbols("001111YBAAXAAAAAAAXAABAAAASM000000Y001X0000001X0010110X0100011X0110100Y00"), 38);
    tm.set_state(5); // Minsky's UTM starts in state 6 (zero-based 5).

    // Python reference trace of the published machine: 100 steps.
    for (int i = 0; i < 100; ++i) {
        if (!tm.step()) break;
    }
    CHECK(!tm.halted());
    CHECK_EQ(tm.state(), 2);
    CHECK_EQ(tm.head(), 38);
    const std::string expected = "001111YBAAXAAAAAAAXAABAAAASM000000Y00BXAAAAAABXAA10110X0100011X0110100Y00";
    CHECK_EQ(expected.size(), 73u);
    for (std::size_t i = 0; i < expected.size(); ++i) {
        CHECK_EQ(tm.symbol(static_cast<std::int64_t>(i)), sym(expected[i]));
    }

    return test_done("Minsky 23-state/8-symbol table matches Python reference");
}
