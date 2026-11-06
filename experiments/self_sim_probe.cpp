#include "nanlm/binary_tm_compiler.hpp"
#include "nanlm/turing_machine.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> table() {
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
std::string bits(std::uint32_t x, unsigned n) {
    std::string s;
    for (unsigned i = 0; i < n; ++i) s.push_back(((x >> i) & 1u) ? '1' : '0');
    return s;
}
} // namespace

int main(int argc, char** argv) {
    const std::size_t limit = argc > 1
        ? static_cast<std::size_t>(std::strtoull(argv[1], nullptr, 10))
        : 10000000u;
    Universe u(0x53454C46);
    TuringMachine tm(u);
    if (!tm.load(table())) return 1;

    const auto source = table();
    const BinaryTm binary = compile_tm_to_binary(source, 23, 8, 6);
    unsigned p = 1;
    while ((1u << p) < binary.states) ++p;

    std::string desc;
    for (const auto& t : binary.transitions) {
        desc.push_back('X');
        desc += bits(t.from, p);
        desc.push_back(t.read ? '1' : '0');
        desc += bits(t.to, p);
        desc.push_back(t.write ? '1' : '0');
        desc.push_back(t.move > 0 ? '1' : '0');
    }
    std::vector<std::uint8_t> src_tape{0, 1, 2, 3, 4, 5, 6, 7,
                                       0, 1, 2, 3, 4, 5, 6, 7};
    const auto bt = encode_binary_tape(src_tape, binary.block_bits);
    std::string cond = bits(binary.initial_state, p);
    cond.push_back(bt[0] ? '1' : '0');
    std::string tape = "0000";
    for (auto b : bt) tape.push_back(b ? '1' : '0');
    tape += "M";
    tape += "00000000";
    tape += "Y";
    tape += cond;
    tape += desc;
    tape += "Y";
    tape += "0000";
    std::vector<std::uint8_t> ut;
    for (char c : tape) ut.push_back(sym(c));
    const std::int64_t head = 4 + static_cast<std::int64_t>(bt.size()) + 1 + 8 + 1 +
                              static_cast<std::int64_t>(cond.size());

    std::cout << "binary states=" << binary.states
              << " transitions=" << binary.transitions.size()
              << " p=" << p << " desc=" << desc.size()
              << " tape=" << ut.size() << " head=" << head << "\n";

    tm.set_tape_symbols(ut, head);
    tm.set_state(5);
    std::size_t ran = 0;
    while (ran < limit && !tm.halted()) {
        tm.step();
        ++ran;
    }
    std::cout << "ran=" << ran << " halted=" << tm.halted()
              << " state=" << static_cast<unsigned>(tm.state())
              << " head=" << tm.head() << " pages=" << tm.tape_pages() << "\n";
    return 0;
}
