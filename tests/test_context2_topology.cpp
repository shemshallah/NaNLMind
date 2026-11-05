#include "nanlm/context2_topology.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    GlobalTopology g(0x1234);
    Context2Topology ctx(g, PageId::root());
    std::string err;

    CHECK(ctx.observe('A', 'B', 'C', 5));
    CHECK(ctx.observe('A', 'B', 'D', 2));
    CHECK(ctx.observe('A', 'C', 'E', 3));
    CHECK(ctx.observe('B', 'C', 'F', 4));
    CHECK_EQ(ctx.count('A', 'B', 'C'), 5u);
    CHECK_EQ(ctx.count('A', 'B', 'D'), 2u);
    CHECK_EQ(ctx.predict('A', 'B'), static_cast<std::uint8_t>('C'));
    CHECK_EQ(ctx.predict('A', 'C'), static_cast<std::uint8_t>('E'));
    CHECK_EQ(ctx.predict('B', 'C'), static_cast<std::uint8_t>('F'));
    CHECK_EQ(ctx.universes(), 2u);
    CHECK_EQ(g.chart_count(), 3u); // root + A + B
    CHECK(g.ledger().verify());
    CHECK(g.manifest().generation >= 2u);

    auto child = g.pages().resolve(ctx.universe('A'));
    CHECK(child != nullptr);
    if (child) CHECK(child->verify(&err));
    CHECK(ctx.universe('A').depth == 1u);
    CHECK(ctx.universe('A').path[0] == static_cast<std::uint8_t>('A'));

    // Missing context is empty.
    CHECK_EQ(ctx.count('Z', 'Z', 'Z'), 0u);
    CHECK_EQ(ctx.predict('Z', 'Z'), 0u);

    return test_done("context-2 child-universe memory");
}
