#include "nanlm/tm_description.hpp"
#include "nanlm/turing_machine.hpp"
#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <string>
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
    out.reserve(s.size());
    for (char c : s) out.push_back(sym(c));
    return out;
}
} // namespace

int main() {
    const auto table = minsky_table();
    TmDescription desc;
    desc.states = 23;
    desc.alphabet = 8;
    desc.transitions = table;
    CHECK(desc.valid());
    const auto encoded = desc.encode();
    auto decoded = TmDescription::decode(encoded.data(), encoded.size());
    CHECK(decoded.has_value());
    if (!decoded) return 1;

    // Minsky UTM tape containing a normal encoded binary machine and input.
    const std::string initial =
        "000" "000" "M" "00000000" "Y" "000"
        "X0000111X0101011" "Y" "000";
    const auto tape = symbols(initial);

    Universe ref_u(0x5245464D);
    TuringMachine ref(ref_u);
    CHECK(ref.load(table));
    ref.set_tape_symbols(tape, 19);
    ref.set_state(5);

    Universe utm_u(0x55544D44);
    UniversalTuringMachine utm(utm_u);
    CHECK(utm.load_description_symbols(*decoded, tape, 19));
    utm.set_state(5);

    for (int i = 0; i < 100; ++i) {
        const bool a = ref.step();
        const bool b = utm.step();
        CHECK_EQ(ref.state(), utm.state());
        CHECK_EQ(ref.head(), utm.head());
        CHECK_EQ(ref.halted(), utm.halted());
        for (std::int64_t p = 0; p < static_cast<std::int64_t>(initial.size()); ++p) {
            CHECK_EQ(ref.symbol(p), utm.symbol(p));
        }
        if (!a || !b) break;
    }

    return test_done("encoded Minsky universal description runs on the chart UTM");
}
