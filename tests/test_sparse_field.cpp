#include "nanlm/sparse_field.hpp"
#include "test_util.hpp"

#include <bit>
#include <cstring>
#include <memory>

using namespace nanlm;

int main() {
    static_assert(kSparseDim == 8);
    static_assert(kSparseHeads == 255);
    static_assert(kSparseActive == 8);
    static_assert(sizeof(SparseFieldState) <= 32768);

    auto u = std::make_unique<Universe>(0x5A17F1E1D0C0B0A0ull);
    SparseField field(*u);
    field.seed(0x1234);
    CHECK(field.seeded());
    CHECK_EQ(field.state().flags & 1u, 1u);

    SparseField::Feature x{};
    for (std::size_t i = 0; i < x.size(); ++i) {
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

    // Hotspot promotion is triad-wide: 3 heads, not one.
    std::array<std::int16_t, kSparseHeads> credits{};
    credits[6] = credits[7] = credits[8] = 100;
    field.update_hotspots(credits, 10);
    CHECK(u->sparse_field().hotspot[6] > 0);
    CHECK(u->sparse_field().hotspot[7] > 0);
    CHECK(u->sparse_field().hotspot[8] > 0);
    CHECK_EQ(u->sparse_field().hotspot[9], 0);

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
