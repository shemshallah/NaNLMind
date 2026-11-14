// Emit the actual C++ TuringMachine trace for the published Minsky input.
// The output is a deterministic line-oriented certificate used by the
// mechanized bridge check; it is not a new interpreter.
#include "nanlm/turing_machine.hpp"

#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> minsky_table() {
    return {
#include "../tests/minsky_table.inc"
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

void emit(int step, const TuringMachine& tm) {
    std::cout << "TRACE " << step << ' ' << static_cast<unsigned>(tm.state())
              << ' ' << tm.head() << ' ' << (tm.halted() ? 1 : 0);
    for (int i = 0; i < 73; ++i)
        std::cout << ' ' << static_cast<unsigned>(tm.symbol(i));
    std::cout << '\n';
}
} // namespace

int main() {
    Universe u(0x4D494E53);
    TuringMachine tm(u);
    if (!tm.load(minsky_table())) return 2;
    const std::string initial =
        "001111YBAAXAAAAAAAXAABAAAASM000000Y001X0000001X0010110X0100011X0110100Y00";
    tm.set_tape_symbols(symbols(initial), 38);
    tm.set_state(5);
    emit(0, tm);
    for (int i = 0; i < 100; ++i) {
        if (!tm.step()) break;
        emit(i + 1, tm);
    }
    return 0;
}
