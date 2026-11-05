#include "nanlm/hypergraph.hpp"
#include "test_util.hpp"

#include <memory>
#include <unordered_map>

using namespace nanlm;

int main() {
    PageTable table;
    auto root = std::make_shared<Universe>(0);
    auto child = std::make_shared<Universe>(1);
    table.map(PageId::root(), root);
    const PageId c1 = PageId::child(PageId::root(), 1);
    const PageId c2 = PageId::child(PageId::root(), 2);
    table.map(c1, child);
    table.map(c2, child);

    const Ref a = Ref::from_bit({PageId::root(), matrix_addr(0, 1), 0, 3});
    const Ref b = Ref::from_bit({c1, matrix_addr(1, 9), 1, 11});
    const Ref c = Ref::from_bit({c2, matrix_addr(9, 20), 2, 31});
    const Ref d = Ref::from_bit({PageId::root(), matrix_addr(0, 2), 0, 4});

    Hypergraph hg;
    Hyperedge e;
    e.flags = kHyperTemporal;
    e.label = 0xCAFE;
    e.epoch = 7;
    e.members = {a, b, c};
    const std::uint32_t id = hg.add(e);
    CHECK(id != 0);
    CHECK_EQ(hg.size(), 1u);

    const Hyperedge* got = hg.get(id);
    CHECK(got != nullptr);
    if (got) {
        CHECK_EQ(got->members.size(), 3u);
        CHECK((got->flags & kHyperCrossSpace) != 0);
        CHECK_EQ(got->epoch, 7u);
    }

    CHECK_EQ(hg.incident(a).size(), 1u);
    CHECK_EQ(hg.incident(b).size(), 1u);
    const auto neighbors = hg.neighbors(a);
    CHECK_EQ(neighbors.size(), 2u);
    CHECK_EQ(hg.members_of(id).size(), 3u);

    CHECK_EQ(hg.at_epoch(7).size(), 1u);
    CHECK_EQ(hg.at_epoch(8).size(), 0u);
    CHECK_EQ(hg.between(6, 8).size(), 1u);
    CHECK_EQ(hg.between(7, 8).size(), 1u);

    // A second hyperedge, and a temporal frame.
    Hyperedge e2;
    e2.label = 0xBEEF;
    e2.epoch = 8;
    e2.members = {b, d};
    const std::uint32_t id2 = hg.add(e2);
    CHECK(id2 != 0);
    CHECK_EQ(hg.size(), 2u);
    CHECK_EQ(hg.neighbors(b).size(), 3u); // a, c, d

    Hypergraph hg2;
    hg2.add(e);
    hg2.add(e2);
    CHECK(hg.digest() == hg2.digest());

    // Hypergraph diffusion preserves the energy map's support and bounds.
    std::unordered_map<Ref, std::int32_t, RefHash> energy;
    energy[a] = 65536;
    energy[b] = 32768;
    energy[c] = 16384;
    const auto next = hg.diffuse(energy);
    CHECK_EQ(next.size(), energy.size());
    for (const auto& kv : next) {
        CHECK(kv.second >= 0);
        CHECK(kv.second <= (1 << 20));
    }

    // The same physical cell can be named through either orientation. The
    // refs are distinct (direction matters) even though the cell is shared.
    const Ref forward = Ref::from_bit({PageId::root(), matrix_addr(3, 9), 0, 0});
    const Ref reverse = Ref::from_bit({PageId::root(), matrix_addr(9, 3), 0, 0});
    CHECK(!(forward == reverse));
    CHECK_EQ(canonical16(matrix_addr(3, 9)), canonical16(matrix_addr(9, 3)));
    CHECK_EQ(reverse16(matrix_addr(3, 9)), matrix_addr(9, 3));

    CHECK(hg.remove(id));
    CHECK_EQ(hg.size(), 1u);
    CHECK(!hg.remove(id));
    CHECK_EQ(hg.incident(a).size(), 0u);

    const auto wire = hg.serialize();
    auto restored = Hypergraph::from_bytes(wire.data(), wire.size());
    CHECK_EQ(restored.size(), hg.size());
    CHECK(restored.digest() == hg.digest());
    auto truncated = wire; truncated.pop_back();
    CHECK_EQ(Hypergraph::from_bytes(truncated.data(), truncated.size()).size(), 0u);

    return test_done("palindromic temporal hypergraph");
}
