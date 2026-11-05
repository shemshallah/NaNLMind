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
    manifests_.reset(PageId::root(), pages_.root_hash());
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
    ledger_.append(1, kEventChart, static_cast<std::uint64_t>(head), before, after,
                   clock_.tick());
    publish_manifest(child);
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

void GlobalTopology::publish_manifest(const PageId& changed) {
    Manifest current = manifests_.snapshot();
    Manifest next = current;
    next.generation = current.generation + 1u;
    next.page = changed;
    next.root = pages_.root_hash();
    next.epoch = current.epoch + 1u;
    next.pages = pages_.pages();
    manifests_.publish(next, current.generation);
}

GrowthDecision GlobalTopology::evaluate_growth(const PageId& chart, std::uint8_t head,
                                                const GrowthPolicy& policy) {
    GrowthDecision d;
    d.chart = chart;
    d.head = head;
    auto page = pages_.resolve(chart);
    if (!page) {
        d.reason = "chart not present";
        return d;
    }
    if (chart.depth >= policy.max_depth) {
        d.reason = "max depth reached";
        return d;
    }
    HeadArray heads(*page, chart);
    HeadView h = heads.at(head);
    if (h.has_child()) {
        d.reason = "head already has a child";
        return d;
    }
    if (h.scratch_used() >= policy.scratch_threshold) {
        d.grow = true;
        d.reason = "scratch high-water mark";
        return d;
    }
    if (h.self_error() >= policy.self_error_threshold &&
        h.error_streak() >= policy.error_streak_required) {
        d.grow = true;
        d.reason = "sustained self-model error";
        return d;
    }
    d.reason = "below threshold";
    return d;
}

std::vector<GrowthDecision> GlobalTopology::scan_growth(const PageId& chart,
                                                        const GrowthPolicy& policy) {
    std::vector<GrowthDecision> out;
    for (std::uint32_t i = 0; i < kHeadCount; ++i) {
        GrowthDecision d = evaluate_growth(chart, static_cast<std::uint8_t>(i), policy);
        if (d.grow) out.push_back(d);
    }
    return out;
}

PageId GlobalTopology::grow_head(const PageId& chart, std::uint8_t head,
                                 const GrowthPolicy& policy, std::uint64_t genome) {
    const GrowthDecision d = evaluate_growth(chart, head, policy);
    if (!d.grow) return {};
    const PageId child = add_chart(chart, head, genome);
    if (!(child.depth != 0)) return {};
    auto page = pages_.resolve(chart);
    if (page) {
        HeadArray heads(*page, chart);
        HeadView h = heads.at(head);
        h.mark_grown();
        const Hash256 after = page->digest();
        ledger_.append(1, kEventGrowth, static_cast<std::uint64_t>(head), {}, after,
                       clock_.tick());
        publish_manifest(chart);
    }
    return child;
}

ConsolidationResult GlobalTopology::consolidate(const ScratchJournal& journal,
                                                std::uint8_t actor) {
    return consolidation_.consolidate(journal, actor);
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
    const Hash256 mf = manifests_.snapshot().digest();
    h.update(pages.data(), pages.size());
    h.update(hy.data(), hy.size());
    h.update(tm.data(), tm.size());
    h.update(lg.data(), lg.size());
    h.update(ck.data(), ck.size());
    h.update(mf.data(), mf.size());
    return h.final();
}

Event GlobalTopology::commit(std::uint8_t actor, std::uint8_t kind, std::uint64_t addr,
                             Hash256 before, Hash256 after, std::uint64_t epoch) {
    return ledger_.append(actor, kind, addr, before, after, epoch == 0 ? clock_.tick() : epoch);
}

} // namespace nanlm
