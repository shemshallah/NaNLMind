#include "nanlm/supercluster.hpp"
#include "test_util.hpp"

using namespace nanlm;

namespace {
SuperclusterProfile make_super(std::uint16_t universe, int clusters, int systems) {
    SuperclusterProfile sc;
    sc.universe = universe;
    sc.generation = 1;
    for (int c = 0; c < clusters; ++c) {
        ClusterProfile cl;
        cl.universe = static_cast<std::uint16_t>(c);
        cl.arch = (c % 2) ? Arch::Arm : Arch::X86;
        cl.generation = 1;
        for (int s = 0; s < systems; ++s) {
            SystemProfile p;
            p.id = static_cast<std::uint32_t>(s);
            p.arch = cl.arch;
            p.cores = 8;
            p.ram_bytes = 8ull << 30;
            p.available = true;
            cl.systems.push_back(p);
        }
        sc.clusters.push_back(std::move(cl));
    }
    return sc;
}
} // namespace

int main() {
    SuperclusterRuntime sc;
    sc.load(make_super(42, 256, 64));
    PlacementPolicy policy;
    const auto placed = sc.place(policy);
    CHECK(placed.ok);
    CHECK_EQ(placed.regions.size(), 256u);
    CHECK_EQ(placed.systems, 16384u);
    CHECK_EQ(placed.heads, 65536u);
    CHECK(sc.validate());
    CHECK_EQ(sc.total_systems(), 16384u);
    CHECK_EQ(sc.total_heads(), 65536u);
    CHECK_EQ(sc.cluster_for_region(0).value(), 0u);
    CHECK_EQ(sc.cluster_for_region(255).value(), 255u);
    CHECK(sc.system_for(0, 0).has_value());
    CHECK(sc.system_for(255, 255).has_value());
    CHECK_EQ(sc.cluster_placements(0).size(), 256u);

    // A failed system reassigns its four heads inside the cluster.
    std::vector<RecoveryEvent> events;
    std::string err;
    CHECK(sc.fail_system(0, 0, policy, &events, &err));
    CHECK_EQ(events.size(), 4u);
    CHECK(sc.validate());

    // A whole region can migrate to another compatible cluster.
    SuperclusterRuntime dest;
    dest.load(make_super(42, 256, 64));
    const MigrationPlan plan = sc.plan_region_migration(0, dest.profile(), policy);
    CHECK(plan.ok);
    CHECK_EQ(plan.heads.size(), 256u);
    CHECK_EQ(plan.generation, sc.profile().generation);

    // Not enough clusters is rejected.
    SuperclusterRuntime bad;
    bad.load(make_super(1, 8, 8));
    CHECK(!bad.place(policy).ok);

    return test_done("two-layer cluster hierarchy");
}
