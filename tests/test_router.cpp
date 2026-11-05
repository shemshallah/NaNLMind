#include "nanlm/router.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    GlobalTopology g(0x1234);
    RouterChart router(g, PageId::root());
    CHECK_EQ(router.universe(3).depth, 1u);
    CHECK(!router.has_universe(3));

    const RouteResult w = router.route(3, 7, PortalOp::WriteForward, 0xDEADBEEFu, 0x5u, 42);
    CHECK(w.ok);
    CHECK(portal_is_write(w.word.op));
    CHECK(portal_is_forward(w.word.op));
    const RouteResult rf = router.read(3, 7, true);
    CHECK(rf.ok);
    CHECK_EQ(rf.word.data, 0xDEADBEEFu);
    CHECK_EQ(rf.word.flags, 0x5u);
    CHECK(rf.word.op == PortalOp::WriteForward);

    // The mirror pair is one physical cell; the reverse rail is separate.
    const RouteResult rw = router.route(7, 3, PortalOp::ReadReverse, 0xCAFEBABEu, 0x2u, 43);
    CHECK(rw.ok);
    const RouteResult rr = router.read(3, 7, false);
    CHECK(rr.ok);
    CHECK_EQ(rr.word.data, 0xCAFEBABEu);
    CHECK_EQ(rr.word.flags, 0x2u);
    CHECK(rr.word.op == PortalOp::ReadReverse);

    // Forward and reverse are independent.
    CHECK_EQ(router.read(3, 7, true).word.data, 0xDEADBEEFu);

    // Open a real child universe on demand.
    CHECK(router.open_universe(3, 0x99));
    CHECK(router.has_universe(3));
    CHECK_EQ(g.chart_count(), 2u);
    CHECK(g.manifest().generation >= 1u);
    CHECK(g.ledger().verify());

    // The router chart remains structurally valid after direct route writes.
    auto page = g.pages().resolve(PageId::root());
    CHECK(page != nullptr);
    if (page) CHECK(page->verify());

    return test_done("meta-router chart");
}
