#include "nanlm/ncr.hpp"
#include "test_util.hpp"

using namespace nanlm;

namespace {
ClusterProfile make_cluster(std::uint16_t universe, int systems, Arch arch,
                            std::uint32_t cores = 8, std::uint64_t ram = 16ull << 30) {
    ClusterProfile c;
    c.universe = universe;
    c.arch = arch;
    c.generation = 1;
    for (int i = 0; i < systems; ++i) {
        SystemProfile s;
        s.id = static_cast<std::uint32_t>(i);
        s.arch = arch;
        s.cores = cores;
        s.ram_bytes = ram;
        s.storage_bytes = 1ull << 40;
        s.bandwidth_bps = 1ull << 30;
        s.available = true;
        c.systems.push_back(s);
    }
    return c;
}
} // namespace

int main() {
    PlacementPolicy p;

    ClusterRuntime one;
    one.load(make_cluster(7, 256, Arch::X86));
    auto r = one.place(p);
    CHECK(r.ok);
    CHECK_EQ(r.placements.size(), 256u);
    CHECK(one.validate());
    CHECK_EQ(one.head_count_on(0), 1u);
    CHECK_EQ(one.head_count_on(255), 1u);

    ClusterRuntime small;
    small.load(make_cluster(8, 64, Arch::Arm));
    auto rs = small.place(p);
    CHECK(rs.ok);
    CHECK_EQ(rs.placements.size(), 256u);
    CHECK_EQ(small.head_count_on(0), 4u);
    CHECK(small.validate());

    ClusterRuntime big;
    big.load(make_cluster(9, 512, Arch::X86));
    auto rb = big.place(p);
    CHECK(rb.ok);
    CHECK_EQ(rb.placements.size(), 256u);
    CHECK_EQ(big.head_count_on(300), 0u);

    ClusterProfile mixed = make_cluster(10, 100, Arch::X86);
    ClusterProfile arm = make_cluster(10, 156, Arch::Arm);
    for (auto& s : arm.systems) {
        s.id += 100;
        mixed.systems.push_back(s);
    }
    mixed.arch = Arch::Mixed;
    ClusterRuntime mixed_rt;
    mixed_rt.load(mixed);
    auto rm = mixed_rt.place(p);
    CHECK(rm.ok);
    CHECK(mixed_rt.validate());

    ClusterProfile weak = make_cluster(11, 8, Arch::X86, 1, 1ull << 20);
    ClusterRuntime weak_rt;
    weak_rt.load(weak);
    PlacementPolicy heavy;
    heavy.head_cores = 2;
    CHECK(!weak_rt.place(heavy).ok);

    // Two-phase handoff ownership.
    ClusterRuntime h;
    h.load(make_cluster(12, 256, Arch::X86));
    CHECK(h.place(p).ok);
    const auto old_owner = h.owner(0);
    CHECK(old_owner.has_value());
    const std::uint32_t to = (*old_owner + 1) % 256;
    std::string err;
    const HandoffTicket t = h.begin_handoff(0, to, 1, 2, &err);
    CHECK(t.valid);
    CHECK(!h.begin_handoff(0, to, 1, 2, &err).valid); // pending duplicate
    CHECK(h.commit_handoff(t, &err));
    CHECK_EQ(h.owner(0).value(), to);
    CHECK_EQ(h.generation(0), 2u);
    CHECK(!h.begin_handoff(0, to, 1, 2, &err).valid); // stale generation
    CHECK(h.validate());

    // Failover preserves the head generation.
    const std::uint32_t down = h.owner(0).value();
    std::vector<RecoveryEvent> events;
    CHECK(h.fail_system(down, p, &events, &err));
    CHECK(h.owner(0).has_value());
    CHECK(!(h.owner(0).value() == down));
    CHECK_EQ(h.generation(0), 2u);
    CHECK(h.validate());

    // Migration plan to a compatible cluster.
    ClusterProfile dest = make_cluster(12, 256, Arch::Arm);
    const MigrationPlan plan = h.plan_migration(dest, p);
    CHECK(plan.ok);
    CHECK_EQ(plan.heads.size(), 256u);
    CHECK_EQ(plan.generation, h.cluster().generation);

    return test_done("NaN cluster runtime");
}
