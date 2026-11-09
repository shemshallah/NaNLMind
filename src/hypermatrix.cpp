#include "nanlm/hypermatrix.hpp"

#include <algorithm>
#include <bit>
#include <cstring>
#include <set>

namespace nanlm {
namespace {
std::uint8_t lowest_set_rule(std::uint16_t mask) {
    for (std::uint8_t r = 0; r < 16; ++r) {
        if ((mask & (1u << r)) != 0) return r;
    }
    return 0;
}
} // namespace

void Hypermatrix::set_bit(Universe& universe, std::uint8_t a, std::uint8_t b,
                          std::uint8_t candidate) {
    auto& row = universe.hypermatrix_row(row_address(a, b));
    const std::uint8_t shift = static_cast<std::uint8_t>(candidate & 7u);
    row[candidate >> 3] = static_cast<std::uint8_t>(
        row[candidate >> 3] | (1u << shift));
}

void Hypermatrix::clear_bit(Universe& universe, std::uint8_t a, std::uint8_t b,
                            std::uint8_t candidate) {
    auto& row = universe.hypermatrix_row(row_address(a, b));
    const std::uint8_t shift = static_cast<std::uint8_t>(candidate & 7u);
    row[candidate >> 3] = static_cast<std::uint8_t>(
        row[candidate >> 3] & ~(1u << shift));
}

bool Hypermatrix::bit(const Universe& universe, std::uint8_t a, std::uint8_t b,
                      std::uint8_t candidate) {
    const auto& row = universe.hypermatrix_row(row_address(a, b));
    const std::uint8_t shift = static_cast<std::uint8_t>(candidate & 7u);
    return (row[candidate >> 3] & (1u << shift)) != 0;
}

void Hypermatrix::set(std::uint8_t a, std::uint8_t b, std::uint8_t c) {
    set_bit(*universe_, a, b, c);
    set_bit(*universe_, b, c, a);
    set_bit(*universe_, c, a, b);
}

void Hypermatrix::clear(std::uint8_t a, std::uint8_t b, std::uint8_t c) {
    clear_bit(*universe_, a, b, c);
    clear_bit(*universe_, b, c, a);
    clear_bit(*universe_, c, a, b);
}

bool Hypermatrix::has(std::uint8_t a, std::uint8_t b, std::uint8_t c) const {
    return exact_support(a, b, c) == 3u;
}

std::uint32_t Hypermatrix::exact_support(std::uint8_t a, std::uint8_t b,
                                         std::uint8_t c) const {
    if (a == b || b == c || a == c) return 0;
    std::uint32_t count = 0;
    count += bit(*universe_, a, b, c) ? 1u : 0u;
    count += bit(*universe_, b, c, a) ? 1u : 0u;
    count += bit(*universe_, c, a, b) ? 1u : 0u;
    return count;
}

bool Hypermatrix::pair_active(const Universe& universe, std::uint8_t a,
                              std::uint8_t b) {
    if (a == b) return false;
    return universe.pair_cell(a, b).q_plus().payload() != 0;
}

std::uint32_t Hypermatrix::dense_support(std::uint8_t a, std::uint8_t b,
                                         std::uint8_t c) const {
    if (a == b || b == c || a == c) return 0;
    const bool ab = pair_active(*universe_, a, b);
    const bool bc = pair_active(*universe_, b, c);
    const bool ca = pair_active(*universe_, c, a);
    return static_cast<std::uint32_t>(ab && bc) +
           static_cast<std::uint32_t>(bc && ca) +
           static_cast<std::uint32_t>(ca && ab);
}

std::uint32_t Hypermatrix::head_coupling(std::uint8_t a, std::uint8_t b,
                                         std::uint8_t c) const {
    const auto& ha = universe_->head(a);
    const auto& hb = universe_->head(b);
    const auto& hc = universe_->head(c);
    const std::uint32_t fa = (ha.phase ^ ha.energy) & 0xFFu;
    const std::uint32_t fb = (hb.phase ^ (static_cast<std::uint32_t>(hb.self_error) << 8)) & 0xFFu;
    const std::uint32_t fc = (hc.phase ^ (static_cast<std::uint32_t>(hc.load) << 4)) & 0xFFu;
    const std::uint32_t cp = fa * fb * fc;
    return (cp >> 8) & 3u;
}

std::uint32_t Hypermatrix::score(std::uint8_t a, std::uint8_t b,
                                 std::uint8_t c) const {
    const std::uint32_t base = exact_support(a, b, c) * 4u +
                               dense_support(a, b, c) + head_coupling(a, b, c);
    const std::int64_t gain =
        (static_cast<std::int64_t>(TriadField::local_gain(*universe_, a)) +
         TriadField::local_gain(*universe_, b) +
         TriadField::local_gain(*universe_, c) +
         TriadField::group_gain(*universe_, a) +
         TriadField::group_gain(*universe_, b) +
         TriadField::group_gain(*universe_, c) +
         3 * static_cast<std::int64_t>(TriadField::field_gain(*universe_))) / 9;
    return static_cast<std::uint32_t>(
        (static_cast<std::int64_t>(base) * gain) / 65536);
}

bool Hypermatrix::project(Universe& universe, const Hyperedge& edge) {
    std::vector<std::uint8_t> heads;
    for (const auto& member : edge.members) {
        BitAddress bit{};
        if (!member.as_bit(bit)) continue;
        if (!(bit.page == PageId::root())) continue;
        if (!is_palindrome16(bit.cell)) continue;
        const std::uint8_t head = matrix_row(bit.cell);
        if (std::find(heads.begin(), heads.end(), head) == heads.end())
            heads.push_back(head);
    }
    if (heads.size() < 3) return false;
    Hypermatrix matrix(universe);
    matrix.set(heads[0], heads[1], heads[2]);
    return true;
}

bool Hypermatrix::project(const Hyperedge& edge) {
    return project(*universe_, edge);
}

std::uint8_t TriadField::leader(std::uint8_t head) {
    if (head == kFieldHead) return kFieldHead;
    return static_cast<std::uint8_t>(head - (head % kTriadSize));
}

std::array<std::uint8_t, TriadField::kTriadSize>
TriadField::members(std::uint8_t head) {
    if (head >= kCognitiveHeads) return {kFieldHead, kFieldHead, kFieldHead};
    const std::uint8_t l = leader(head);
    return {l, static_cast<std::uint8_t>(l + 1u),
            static_cast<std::uint8_t>(l + 2u)};
}

std::uint32_t TriadField::votes(const Universe& universe, std::uint8_t head) {
    const auto& scratch = universe.head_scratch(leader(head));
    std::uint32_t mask = 0;
    std::memcpy(&mask, scratch.local() + kVoteOffset, sizeof(mask));
    return mask & 7u;
}

bool TriadField::vote(Universe& universe, std::uint8_t head, bool approve) {
    const std::uint8_t l = leader(head);
    auto& scratch = universe.head_scratch(l);
    std::uint32_t mask = 0;
    std::memcpy(&mask, scratch.local() + kVoteOffset, sizeof(mask));
    if (head == kFieldHead) {
        mask = approve ? 1u : 0u;
    } else {
        const std::uint32_t bit = 1u << (head % kTriadSize);
        mask = approve ? (mask | bit) : (mask & ~bit);
        mask &= 7u;
    }
    std::memcpy(scratch.local() + kVoteOffset, &mask, sizeof(mask));
    if (head == kFieldHead) return approve;
    return std::popcount(mask) >= 2;
}

void TriadField::clear(Universe& universe, std::uint8_t head) {
    const std::uint8_t l = leader(head);
    auto& scratch = universe.head_scratch(l);
    const std::uint32_t zero = 0;
    std::memcpy(scratch.local() + kVoteOffset, &zero, sizeof(zero));
}

bool TriadField::accepted(const Universe& universe, std::uint8_t head) {
    if (head == kFieldHead) return (votes(universe, head) & 1u) != 0;
    return std::popcount(votes(universe, head)) >= 2;
}

std::uint16_t TriadField::update_field(Universe& universe) {
    std::uint16_t accepted_count = 0;
    for (std::uint8_t t = 0; t < kTriadCount; ++t) {
        if (accepted(universe, static_cast<std::uint8_t>(t * kTriadSize)))
            ++accepted_count;
    }
    auto& scratch = universe.head_scratch(kFieldHead);
    std::memcpy(scratch.local() + kFieldOffset, &accepted_count,
                sizeof(accepted_count));
    return accepted_count;
}

bool TriadField::field_accepted(const Universe& universe) {
    const auto& scratch = universe.head_scratch(kFieldHead);
    std::uint16_t count = 0;
    std::memcpy(&count, scratch.local() + kFieldOffset, sizeof(count));
    return count >= (kTriadCount / 2u + 1u);
}

std::uint16_t TriadField::field_count(const Universe& universe) {
    const auto& scratch = universe.head_scratch(kFieldHead);
    std::uint16_t count = 0;
    std::memcpy(&count, scratch.local() + kFieldOffset, sizeof(count));
    return count;
}

namespace {
std::int32_t read_gain(const Universe& universe, std::uint8_t head,
                       std::size_t offset) {
    const auto& scratch = universe.head_scratch(head);
    std::int32_t value = 0;
    std::memcpy(&value, scratch.local() + offset, sizeof(value));
    if (value == 0) return 65536;
    return std::clamp(value, 0, 131072);
}
void write_gain(Universe& universe, std::uint8_t head, std::size_t offset,
                std::int32_t value) {
    value = std::clamp(value, 0, 131072);
    auto& scratch = universe.head_scratch(head);
    std::memcpy(scratch.local() + offset, &value, sizeof(value));
}
std::uint8_t group_register(std::uint8_t head) {
    const std::uint8_t l = TriadField::leader(head);
    return l == TriadField::kFieldHead ? l
                                       : static_cast<std::uint8_t>(l + 2u);
}
} // namespace

std::int32_t TriadField::local_gain(const Universe& universe,
                                    std::uint8_t head) {
    return read_gain(universe, head, kLocalGainOffset);
}

std::int32_t TriadField::group_gain(const Universe& universe,
                                    std::uint8_t head) {
    return read_gain(universe, group_register(head), kGroupGainOffset);
}

std::int32_t TriadField::field_gain(const Universe& universe) {
    return read_gain(universe, kFieldHead, kLocalGainOffset);
}

void TriadField::set_local_gain(Universe& universe, std::uint8_t head,
                                std::int32_t q16) {
    write_gain(universe, head, kLocalGainOffset, q16);
}

void TriadField::set_group_gain(Universe& universe, std::uint8_t head,
                                std::int32_t q16) {
    write_gain(universe, group_register(head), kGroupGainOffset, q16);
}

void TriadField::set_field_gain(Universe& universe, std::int32_t q16) {
    write_gain(universe, kFieldHead, kLocalGainOffset, q16);
}

bool TriadField::apply_patch(Universe& universe, HeadArray& heads,
                             std::uint8_t proposer, std::uint16_t patch,
                             std::uint32_t a, std::uint32_t b, bool target) {
    if (patch == 0) return false;
    const auto trio = members(proposer);
    clear(universe, proposer);
    for (std::uint8_t member : trio) {
        if (member == kFieldHead) {
            vote(universe, member, false);
            continue;
        }
        HeadView view = heads.at(member);
        const std::uint8_t current_rule = view.boolean_rule();
        const std::uint16_t next_mask =
            static_cast<std::uint16_t>(view.boolean_mask() ^ patch);
        const std::uint8_t candidate_rule = lowest_set_rule(next_mask);
        const bool current_ok =
            (NanWord::eval_bool(current_rule, a, b) & 1u) == (target ? 1u : 0u);
        const bool candidate_ok =
            (NanWord::eval_bool(candidate_rule, a, b) & 1u) == (target ? 1u : 0u);
        vote(universe, member, candidate_ok && !current_ok);
    }
    if (!accepted(universe, proposer)) return false;
    for (std::uint8_t member : trio) {
        if (member == kFieldHead) continue;
        HeadView view = heads.at(member);
        view.self_modify_boolean(patch);
    }
    update_field(universe);
    return true;
}

} // namespace nanlm
