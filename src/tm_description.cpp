#include "nanlm/tm_description.hpp"
#include "nanlm/sha256.hpp"

#include <cstring>

namespace nanlm {
namespace {
void put(std::vector<std::uint8_t>& o, std::uint64_t v, unsigned n) {
    for (unsigned i = 0; i < n; ++i) o.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
}
bool get(const std::uint8_t* d, std::size_t n, std::size_t& p, unsigned b, std::uint64_t& v) {
    if (p > n || n - p < b) return false;
    v = 0;
    for (unsigned i = 0; i < b; ++i) v |= static_cast<std::uint64_t>(d[p++]) << (8 * i);
    return true;
}
} // namespace

bool TmDescription::valid() const {
    if (states == 0 || states > 32 || alphabet < 2 || alphabet > 8) return false;
    if (transitions.size() > 255) return false;
    for (const auto& t : transitions) {
        if (t.from >= states || t.to >= states || t.read >= alphabet || t.write >= alphabet)
            return false;
        if (t.move < -1 || t.move > 1) return false;
    }
    return true;
}

std::vector<std::uint8_t> TmDescription::encode() const {
    std::vector<std::uint8_t> o{'N', 'L', 'M', 'T', 'M', '0', '0', '1'};
    put(o, kVersion, 2);
    put(o, states, 2);
    put(o, alphabet, 2);
    put(o, transitions.size(), 2);
    for (const auto& t : transitions) {
        o.push_back(t.from); o.push_back(t.read); o.push_back(t.write);
        o.push_back(static_cast<std::uint8_t>(t.move + 1));
        o.push_back(t.to); o.push_back(t.halt ? 1 : 0);
    }
    const Hash256 d = Sha256::hash(o.data(), o.size());
    o.insert(o.end(), d.begin(), d.end());
    return o;
}

std::optional<TmDescription> TmDescription::decode(const std::uint8_t* data, std::size_t len) {
    if (!data || len < 8 + 6 + 32 || std::memcmp(data, "NLMTM001", 8) != 0) return std::nullopt;
    std::size_t p = 8;
    std::uint64_t version = 0, states = 0, alphabet = 0, count = 0;
    if (!get(data, len, p, 2, version) || version != kVersion) return std::nullopt;
    if (!get(data, len, p, 2, states) || !get(data, len, p, 2, alphabet) ||
        !get(data, len, p, 2, count)) return std::nullopt;
    if (states == 0 || states > 32 || alphabet < 2 || alphabet > 8 || count > 255) return std::nullopt;
    if (len - p != count * 6 + 32) return std::nullopt;
    TmDescription out;
    out.states = static_cast<std::uint16_t>(states);
    out.alphabet = static_cast<std::uint16_t>(alphabet);
    for (std::uint64_t i = 0; i < count; ++i) {
        TmTransition t;
        t.from = data[p++]; t.read = data[p++]; t.write = data[p++];
        t.move = static_cast<std::int8_t>(data[p++]) - 1;
        t.to = data[p++]; t.halt = data[p++] != 0;
        out.transitions.push_back(t);
    }
    const Hash256 expected = Sha256::hash(data, p);
    if (std::memcmp(expected.data(), data + p, 32) != 0) return std::nullopt;
    if (!out.valid()) return std::nullopt;
    return out;
}

} // namespace nanlm
