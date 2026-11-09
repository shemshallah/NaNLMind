#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <array>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    if (!vm.ready()) return test_done("raw NaN16 field VM bridge");

    RawProposalResult proposal;
    CHECK(vm.proposal(0x0001, 0x0003, {0x0001, 0x0002, 0x0002},
                      0, 0, true, proposal));
    CHECK_EQ(proposal.votes, 6u);
    CHECK(proposal.accepted);
    CHECK_EQ(proposal.candidate_mask, 0x0002u);
    CHECK_EQ(proposal.candidate_rule, 1u);

    std::array<std::uint8_t, kTriadCount> masks{};
    for (std::size_t i = 0; i < 43; ++i) masks[i] = 6;
    std::uint16_t count = 0;
    bool field_ok = false;
    CHECK(vm.field_vote(masks, count, field_ok));
    CHECK_EQ(count, 43u);
    CHECK(field_ok);

    std::array<std::uint16_t, kTriadMemberCount> phases{};
    std::int32_t coherence = 0;
    CHECK(vm.coherence(phases, coherence));
    CHECK(coherence >= 65500);

    std::array<std::uint16_t, 6> remap_masks = {
        0x8000, 0, 0, 0x8000, 0, 0};
    bool improved = false;
    std::int32_t before = 0, after = 0;
    CHECK(vm.remap(remap_masks, 0, 0, true, improved, before, after));
    CHECK(improved);
    CHECK_EQ(before, 2);
    CHECK_EQ(after, 4);

    // Chart bridge: the guest decision changes only the proposer's mask and
    // updates the chart's integer credit fields.
    Universe universe;
    HeadArray heads(universe, PageId::root());
    CHECK(heads.at(3).set_boolean_mask(0x0001));
    CHECK(heads.at(4).set_boolean_mask(0x0002));
    CHECK(heads.at(5).set_boolean_mask(0x0002));
    RawProposalResult chart_result;
    CHECK(vm.propose(universe, heads, 3, 0x0003, 0, 0, true, chart_result));
    CHECK(chart_result.accepted);
    CHECK_EQ(heads.at(3).boolean_mask(), 0x0002u);
    CHECK_EQ(heads.at(4).boolean_mask(), 0x0002u);
    CHECK_EQ(heads.at(5).boolean_mask(), 0x0002u);
    CHECK_EQ(universe.head_credit()[3], 1);
    CHECK_EQ(universe.triad_credit()[1], 1);

    // General remap bridge: swap a member between triads only when the raw
    // guest says the combined majority objective improves.
    Universe map_universe;
    HeadArray map_heads(map_universe, PageId::root());
    CHECK(map_heads.at(3).set_boolean_mask(0x8000));
    CHECK(map_heads.at(4).set_boolean_mask(0x0000));
    CHECK(map_heads.at(5).set_boolean_mask(0x0000));
    CHECK(map_heads.at(6).set_boolean_mask(0x8000));
    CHECK(map_heads.at(7).set_boolean_mask(0x0000));
    CHECK(map_heads.at(8).set_boolean_mask(0x0000));
    bool chart_improved = false;
    std::int32_t chart_before = 0, chart_after = 0;
    CHECK(vm.remap_chart(map_universe, map_heads, 1, 1, 2, 0, 0, 0, true,
                         chart_improved, chart_before, chart_after));
    CHECK(chart_improved);
    CHECK_EQ(map_universe.triad_of()[6], 1);
    CHECK_EQ(map_universe.triad_slot()[6], 1);
    CHECK_EQ(map_universe.triad_of()[4], 2);
    CHECK_EQ(map_universe.triad_slot()[4], 0);
    CHECK_EQ(map_universe.triad_credit()[1], 1);
    CHECK_EQ(map_universe.triad_credit()[2], 1);

    // Deterministic autonomous scheduler: lowest-credit triads are tried.
    Universe auto_universe;
    HeadArray auto_heads(auto_universe, PageId::root());
    CHECK(auto_heads.at(3).set_boolean_mask(0x8000));
    CHECK(auto_heads.at(4).set_boolean_mask(0x0000));
    CHECK(auto_heads.at(5).set_boolean_mask(0x0000));
    CHECK(auto_heads.at(6).set_boolean_mask(0x8000));
    CHECK(auto_heads.at(7).set_boolean_mask(0x0000));
    CHECK(auto_heads.at(8).set_boolean_mask(0x0000));
    auto_universe.triad_credit()[1] = -5;
    auto_universe.triad_credit()[2] = -4;
    AutoRemapResult auto_result;
    CHECK(vm.auto_remap(auto_universe, auto_heads, 256, 0, 0, true,
                        auto_result));
    CHECK(auto_result.attempted);
    CHECK(auto_result.improved);
    CHECK_EQ(auto_result.triad_a, 1);
    CHECK_EQ(auto_result.triad_b, 2);
    CHECK_EQ(auto_result.slot_a, 1);
    CHECK_EQ(auto_result.slot_b, 0);
    CHECK_EQ(auto_universe.triad_of()[6], 1);
    CHECK_EQ(auto_universe.triad_of()[4], 2);

    // Raw hot-head scan: three hot individuals become one hot triad, and the
    // guest writes a unique 85x3 auto-mapping.
    std::array<std::int32_t, kTriadMemberCount> credits{};
    credits[3] = 100;
    credits[17] = 90;
    credits[99] = 80;
    HotTriheadResult hot;
    CHECK(vm.hot_triheads(credits, 10, hot));
    CHECK_EQ(hot.hot_heads, 3u);
    CHECK_EQ(hot.hot_triads, 1u);
    CHECK(!hot.field_hot);
    CHECK_EQ(hot.members[0], 3u);
    CHECK_EQ(hot.members[1], 17u);
    CHECK_EQ(hot.members[2], 99u);
    std::array<bool, kTriadMemberCount> seen{};
    for (std::uint8_t h : hot.members) {
        CHECK(h < kTriadMemberCount);
        CHECK(!seen[h]);
        seen[h] = true;
    }

    // 129 hot heads -> 43 complete hot triads -> global field flag.
    std::array<std::int32_t, kTriadMemberCount> many{};
    for (std::size_t i = 0; i < 129; ++i) many[i] = 50;
    CHECK(vm.hot_triheads(many, 10, hot));
    CHECK_EQ(hot.hot_heads, 129u);
    CHECK_EQ(hot.hot_triads, 43u);
    CHECK(hot.field_hot);

    // Chart bridge commits the raw mapping and reverses it for all heads.
    Universe hot_universe;
    HotTriheadResult mapped;
    CHECK(vm.hot_triheads(hot_universe, credits, 10, mapped));
    CHECK(mapped.mapped);
    CHECK_EQ(hot_universe.triad_members()[0], 3u);
    CHECK_EQ(hot_universe.triad_members()[1], 17u);
    CHECK_EQ(hot_universe.triad_members()[2], 99u);
    CHECK_EQ(hot_universe.triad_of()[3], 0u);
    CHECK_EQ(hot_universe.triad_of()[17], 0u);
    CHECK_EQ(hot_universe.triad_of()[99], 0u);
    CHECK_EQ(hot_universe.triad_slot()[99], 2u);

    return test_done("raw NaN16 field VM bridge");
}
