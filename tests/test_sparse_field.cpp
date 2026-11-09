#include "nanlm/sparse_field.hpp"
#include "test_util.hpp"

#include <bit>
#include <cstring>
#include <memory>

using namespace nanlm;

int main() {
    static_assert(kSparseMaxDim == 512);
    static_assert(kSparseMaxRank == 4);
    static_assert(kSparseHeads == 255);
    static_assert(kSparseActive == 8);
    static_assert(sizeof(SparseFieldState) <= 2'400'000);

    auto u = std::make_unique<Universe>(0x5A17F1E1D0C0B0A0ull);
    SparseField field(*u);
    CHECK(field.configure(64, 4, 8));
    CHECK_EQ(field.dim(), 64u);
    CHECK_EQ(field.rank(), 4u);
    field.seed(0x1234);
    CHECK(field.seeded());

    SparseField::Feature x{};
    for (std::size_t i = 0; i < field.dim(); ++i) {
        x[i] = static_cast<std::int32_t>((i + 1) * 4096);
    }
    SparseField::Result result;
    CHECK(field.forward(x, result));
    CHECK_EQ(result.count, SparseField::kActive);

    std::size_t unique = 0;
    std::size_t mask_bits = 0;
    for (std::size_t slot = 0; slot < result.count; ++slot) {
        bool seen = false;
        for (std::size_t prior = 0; prior < slot; ++prior) {
            if (result.heads[prior] == result.heads[slot]) seen = true;
        }
        if (!seen) ++unique;
    }
    for (std::uint64_t word : result.mask) {
        mask_bits += static_cast<std::size_t>(std::popcount(word));
    }
    CHECK_EQ(unique, result.count);
    CHECK_EQ(mask_bits, result.count);

    std::int64_t weight_sum = 0;
    for (std::size_t slot = 0; slot < result.count; ++slot) {
        weight_sum += result.weights[slot];
        CHECK(result.heads[slot] < kSparseHeads);
    }
    CHECK(weight_sum > 60000);
    CHECK(weight_sum <= 65536);

    // Forward must not modify adapter/router weights; only usage counters.
    const SparseFieldState before = u->sparse_field();
    SparseField::Result second;
    CHECK(field.forward(x, second));
    for (std::size_t h = 0; h < kSparseHeads; ++h) {
        CHECK_EQ(std::memcmp(before.down[h], u->sparse_field().down[h],
                             sizeof(before.down[h])), 0);
        CHECK_EQ(std::memcmp(before.up[h], u->sparse_field().up[h],
                             sizeof(before.up[h])), 0);
        CHECK_EQ(std::memcmp(before.router[h], u->sparse_field().router[h],
                             sizeof(before.router[h])), 0);
        CHECK_EQ(before.hotspot[h], u->sparse_field().hotspot[h]);
    }

    // A local credit update changes only the selected head's adapter.
    const std::uint8_t active = result.heads[0];
    SparseFieldState prior = u->sparse_field();
    CHECK(field.update(active, x, 512));
    for (std::size_t h = 0; h < kSparseHeads; ++h) {
        if (h == active) {
            CHECK(std::memcmp(prior.down[h], u->sparse_field().down[h],
                              sizeof(prior.down[h])) != 0);
        } else {
            CHECK_EQ(std::memcmp(prior.down[h], u->sparse_field().down[h],
                                 sizeof(prior.down[h])), 0);
        }
    }

    // The maximum d=512, rank-4 sidecar layout is reachable in the same field.
    CHECK(field.configure(512, 4, 8));
    CHECK_EQ(field.dim(), 512u);
    field.seed(0x9999);
    SparseField::Feature wide{};
    for (std::size_t i = 0; i < field.dim(); ++i) {
        wide[i] = static_cast<std::int32_t>((i % 17) * 1024);
    }
    SparseField::Result wide_result;
    CHECK(field.forward(wide, wide_result));
    CHECK_EQ(wide_result.count, SparseField::kActive);

    // Hotspots use the adaptive triad mapping, not fixed h/3 groups.
    auto adaptive = std::make_unique<Universe>(0x1111222233334444ull);
    SparseField adaptive_field(*adaptive);
    CHECK(adaptive_field.configure(32, 4, 8));
    adaptive_field.seed(7);
    adaptive->triad_members()[0] = 10;
    adaptive->triad_members()[1] = 100;
    adaptive->triad_members()[2] = 200;
    std::array<std::int16_t, kSparseHeads> credits{};
    credits[10] = credits[100] = credits[200] = 100;
    const auto hotspots = adaptive_field.update_hotspots(credits, 10, 10);
    CHECK(hotspots.triads[0] == 1);
    CHECK(hotspots.heads[10] == 1);
    CHECK(hotspots.heads[100] == 1);
    CHECK(hotspots.heads[200] == 1);

    // 42 hot triads do not pass the 43/85 field gate; 43 do.
    auto gate_u = std::make_unique<Universe>(0xAAAABBBBCCCCDDDDull);
    SparseField gate(*gate_u);
    CHECK(gate.configure(16, 4, 8));
    gate.seed(11);
    std::array<std::int16_t, kSparseHeads> gate_credits{};
    for (std::size_t t = 0; t < 42; ++t) {
        for (std::size_t slot = 0; slot < kTriadSize; ++slot) {
            gate_credits[gate_u->triad_members()[t * kTriadSize + slot]] = 100;
        }
    }
    auto gate_result = gate.update_hotspots(gate_credits, 10, 10);
    CHECK_EQ(gate_result.hot_triads, 42u);
    CHECK(!gate_result.field_hot);
    for (std::size_t slot = 0; slot < kTriadSize; ++slot) {
        gate_credits[gate_u->triad_members()[42 * kTriadSize + slot]] = 100;
    }
    gate_result = gate.update_hotspots(gate_credits, 10, 10);
    CHECK_EQ(gate_result.hot_triads, 43u);
    CHECK(gate_result.field_hot);

    // Persistence is one chart identity: serialization restores the bank and
    // the digest matches.
    const auto bytes = u->serialize();
    auto restored = Universe::from_bytes(bytes.data(), bytes.size());
    CHECK(restored != nullptr);
    if (restored) {
        CHECK(restored->digest() == u->digest());
        CHECK_EQ(std::memcmp(&restored->sparse_field(), &u->sparse_field(),
                             sizeof(SparseFieldState)), 0);
    }

    // Older snapshots without the trailing bank restore to a zeroed bank.
    auto legacy = bytes;
    CHECK(legacy.size() > sizeof(SparseFieldState));
    legacy.resize(legacy.size() - sizeof(SparseFieldState));
    auto old = Universe::from_bytes(legacy.data(), legacy.size());
    CHECK(old != nullptr);
    if (old) {
        CHECK_EQ(old->sparse_field().flags & 1u, 0u);
    }

    return test_done("native sparse head/field bank");
}
