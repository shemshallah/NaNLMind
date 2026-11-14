// Concrete bridge gate: every 23x8 transition of the canonical Minsky table
// must execute identically through the indexed TM and chart-backed scan UTM.
// This is an executable conformance test, not a proof of compiled C++ semantics.
#include "nanlm/tm_description.hpp"
#include "nanlm/turing_machine.hpp"
#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> minsky_table() {
    return {
#include "minsky_table.inc"
    };
}

void check_configuration(const TuringMachine& indexed,
                         const UniversalTuringMachine& scanning) {
    CHECK_EQ(indexed.state(), scanning.state());
    CHECK_EQ(indexed.head(), scanning.head());
    CHECK_EQ(indexed.halted(), scanning.halted());
    for (std::int64_t p = -6; p <= 12; ++p)
        CHECK_EQ(indexed.symbol(p), scanning.symbol(p));
}

void check_single_entry(const TmDescription& description,
                        std::uint8_t q, std::uint8_t s,
                        std::uint32_t trial) {
    const auto& t = description.transitions[static_cast<std::size_t>(q) * 8 + s];
    CHECK_EQ(t.from, q);
    CHECK_EQ(t.read, s);

    const std::vector<std::uint8_t> tape{2, s, 2};
    Universe indexed_universe(0x4D495300u + trial);
    TuringMachine indexed(indexed_universe);
    CHECK(indexed.load(description.transitions));
    indexed.set_tape_symbols(tape, 1);
    indexed.set_state(q);

    Universe scanning_universe(0x53434100u + trial);
    UniversalTuringMachine scanning(scanning_universe);
    CHECK(scanning.load_description_symbols(description, tape, 1));
    scanning.set_state(q);

    check_configuration(indexed, scanning);
    const bool indexed_running = indexed.step();
    const bool scanning_running = scanning.step();
    CHECK_EQ(indexed_running, !t.halt);
    CHECK_EQ(scanning_running, !t.halt);
    CHECK_EQ(indexed.state(), t.to);
    CHECK_EQ(indexed.head(), static_cast<std::int64_t>(1 + t.move));
    CHECK_EQ(indexed.symbol(1), t.write);
    CHECK_EQ(indexed.halted(), t.halt);
    check_configuration(indexed, scanning);

    // Continue across transitions and check every intermediate configuration.
    // The explicit halting row is also checked for idempotence on later calls.
    for (int i = 0; i < 12; ++i) {
        const bool left = indexed.step();
        const bool right = scanning.step();
        CHECK_EQ(left, right);
        check_configuration(indexed, scanning);
    }
}

void check_invalid(const TmDescription& description,
                   std::uint8_t state, std::uint8_t symbol,
                   std::uint32_t seed) {
    const std::vector<std::uint8_t> tape{symbol};
    Universe indexed_universe(0x494E5600u + seed);
    TuringMachine indexed(indexed_universe);
    CHECK(indexed.load(description.transitions));
    indexed.set_tape_symbols(tape, 0);
    indexed.set_state(state);

    Universe scanning_universe(0x494E5700u + seed);
    UniversalTuringMachine scanning(scanning_universe);
    CHECK(scanning.load_description_symbols(description, tape, 0));
    scanning.set_state(state);

    CHECK(!indexed.step());
    CHECK(!scanning.step());
    CHECK(indexed.halted());
    CHECK(scanning.halted());
    CHECK_EQ(indexed.state(), state);
    CHECK_EQ(indexed.head(), 0);
    CHECK_EQ(indexed.symbol(0), symbol);
    check_configuration(indexed, scanning);
    CHECK(!indexed.step());
    CHECK(!scanning.step());
    check_configuration(indexed, scanning);
}
} // namespace

int main() {
    TmDescription description;
    description.states = 23;
    description.alphabet = 8;
    description.transitions = minsky_table();
    CHECK(description.valid());
    CHECK_EQ(description.transitions.size(), 184u);

    // Exhaust every in-domain (state, symbol), not merely sampled traces.
    for (std::uint8_t q = 0; q < 23; ++q)
        for (std::uint8_t s = 0; s < 8; ++s)
            check_single_entry(description, q, s,
                               static_cast<std::uint32_t>(q) * 8u + s);

    // Outside the table must halt without aliasing another row or writing.
    check_invalid(description, 23, 0, 1);
    check_invalid(description, 31, 7, 2);
    check_invalid(description, 0, 8, 3);
    check_invalid(description, 22, 255, 4);

    // Test a negative head coordinate, for which the tape's blank is 2.
    {
        Universe indexed_u(0x4E454731);
        TuringMachine indexed(indexed_u);
        CHECK(indexed.load(description.transitions));
        indexed.set_tape_symbols({0}, 0);
        indexed.set_state(0);  // q0,0 -> L, q2, write 2.
        Universe scanning_u(0x4E454732);
        UniversalTuringMachine scanning(scanning_u);
        CHECK(scanning.load_description_symbols(description, {0}, 0));
        scanning.set_state(0);
        CHECK(indexed.step());
        CHECK(scanning.step());
        CHECK_EQ(indexed.head(), -1);
        CHECK_EQ(indexed.symbol(-1), 2);
        check_configuration(indexed, scanning);
        for (int i = 0; i < 12; ++i) {
            CHECK_EQ(indexed.step(), scanning.step());
            check_configuration(indexed, scanning);
        }
    }

    return test_done("Minsky chart refinement: 184 entries, halting, malformed and negative tape");
}
