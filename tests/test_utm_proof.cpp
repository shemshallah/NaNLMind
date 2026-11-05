#include "nanlm/global.hpp"
#include "nanlm/tm_description.hpp"
#include "nanlm/turing_machine.hpp"
#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::uint32_t lcg(std::uint32_t& s) { s = s * 1664525u + 1013904223u; return s; }

TmDescription random_machine(std::uint32_t& seed) {
    TmDescription d;
    d.states = 4;
    d.alphabet = 3;
    for (std::uint8_t from = 0; from < d.states; ++from) {
        for (std::uint8_t read = 0; read < d.alphabet; ++read) {
            TmTransition t;
            t.from = from;
            t.read = read;
            t.write = static_cast<std::uint8_t>(lcg(seed) % d.alphabet);
            t.move = static_cast<std::int8_t>(static_cast<int>(lcg(seed) % 3) - 1);
            t.to = static_cast<std::uint8_t>(lcg(seed) % d.states);
            t.halt = (lcg(seed) % 11) == 0;
            d.transitions.push_back(t);
        }
    }
    return d;
}
} // namespace

int main() {
    const std::vector<TmTransition> binary{
        {0, 1, 0, -1, 0, false},
        {0, 0, 1, 0, 0, true},
        {0, 2, 1, 0, 0, true},
    };
    TmDescription d;
    d.states = 1;
    d.alphabet = 3;
    d.transitions = binary;
    CHECK(d.valid());
    const auto bytes = d.encode();
    auto decoded = TmDescription::decode(bytes.data(), bytes.size());
    CHECK(decoded.has_value());
    if (decoded) CHECK_EQ(decoded->transitions.size(), binary.size());
    auto corrupt = bytes;
    corrupt[12] ^= 1;
    CHECK(!TmDescription::decode(corrupt.data(), corrupt.size()).has_value());

    // The runtime consumes the encoded grammar directly.
    Universe encoded_u(0x454E4344);
    UniversalTuringMachine encoded(encoded_u);
    CHECK(encoded.load_encoded_description(bytes.data(), bytes.size(), "1011", 3));
    encoded.run(100);
    CHECK_EQ(encoded.tape(0, 4), std::string("1100"));

    // Randomized cross-check: UTM interpreter vs table-driven TM.
    std::uint32_t seed = 0xC0FFEEu;
    for (int machine = 0; machine < 20; ++machine) {
        TmDescription desc = random_machine(seed);
        CHECK(desc.valid());
        std::string tape;
        for (int i = 0; i < 8; ++i) tape.push_back((lcg(seed) % 3 == 2) ? ' ' : (lcg(seed) % 2 ? '1' : '0'));

        Universe ref_u(0x52454631u + machine);
        TuringMachine ref(ref_u);
        CHECK(ref.load(desc.transitions));
        ref.set_tape(tape, 0);

        Universe utm_u(0x55544D31u + machine);
        UniversalTuringMachine utm(utm_u);
        CHECK(utm.load_description(desc, tape, 0));

        for (int step = 0; step < 30; ++step) {
            const bool ref_alive = ref.step();
            const bool utm_alive = utm.step();
            CHECK_EQ(utm.state(), ref.state());
            CHECK_EQ(utm.head(), ref.head());
            CHECK_EQ(utm.halted(), ref.halted());
            CHECK_EQ(utm.tape(-8, 16), ref.tape(-8, 16));
            if (!ref_alive || !utm_alive) break;
        }
    }

    // Exhaustive 1-state, 2-symbol table space (12 choices per read symbol).
    for (int code = 0; code < 12 * 12; ++code) {
        int c = code;
        TmDescription small;
        small.states = 1;
        small.alphabet = 2;
        for (std::uint8_t read = 0; read < 2; ++read) {
            TmTransition t;
            t.from = 0;
            t.read = read;
            t.write = static_cast<std::uint8_t>(c % 2); c /= 2;
            t.move = static_cast<std::int8_t>(c % 3 - 1); c /= 3;
            t.to = 0;
            t.halt = (c % 2) != 0; c /= 2;
            small.transitions.push_back(t);
        }
        CHECK(small.valid());
        Universe ref_u(0x45584831u + static_cast<std::uint32_t>(code));
        TuringMachine ref(ref_u);
        CHECK(ref.load(small.transitions));
        ref.set_tape("01", 0);
        Universe utm_u(0x45585531u + static_cast<std::uint32_t>(code));
        UniversalTuringMachine utm(utm_u);
        CHECK(utm.load_description(small, "01", 0));
        for (int step = 0; step < 12; ++step) {
            const bool ra = ref.step();
            const bool ua = utm.step();
            CHECK_EQ(ref.state(), utm.state());
            CHECK_EQ(ref.head(), utm.head());
            CHECK_EQ(ref.halted(), utm.halted());
            CHECK_EQ(ref.tape(-4, 6), utm.tape(-4, 6));
            if (!ra || !ua) break;
        }
    }

    // Ledger-linked tape checkpoint.
    Universe u(0x4C454447);
    UniversalTuringMachine utm(u);
    CHECK(utm.load_machine(binary, "1011", 3));
    utm.run(100);
    const auto tape = utm.serialize_tape();
    const Hash256 tape_hash = Sha256::hash(tape.data(), tape.size());
    GlobalTopology g;
    g.commit(1, 0, 0, Hash256{}, tape_hash, 0);
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK(g.ledger().verify());
    Universe restored_u(0x4C454447);
    UniversalTuringMachine restored(restored_u);
    CHECK(restored.load_machine(binary, "", 0));
    CHECK(restored.restore_tape(tape.data(), tape.size()));
    CHECK_EQ(restored.tape(0, 4), std::string("1100"));

    return test_done("UTM proof harness: grammar, random cross-check, ledger checkpoint");
}
