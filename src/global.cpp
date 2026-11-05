#include "nanlm/global.hpp"

#include <stdexcept>

namespace nanlm {

GlobalTopology::GlobalTopology() : GlobalTopology(0) {}

GlobalTopology::GlobalTopology(std::uint64_t genome) {
    auto root = std::make_shared<Universe>(genome);
    pages_.map(PageId::root(), root);
    Hash256 genesis = root->digest();
    ledger_ = Ledger(genesis);
    clock_.init();
}

PageId GlobalTopology::add_chart(const PageId& parent, std::uint8_t head,
                                 std::uint64_t genome) {
    if (!pages_.contains(parent)) return {};
    const PageId child = PageId::child(parent, head);
    if (pages_.contains(child)) return child;
    auto page = std::make_shared<Universe>(genome);
    if (!pages_.map(child, page)) return {};
    const Hash256 before = ledger_.head();
    const Hash256 after = page->digest();
    ledger_.append(1, 2, static_cast<std::uint64_t>(head), before, after);
    return child;
}

bool GlobalTopology::has_chart(const PageId& id) const { return pages_.contains(id); }

HeadArray GlobalTopology::head_array(const PageId& chart) {
    auto page = pages_.resolve(chart);
    if (!page) throw std::runtime_error("chart not found");
    return HeadArray(*page, chart);
}

std::vector<PageId> GlobalTopology::charts() const { return pages_.pages(); }

bool GlobalTopology::read_bit(const BitAddress& address, bool& out) const {
    return pages_.read_bit(address, out);
}

bool GlobalTopology::write_bit(const BitAddress& address, bool value, bool cow) {
    return pages_.write_bit(address, value, cow);
}

NanCell* GlobalTopology::cell(const PageId& chart, std::uint16_t addr) {
    auto page = pages_.resolve(chart);
    return page ? &page->at_addr(addr) : nullptr;
}

const NanCell* GlobalTopology::cell(const PageId& chart, std::uint16_t addr) const {
    const auto* entry = pages_.entry(chart);
    return entry ? &entry->page->at_addr(addr) : nullptr;
}

BitAddress GlobalTopology::mirror(const BitAddress& address) {
    BitAddress out = address;
    out.cell = reverse16(address.cell);
    return out;
}

Hash256 GlobalTopology::global_digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'G', 'L', 'O', 'B', '1'};
    h.update(tag, sizeof(tag));
    const Hash256 pages = pages_.root_hash();
    const Hash256 hy = hypergraph_.digest();
    const Hash256 tm = temporal_.digest();
    const Hash256 lg = ledger_.head();
    const Hash256 ck = clock_.digest();
    h.update(pages.data(), pages.size());
    h.update(hy.data(), hy.size());
    h.update(tm.data(), tm.size());
    h.update(lg.data(), lg.size());
    h.update(ck.data(), ck.size());
    return h.final();
}

Event GlobalTopology::commit(std::uint8_t actor, std::uint8_t kind, std::uint64_t addr,
                             Hash256 before, Hash256 after) {
    return ledger_.append(actor, kind, addr, before, after);
}

} // namespace nanlm
