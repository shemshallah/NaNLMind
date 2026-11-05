#include "nanlm/global.hpp"
#include "test_util.hpp"

using namespace nanlm;

namespace {
Hash256 make_hash(std::uint8_t v) {
    Hash256 h{};
    h[0] = v;
    return h;
}
} // namespace

int main() {
    GlobalTopology g(0x1234);
    CHECK_EQ(g.chart_count(), 1u);
    CHECK(g.has_chart(PageId::root()));
    CHECK(g.ledger().verify());
    const Hash256 genesis = g.global_digest();
    CHECK(genesis == GlobalTopology(0x1234).global_digest());

    // The initial brain is one chart with 256 heads and 32,640 edges.
    auto root = g.pages().resolve(PageId::root());
    CHECK(root != nullptr);
    if (root) {
        std::uint32_t heads = 0;
        std::uint32_t edges = 0;
        for (int a = 0; a < 256; ++a) {
            if (root->head_cell(static_cast<std::uint8_t>(a)).is_head()) ++heads;
            for (int b = a + 1; b < 256; ++b) {
                if (root->adjacent(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b))) ++edges;
            }
        }
        CHECK_EQ(heads, 256u);
        CHECK_EQ(edges, 32640u);
    }

    // Grow the same object by adding coordinate regions. This is not a new
    // topology and not a new ledger.
    const PageId child = g.add_chart(PageId::root(), 7);
    CHECK(g.has_chart(child));
    CHECK_EQ(g.chart_count(), 2u);
    CHECK_EQ(g.ledger().size(), 1u);
    const Hash256 after_child = g.global_digest();
    CHECK(!(genesis == after_child));

    const PageId grand = g.add_chart(child, 3);
    CHECK(g.has_chart(grand));
    CHECK_EQ(g.chart_count(), 3u);
    CHECK_EQ(grand.depth, 2u);

    // Bit addressing works across the one object.
    const BitAddress root_bit{PageId::root(), matrix_addr(0, 1), 0, 4};
    const BitAddress child_bit{child, matrix_addr(1, 2), 1, 9};
    CHECK(g.write_bit(root_bit, true));
    CHECK(g.write_bit(child_bit, true));
    bool rv = false, cv = false;
    CHECK(g.read_bit(root_bit, rv));
    CHECK(g.read_bit(child_bit, cv));
    CHECK(rv && cv);

    // A cross-space hyperedge is a first-class relation of the one object.
    Hyperedge e;
    e.label = 0x5150;
    e.epoch = 1;
    e.members = {Ref::from_bit(root_bit), Ref::from_bit(child_bit)};
    const std::uint32_t eid = g.hypergraph().add(e);
    CHECK(eid != 0);
    CHECK_EQ(g.hypergraph().size(), 1u);
    CHECK_EQ(g.hypergraph().neighbors(Ref::from_bit(root_bit)).size(), 1u);
    CHECK((g.hypergraph().get(eid)->flags & kHyperCrossSpace) != 0);

    // A temporal link is part of the same global state.
    const std::uint32_t tid =
        g.temporal().link(Ref::from_bit(root_bit), Ref::from_bit(child_bit), 1, kTemporalBranch);
    CHECK(tid != 0);
    Ref future;
    CHECK(g.temporal().forward(Ref::from_bit(root_bit), future, 1));
    CHECK(future == Ref::from_bit(child_bit));

    // The palindrome involution is local to a chart and pairs orientations.
    const BitAddress before_mirror{child, matrix_addr(11, 23), 2, 5};
    const BitAddress after_mirror = GlobalTopology::mirror(before_mirror);
    CHECK_EQ(after_mirror.cell, matrix_addr(23, 11));
    CHECK_EQ(canonical16(before_mirror.cell), canonical16(after_mirror.cell));
    CHECK(after_mirror.page == before_mirror.page);

    // One global ledger for the whole object.
    const Hash256 before_event = g.global_digest();
    g.commit(1, 3, 0, make_hash(1), make_hash(2));
    CHECK_EQ(g.ledger().size(), 3u); // two chart events + one explicit event
    CHECK(g.ledger().verify());
    CHECK(!(before_event == g.global_digest()));

    // Deterministic replay of the same construction yields one identity.
    GlobalTopology g2(0x1234);
    g2.add_chart(PageId::root(), 7);
    g2.add_chart(PageId::child(PageId::root(), 7), 3);
    g2.write_bit(root_bit, true);
    g2.write_bit(child_bit, true);
    g2.hypergraph().add(e);
    g2.temporal().link(Ref::from_bit(root_bit), Ref::from_bit(child_bit), 1, kTemporalBranch);
    g2.commit(1, 3, 0, make_hash(1), make_hash(2));
    CHECK(g.global_digest() == g2.global_digest());

    // Cell access through the one object.
    CHECK(g.cell(PageId::root(), matrix_addr(0, 1)) != nullptr);
    CHECK(g.cell(PageId::child(PageId::root(), 99), matrix_addr(0, 1)) == nullptr);

    return test_done("one global topology");
}
