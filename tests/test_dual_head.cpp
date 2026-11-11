#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <cmath>

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

    // Contrastive triangle model: positive-like shapes score high, negative
    // shapes low, all in the raw guest.
    {
        std::array<std::int32_t, 3> sides = {100, 100, 100};
        std::int32_t count = 0, score = 0;
        CHECK(vm.triangle_model_reset());
        CHECK(vm.triangle_model_observe(sides, 500, 1000, 1, count));
        CHECK(vm.triangle_model_observe(sides, 500, 1000, 1, count));
        CHECK(vm.triangle_model_observe_negative(sides, 3000, 5000, 1, count));
        CHECK(vm.triangle_model_observe_negative(sides, 3000, 5000, 1, count));
        CHECK(vm.triangle_model_score_contrastive(sides, 500, 1000, score));
        CHECK(score > 60000);
        CHECK(vm.triangle_model_score_contrastive(sides, 3000, 5000, score));
        CHECK(score < 5000);
    }

    // Global 256-head Hodge: oriented 0->1->2 triangle has zero divergence
    // and curl +3 from canonical pair flows.
    {
        std::array<float, 32640> flows{};
        flows[0] = 1.0f;    // 0 -> 1
        flows[255] = 1.0f;  // 1 -> 2
        flows[1] = -1.0f;   // low 0 -> high 2, so 2 -> 0 is +1
        std::vector<std::array<std::uint32_t, 3>> faces = {{{0, 1, 2}}};
        std::array<float, 256> divergence{};
        std::array<float, 16> curl{};
        const bool hodge_ok = vm.global_hodge(flows, faces, divergence, curl);
        if (!hodge_ok) std::cerr << "hodge error: " << vm.error() << "\n";
        CHECK(hodge_ok);
        CHECK(std::fabs(curl[0] - 3.0f) < 1e-5f);
        for (float value : divergence) CHECK(std::fabs(value) < 1e-6f);

        std::vector<std::int32_t> q16_flows(32640, 0);
        q16_flows[0] = 65536;
        q16_flows[255] = 65536;
        q16_flows[1] = -65536;
        std::array<float, 256> q16_divergence{};
        std::array<float, 16> q16_curl{};
        CHECK(vm.global_hodge_q16(q16_flows, faces, q16_divergence,
                                  q16_curl));
        CHECK(std::fabs(q16_curl[0] - 3.0f) < 1e-5f);
    }

    return test_done("dual-head self-modification");
}
