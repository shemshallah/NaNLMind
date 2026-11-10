#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    if (!vm.ready()) return test_done("dual-head self-modification");

    Universe universe;
    HeadArray heads(universe, PageId::root());
    CHECK(heads.at(3).set_boolean_mask(0x0001));
    CHECK(heads.at(4).set_boolean_mask(0x0002));
    CHECK(heads.at(5).set_boolean_mask(0x0002));
    CHECK(heads.at(6).set_boolean_mask(0x0001));
    CHECK(heads.at(7).set_boolean_mask(0x0002));
    CHECK(heads.at(8).set_boolean_mask(0x0002));

    universe.triad_votes().fill(0);
    for (std::size_t t = 0; t < 43; ++t) universe.triad_votes()[t] = 6;

    DualProposalResult accepted;
    CHECK(vm.propose_dual(universe, heads, 3, 6, 0x0003, 0, 0, true,
                          -65536, accepted));
    CHECK(accepted.fast.accepted);
    CHECK(accepted.slow.accepted);
    CHECK(accepted.field_accepted);
    CHECK(accepted.slow_ok);
    CHECK(accepted.committed);
    CHECK_EQ(accepted.committed_mask, 0x0002u);
    CHECK_EQ(heads.at(3).boolean_mask(), 0x0001u);
    CHECK_EQ(heads.at(6).boolean_mask(), 0x0002u);
    CHECK_EQ(universe.head_credit()[3], 1);
    CHECK_EQ(universe.head_credit()[6], 1);

    // Medium field rejects: the fast proposal cannot durably modify the slow
    // head, even though both Boolean proposals accept.
    Universe gated;
    HeadArray gated_heads(gated, PageId::root());
    CHECK(gated_heads.at(3).set_boolean_mask(0x0001));
    CHECK(gated_heads.at(4).set_boolean_mask(0x0002));
    CHECK(gated_heads.at(5).set_boolean_mask(0x0002));
    CHECK(gated_heads.at(6).set_boolean_mask(0x0001));
    CHECK(gated_heads.at(7).set_boolean_mask(0x0002));
    CHECK(gated_heads.at(8).set_boolean_mask(0x0002));
    gated.triad_votes().fill(0);
    DualProposalResult blocked;
    CHECK(vm.propose_dual(gated, gated_heads, 3, 6, 0x0003, 0, 0, true,
                          -65536, blocked));
    CHECK(blocked.fast.accepted);
    CHECK(blocked.slow.accepted);
    CHECK(!blocked.field_accepted);
    CHECK(!blocked.committed);
    CHECK_EQ(gated_heads.at(6).boolean_mask(), 0x0001u);

    return test_done("dual-head self-modification");
}
