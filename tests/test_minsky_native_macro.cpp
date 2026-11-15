// Native C++ execution of the *concrete* Coq positive-buffer macros.
//
// The expectations here are the explicit configurations in
// MinskyVariableBuffer.v, not evaluations of an alternate C++ interpreter.
// This checks executable machine conformance over finite inputs; it is NOT
// a proof of the C++ compiler or of the 23x8 machine's universality.

#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <random>
#include <vector>

using namespace nanlm;

namespace {
std::vector<TmTransition> canonical_table() {
    return {
#include "minsky_table.inc"
    };
}

struct Case {
    std::size_t buffer;
    std::vector<std::uint8_t> tail;
    bool high;
    std::uint8_t delimiter; // 4 for X, 5 for Y
    std::size_t marker;    // absolute native tape index for first X
};

void check_case(TuringMachine& native, const Case& c) {
    // The Coq zipper left side [0;...;0;Y;prefix] represents cells in
    // reverse order; here all coordinates are explicit and nonnegative.
    const auto first_x = c.marker;
    const auto y = first_x - c.buffer - 1;
    const auto next_marker = first_x + 2 + c.tail.size();
    const auto end = next_marker + 5;
    std::vector<std::uint8_t> before(end, 2);
    before[y - 1] = 6;
    before[y - 2] = 1;
    before[y - 3] = 3;
    before[y] = 5;
    for (std::size_t j = 0; j < c.buffer; ++j)
        before[y + 1 + j] = 0;
    before[first_x] = 4;
    before[first_x + 1] = c.high ? 1 : 0;
    for (std::size_t j = 0; j < c.tail.size(); ++j)
        before[first_x + 2 + j] = c.tail[j];
    before[next_marker] = c.delimiter;
    before[next_marker + 1] = 7;
    before[next_marker + 2] = 6;

    native.set_tape_symbols(before, static_cast<std::int64_t>(first_x));
    native.set_state(5);

    // Coq: positive_buffer_first_bit_at_2n_plus_4.
    const auto first_steps = 2 * c.buffer + 4;
    for (std::size_t step = 0; step < first_steps; ++step) {
        CHECK(native.step());
        CHECK(!native.halted());
    }
    CHECK_EQ(native.state(), c.high ? 3 : 2);
    CHECK_EQ(native.head(), static_cast<std::int64_t>(
        c.high ? first_x + 2 : first_x));
    CHECK_EQ(native.symbol(first_x), 4);
    CHECK_EQ(native.symbol(first_x + 1), c.high ? 3 : 2);

    // The first buffer cell (nearest Y) is 0; every other cell is 2.
    for (std::size_t j = 0; j < c.buffer; ++j)
        CHECK_EQ(native.symbol(static_cast<std::int64_t>(y + 1 + j)),
                 j == 0 ? 0 : 2);
    for (std::size_t j = 0; j < c.tail.size(); ++j)
        CHECK_EQ(native.symbol(static_cast<std::int64_t>(first_x + 2 + j)),
                 c.tail[j]);

    if (c.high) {
        // Coq: positive_buffer_high_reaches_next_marker / _halts_on_y.
        for (std::size_t j = 0; j < c.tail.size(); ++j) {
            CHECK(native.step());
            CHECK(!native.halted());
        }
        CHECK_EQ(native.head(), static_cast<std::int64_t>(next_marker));
        const auto running = native.step();
        if (c.delimiter == 4) {
            CHECK(running);
            CHECK(!native.halted());
            CHECK_EQ(native.state(), 5);
            CHECK_EQ(native.head(), static_cast<std::int64_t>(next_marker - 1));
        } else {
            CHECK(!running);
            CHECK(native.halted());
            CHECK_EQ(native.state(), 0);
            CHECK_EQ(native.head(), static_cast<std::int64_t>(next_marker));
            // A second step cannot restart the halted machine.
            CHECK(!native.step());
            CHECK(native.halted());
        }
    } else {
        // Coq: positive_buffer_low_returns_at_3n_plus_6.
        for (std::size_t j = 0; j < c.buffer + 2; ++j) {
            CHECK(native.step());
            CHECK(!native.halted());
        }
        CHECK_EQ(native.state(), 1);
        CHECK_EQ(native.head(), static_cast<std::int64_t>(y + 1));
    }

    // Compare the entire represented tape, including nonbinary sentinels.
    // This catches corruption outside the current record or its buffer.
    for (std::size_t p = 0; p < before.size(); ++p) {
        std::uint8_t expected = before[p];
        if (p >= y + 1 && p < first_x) expected = (p == y + 1) ? 0 : 2;
        if (p == first_x + 1) expected = c.high ? 3 : 2;
        CHECK_EQ(native.symbol(static_cast<std::int64_t>(p)), expected);
    }
}

void check_signed_page_boundaries() {
    // MinskyNativePages.v models quotient/remainder by 4096, including
    // negative addresses.  The separately allocated C++ pages must agree.
    // This is finite validation of the representation, not formal C++ proof.
    TuringTape tape;
    const auto low = std::numeric_limits<std::int64_t>::min();
    const auto high = std::numeric_limits<std::int64_t>::max();
    const std::array<std::int64_t, 11> addresses{
        low, -8193, -4097, -4096, -4095, -1,
        0, 1, 4095, 4096, high};
    CHECK_EQ(tape.read(low), 2);
    CHECK_EQ(tape.read(-1), 2);
    CHECK_EQ(tape.read(high), 2);
    for (std::size_t i = 0; i < addresses.size(); ++i)
        tape.write(addresses[i], static_cast<std::uint8_t>(i % 8));
    for (std::size_t i = 0; i < addresses.size(); ++i)
        CHECK_EQ(tape.read(addresses[i]), static_cast<std::uint8_t>(i % 8));
    CHECK_EQ(tape.read(-2), 2);
    CHECK_EQ(tape.read(4097), 2);
    const auto actual_keys = tape.page_keys();
    const std::vector<std::int64_t> expected_keys{
        -2251799813685248LL, -3, -2, -1, 0, 1,
        2251799813685247LL};
    CHECK(actual_keys == expected_keys);
}
} // namespace

int main() {
    Universe u(0x4D494E58);
    TuringMachine native(u);
    CHECK(native.load(canonical_table()));

    std::mt19937 rng(0x2385);
    std::size_t cases = 0;
    // 4095 and 4096 force tape-page crossings; 10 is an ordinary location.
    for (std::size_t buffer : {1u, 2u, 3u, 7u, 16u, 32u, 65u, 129u}) {
        for (std::size_t tail_length : {0u, 1u, 6u, 16u, 65u}) {
            std::vector<std::uint8_t> tail(tail_length);
            for (auto& bit : tail) bit = static_cast<std::uint8_t>(rng() & 1u);
            for (bool high : {false, true}) {
                for (std::uint8_t next : {std::uint8_t{4}, std::uint8_t{5}}) {
                    for (std::size_t location :
                         {buffer + 7, std::size_t{4095}, std::size_t{4096}}) {
                        check_case(native, Case{buffer, tail, high, next, location});
                        ++cases;
                    }
                }
            }
        }
    }
    CHECK_EQ(cases, 480u);
    check_signed_page_boundaries();
    return test_done("Minsky native C++ variable-buffer macros: 480 cases, page boundaries");
}
