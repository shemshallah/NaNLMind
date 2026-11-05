// One global topology.
//
// This is the central design constraint: there is exactly one mathematical
// object, not a federation of per-head or per-shard brains. A 4 MiB universe
// is a *local coordinate chart* of that object, not a separate computer. The
// atlas of charts, the hypergraph, the temporal memory, and the ledger are all
// fields of the same global state.
//
// Distribution is a placement/caching concern. Replicas host regions of this
// object; they do not own independent minds and there is no external semantic
// coordinator. Identity is the global digest.
#pragma once

#include "nanlm/clock.hpp"
#include "nanlm/hypergraph.hpp"
#include "nanlm/head.hpp"
#include "nanlm/ledger.hpp"
#include "nanlm/pager.hpp"
#include "nanlm/temporal.hpp"
#include "nanlm/universe.hpp"

#include <cstdint>
#include <memory>
#include <vector>

namespace nanlm {

class GlobalTopology {
public:
    GlobalTopology();
    explicit GlobalTopology(std::uint64_t genome);

    // The initial brain is one chart: the root universe. Adding a chart adds a
    // coordinate region to the same object; it does not create a new topology.
    PageId add_chart(const PageId& parent, std::uint8_t head, std::uint64_t genome = 0);
    bool has_chart(const PageId& id) const;
    std::vector<PageId> charts() const;
    std::size_t chart_count() const { return pages_.size(); }

    // Global address views. The chart path selects the local coordinate
    // region; the 16-bit cell address is canonicalized inside that chart.
    bool read_bit(const BitAddress& address, bool& out) const;
    bool write_bit(const BitAddress& address, bool value, bool cow = true);
    NanCell* cell(const PageId& chart, std::uint16_t addr);
    const NanCell* cell(const PageId& chart, std::uint16_t addr) const;

    // The palindrome involution is local to a chart. It maps a cell to its
    // mirror orientation in the same global object.
    static BitAddress mirror(const BitAddress& address);

    // All relations are fields of the one object.
    Hypergraph& hypergraph() { return hypergraph_; }
    const Hypergraph& hypergraph() const { return hypergraph_; }
    BidirectionalMemory& temporal() { return temporal_; }
    const BidirectionalMemory& temporal() const { return temporal_; }
    Ledger& ledger() { return ledger_; }
    const Ledger& ledger() const { return ledger_; }
    TemporalClock& clock() { return clock_; }
    const TemporalClock& clock() const { return clock_; }
    PageTable& pages() { return pages_; }
    const PageTable& pages() const { return pages_; }

    // The 256-Head Array of one chart. The initial brain is the root chart;
    // the returned view shares the one Universe and does not own state.
    HeadArray head_array(const PageId& chart);
    HeadArray root_heads() { return head_array(PageId::root()); }

    // One identity for the whole object: chart hashes + hypergraph + temporal
    // memory + ledger head.
    Hash256 global_digest() const;

    // Explicit committed event. The caller supplies the before/after state
    // hashes; the global ledger is the single history.
    Event commit(std::uint8_t actor, std::uint8_t kind, std::uint64_t addr,
                 Hash256 before, Hash256 after);

private:
    PageTable pages_;
    Hypergraph hypergraph_;
    BidirectionalMemory temporal_;
    Ledger ledger_;
    TemporalClock clock_;
};

} // namespace nanlm
