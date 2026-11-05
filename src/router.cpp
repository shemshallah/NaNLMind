#include "nanlm/router.hpp"

namespace nanlm {

RouterChart::RouterChart(GlobalTopology& topology, PageId chart)
    : topology_(&topology), chart_(std::move(chart)) {}

bool RouterChart::has_universe(std::uint8_t head) const {
    return topology_->has_chart(PageId::child(chart_, head));
}

bool RouterChart::open_universe(std::uint8_t head, std::uint64_t genome) {
    return topology_->add_chart(chart_, head, genome).depth != 0;
}

RouteResult RouterChart::route(std::uint8_t src, std::uint8_t dst, PortalOp op,
                               std::uint32_t data, std::uint8_t flags,
                               std::uint64_t epoch) {
    RouteResult result;
    auto page = topology_->pages().resolve(chart_);
    if (!page) {
        result.error = "router chart not present";
        return result;
    }
    const std::uint16_t addr = matrix_addr(src, dst);
    PortalWord word{op, flags, data};
    const std::uint8_t rail = portal_is_forward(op) ? 0u : 1u;
    if (!topology_->pages().write_word(chart_, addr, rail, word.encode())) {
        result.error = "route write failed";
        return result;
    }
    // write_word may have cloned the page; re-resolve before touching aux.
    page = topology_->pages().resolve(chart_);
    NanCell& cell = page->at_addr(addr);
    cell.aux = static_cast<std::uint16_t>((static_cast<std::uint16_t>(op) << 8) | flags);
    cell.epoch = static_cast<std::uint32_t>(epoch);
    cell.generation = static_cast<std::uint16_t>(cell.generation + 1u);
    topology_->pages().touch(chart_, addr);
    result.ok = true;
    result.word = word;
    return result;
}

RouteResult RouterChart::request_time(std::uint8_t src, std::uint8_t dst,
                                         std::uint64_t epoch) {
    RouteResult r = route(src, dst, PortalOp::ReadForward, kTimeRequestMagic,
                          kTimeRequestFlag, epoch);
    if (r.ok) r.word.flags = kTimeRequestFlag;
    return r;
    }

RouteResult RouterChart::read(std::uint8_t src, std::uint8_t dst, bool forward) const {
    RouteResult result;
    const std::uint16_t addr = matrix_addr(src, dst);
    NanWord word;
    if (!topology_->pages().read_word(chart_, addr, forward ? 0u : 1u, word)) {
        result.error = "route read failed";
        return result;
    }
    const auto page = topology_->pages().resolve(chart_);
    if (!page) {
        result.error = "router chart not present";
        return result;
    }
    result.word = PortalWord::decode(word, page->at_addr(addr).aux);
    result.ok = true;
    return result;
}

} // namespace nanlm
