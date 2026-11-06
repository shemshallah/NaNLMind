#include "nanlm/binary_tm_compiler.hpp"

#include <algorithm>
#include <map>
#include <tuple>
#include <utility>

namespace nanlm {
namespace {
using Key = std::tuple<int, int, int, int>;

std::uint8_t block_bits_for(std::uint8_t symbols) {
    std::uint8_t bits = 1;
    while ((1u << bits) < symbols) ++bits;
    return bits;
}
} // namespace

std::vector<std::uint8_t> encode_binary_tape(
    const std::vector<std::uint8_t>& source_tape, std::uint8_t block_bits) {
    std::vector<std::uint8_t> out;
    out.reserve(source_tape.size() * block_bits);
    for (std::uint8_t s : source_tape) {
        for (std::uint8_t b = 0; b < block_bits; ++b) {
            out.push_back(static_cast<std::uint8_t>((s >> b) & 1u));
        }
    }
    return out;
}

BinaryTm compile_tm_to_binary(const std::vector<TmTransition>& source,
                              std::uint8_t source_states,
                              std::uint8_t source_symbols,
                              std::uint8_t initial_state) {
    BinaryTm out;
    out.block_bits = block_bits_for(source_symbols);
    std::map<std::pair<std::uint8_t, std::uint8_t>, TmTransition> table;
    for (const auto& t : source) table[{t.from, t.read}] = t;

    std::map<Key, std::uint16_t> ids;
    auto id = [&](int phase, int a, int b, int c) -> std::uint16_t {
        const Key key{phase, a, b, c};
        const auto it = ids.find(key);
        if (it != ids.end()) return it->second;
        const auto next = static_cast<std::uint16_t>(ids.size());
        ids.emplace(key, next);
        return next;
    };

    const std::uint16_t halt = id(9, 0, 0, 0);
    std::map<std::pair<std::uint16_t, std::uint8_t>, BinaryTransition> transitions;
    auto add = [&](std::uint16_t from, std::uint8_t read, std::uint16_t to,
                   std::uint8_t write, int move) {
        transitions.emplace(std::make_pair(from, read),
                            BinaryTransition{from, read, write,
                                             static_cast<std::int8_t>(move), to});
    };

    // Read one 3-bit (or ceil(log2(symbols))) block at a block boundary.
    for (std::uint8_t q = 0; q < source_states; ++q) {
        const std::uint16_t r0 = id(0, q, 0, 0);
        out.r0_state[r0] = q;
        for (std::uint8_t b0 = 0; b0 < 2; ++b0) {
            const std::uint16_t r1 = id(1, q, b0, 0);
            add(r0, b0, r1, b0, +1);
            for (std::uint8_t b1 = 0; b1 < 2; ++b1) {
                const std::uint16_t r2 = id(2, q, b0, b1);
                add(r1, b1, r2, b1, +1);
                for (std::uint8_t b2 = 0; b2 < 2; ++b2) {
                    const std::uint8_t symbol =
                        static_cast<std::uint8_t>(b0 | (b1 << 1) | (b2 << 2));
                    if (symbol >= source_symbols) continue;
                    const auto it = table.find({q, symbol});
                    if (it == table.end()) continue;
                    const auto& t = it->second;
                    const std::uint16_t w1 = id(3, t.to, t.write, t.move);
                    add(r2, b2, w1, b2, -1);
                }
            }
        }
    }

    // Write the saved symbol bits back, then move by one source cell.
    for (const auto& [key, t] : table) {
        (void)key;
        const std::uint16_t w1 = id(3, t.to, t.write, t.move);
        const std::uint16_t w0 = id(4, t.to, t.write, t.move);
        for (std::uint8_t bit = 0; bit < 2; ++bit) {
            add(w1, bit, w0, static_cast<std::uint8_t>((t.write >> 1) & 1u), -1);
        }
        std::uint16_t target = halt;
        if (!t.halt) {
            if (t.move > 0) target = id(5, t.to, 0, 0);
            else if (t.move < 0) target = id(6, t.to, 0, 0);
            else target = id(0, t.to, 0, 0);
        }
        for (std::uint8_t bit = 0; bit < 2; ++bit) {
            add(w0, bit, target, t.write & 1u, t.move);
        }
        if (!t.halt && t.move > 0) {
            const std::uint16_t mr2 = id(7, t.to, 0, 0);
            const std::uint16_t r0 = id(0, t.to, 0, 0);
            for (std::uint8_t bit = 0; bit < 2; ++bit) {
                add(target, bit, mr2, bit, +1);
                add(mr2, bit, r0, bit, +1);
            }
        } else if (!t.halt && t.move < 0) {
            const std::uint16_t ml2 = id(8, t.to, 0, 0);
            const std::uint16_t r0 = id(0, t.to, 0, 0);
            for (std::uint8_t bit = 0; bit < 2; ++bit) {
                add(target, bit, ml2, bit, -1);
                add(ml2, bit, r0, bit, -1);
            }
        }
    }

    out.states = static_cast<std::uint16_t>(ids.size());
    out.initial_state = id(0, initial_state, 0, 0);
    out.transitions.reserve(transitions.size());
    for (const auto& [key, t] : transitions) {
        (void)key;
        out.transitions.push_back(t);
    }
    return out;
}

} // namespace nanlm
