#include "nanlm/context2_topology.hpp"

namespace nanlm {

bool Context2Topology::ensure_universe(std::uint8_t a) {
    if (open_[a]) return true;
    const PageId child = topology_->add_chart(router_, a, 0x434f4e54ull + a);
    if (child.depth == 0) return false;
    auto page = topology_->pages().resolve(child);
    if (!page) return false;
    // A context child is a count slab: clear the four NaN payloads so the
    // genesis mix does not leak into the counts. The head identity remains.
    for (auto& cell : page->cells()) {
        cell.s_plus() = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, 0);
        cell.s_minus() = NanWord::make(NanType::QuietNegative, NanType::QuietNegative, 0);
        cell.q_plus() = NanWord::make(NanType::SignalPositive, NanType::SignalPositive, 0);
        cell.q_minus() = NanWord::make(NanType::SignalNegative, NanType::SignalNegative, 0);
    }
    page->refresh_checksums();
    child_[a] = child;
    open_[a] = true;
    return true;
}

bool Context2Topology::observe(std::uint8_t a, std::uint8_t b, std::uint8_t c,
                               std::uint32_t n) {
    if (!ensure_universe(a)) return false;
    const std::uint16_t addr = matrix_addr(b, c);
    const std::uint8_t rail = (b <= c) ? 0u : 1u; // directed count on the pair cell
    NanWord word;
    if (!topology_->pages().read_word(child_[a], addr, rail, word)) return false;
    const std::uint32_t old = word.payload();
    const std::uint32_t next = (old > 0xFFFFFFFFu - n) ? 0xFFFFFFFFu : old + n;
    const NanType t = (rail == 0u) ? NanType::QuietPositive : NanType::QuietNegative;
    if (!topology_->pages().write_word(child_[a], addr, rail, NanWord::make(t, t, next))) {
        return false;
    }
    return topology_->pages().touch(child_[a], addr);
}

std::uint32_t Context2Topology::count(std::uint8_t a, std::uint8_t b,
                                      std::uint8_t c) const {
    if (!open_[a]) return 0;
    NanWord word;
    const std::uint8_t rail = (b <= c) ? 0u : 1u;
    if (!topology_->pages().read_word(child_[a], matrix_addr(b, c), rail, word)) return 0;
    return word.payload();
}

std::uint8_t Context2Topology::predict(std::uint8_t a, std::uint8_t b) const {
    if (!open_[a]) return 0;
    std::uint32_t best = 0;
    std::uint8_t best_c = 0;
    for (std::uint32_t c = 0; c < 256; ++c) {
        const std::uint32_t n = count(a, b, static_cast<std::uint8_t>(c));
        if (n > best) {
            best = n;
            best_c = static_cast<std::uint8_t>(c);
        }
    }
    return best_c;
}

std::size_t Context2Topology::universes() const {
    std::size_t n = 0;
    for (bool b : open_) if (b) ++n;
    return n;
}

} // namespace nanlm
