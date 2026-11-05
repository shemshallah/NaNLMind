#include "nanlm/overbootstrap.hpp"
#include "nanlm/bootstrap_layers.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>
#include <vector>

using namespace nanlm;

int main() {
#if defined(__ANDROID__)
    std::cout << "SKIP dense 2 GiB overbootstrap on Android (8 MiB only)\n";
    return 0;
#else
    OverbootstrapMap map;
    CHECK_EQ(map.virtual_bytes(), 2147483648ull);
    CHECK_EQ(map.page_bytes(), 8388608u);
    CHECK_EQ(map.page_count(), 256u);
    CHECK_EQ(map.resident_bytes(), 0ull);
    CHECK_EQ(map.resident_pages(), 0u);

    RunnerMap runner;
    CHECK(runner.initialize(map));
    CHECK_EQ(map.resident_pages(), 2u);
    CHECK_EQ(map.resident_bytes(), 2ull * kOverbootstrapPageBytes);
    CHECK_EQ(runner.universe.page, 0u);
    CHECK_EQ(runner.head_arena.page, 1u);
    CHECK_EQ(runner.heads[0].page, 1u);
    CHECK_EQ(runner.heads[255].page, 1u);
    CHECK_EQ(runner.heads[255].offset, 255u * kHeadRegionBytes);

    // The 8 MiB live runner image is mapped into page 0.
    const std::array<std::uint8_t, 8> live{1, 2, 3, 4, 5, 6, 7, 8};
    CHECK(map.write(runner.universe, 4096, live.data(), live.size()));
    std::array<std::uint8_t, 8> live_out{};
    CHECK(map.read(runner.universe, 4096, live_out.data(), live_out.size()));
    CHECK(live == live_out);

    // 256 head updates are mapped into the 8 MiB head arena in page 1.
    for (std::uint16_t h = 0; h < kOverbootstrapHeadCount; ++h) {
        const std::array<std::uint8_t, 8> update{
            static_cast<std::uint8_t>(h & 0xFFu),
            static_cast<std::uint8_t>(h >> 8),
            static_cast<std::uint8_t>(h * 7u),
            static_cast<std::uint8_t>(h * 13u),
            static_cast<std::uint8_t>(h * 17u),
            static_cast<std::uint8_t>(h * 19u),
            static_cast<std::uint8_t>(h * 23u),
            static_cast<std::uint8_t>(h * 29u)};
        CHECK(runner.write_head(map, h, 0, update.data(), update.size()));
        std::array<std::uint8_t, 8> out{};
        CHECK(runner.read_head(map, h, 0, out.data(), out.size()));
        CHECK(update == out);
    }
    CHECK_EQ(map.resident_pages(), 2u); // all head regions share page 1
    CHECK_EQ(map.dirty_pages(), 2u);
    CHECK(map.commit());
    CHECK_EQ(map.dirty_pages(), 0u);
    CHECK_EQ(map.generation(), 1u);

    // A peer page can be allocated independently and is not resident until used.
    const RegionRef peer{254, 0, kOverbootstrapPageBytes};
    std::array<std::uint8_t, 8> zero_out{};
    CHECK(map.read(peer, 0, zero_out.data(), zero_out.size()));
    for (std::uint8_t b : zero_out) CHECK_EQ(b, 0u);
    CHECK(map.write(peer, 0, live.data(), live.size()));
    CHECK_EQ(map.resident_pages(), 3u);
    CHECK(map.read(peer, 0, live_out.data(), live_out.size()));
    CHECK(live == live_out);

    // Per-layer payload regions start at page 2 and do not overlap the head
    // arena or the peer page.
    LayerPayloadStore layers(map);
    CHECK(layers.allocate(3, 16));
    CHECK(layers.allocate(5, 32));
    CHECK(!layers.allocate(3, 8));
    const std::array<std::uint8_t, 4> payload{9, 8, 7, 6};
    CHECK(layers.write(3, 4, payload.data(), payload.size()));
    std::array<std::uint8_t, 4> payload_out{};
    CHECK(layers.read(3, 4, payload_out.data(), payload_out.size()));
    CHECK(payload == payload_out);
    CHECK(layers.region(3).has_value());
    if (layers.region(3)) CHECK_EQ(layers.region(3)->page, 2u);
    if (layers.region(5)) CHECK_EQ(layers.region(5)->page, 3u);
    CHECK_EQ(map.resident_pages(), 5u); // page0, head arena, peer, layer3, layer5

    // Six-runner ownership of the 256 logical heads: 43,43,43,43,43,41.
    RunnerRing ring;
    const auto counts = ring.counts();
    CHECK_EQ(counts[0], 43u);
    CHECK_EQ(counts[1], 43u);
    CHECK_EQ(counts[2], 43u);
    CHECK_EQ(counts[3], 43u);
    CHECK_EQ(counts[4], 42u);
    CHECK_EQ(counts[5], 42u);
    CHECK_EQ(ring.owner(0), 0u);
    CHECK_EQ(ring.owner(255), 3u);
    CHECK_EQ(ring.owner(256), 0xFFu);

    CHECK(runner.write_head(map, 255, kHeadRegionBytes - 1, live.data(), 1));
    CHECK(!runner.write_head(map, 256, 0, live.data(), live.size()));
    CHECK(!map.write(runner.heads[0], kHeadRegionBytes, live.data(), 1));

    // Train a small sequence, then persist all 256 head vectors through the
    // 2 GiB head arena and read them back.
    HopfieldConfig cfg;
    cfg.top_k = 1;
    HopfieldRouter trained(cfg);
    for (std::uint8_t t = 0; t < 8; ++t) {
        HopfieldRouter::Vector v{};
        v[t % HopfieldRouter::kDim] = 100;
        trained.set_head(t, v);
    }
    const std::array<std::uint8_t, 8> seq{0, 1, 2, 3, 4, 5, 6, 7};
    for (int epoch = 0; epoch < 10; ++epoch) {
        for (std::size_t i = 0; i < seq.size(); ++i) {
            HopfieldRouter::Vector q{};
            q[seq[i] % HopfieldRouter::kDim] = 100;
            CHECK(trained.learn(q, seq[(i + 1) % seq.size()]));
        }
    }
    HeadStore heads(map, runner);
    CHECK(heads.write_all(trained));
    CHECK_EQ(heads.mapped_heads(), 256u);
    for (std::uint16_t h = 0; h < 8; ++h) {
        HopfieldRouter::Vector out{};
        CHECK(heads.read_head(h, out));
        CHECK(out == trained.head(static_cast<std::uint8_t>(h)));
    }
    CHECK(heads.mapped_slots() > 0);
    std::vector<StoredSlot> stored;
    CHECK(heads.read_slots(1, map, stored));
    CHECK(!stored.empty());
    if (!stored.empty()) CHECK_EQ(stored.front().used, 1u);
    CHECK_EQ(map.resident_pages(), 3u); // page 0, head arena, peer page

    return test_done("dense 2 GiB overbootstrap and 8 MiB runner mapping");
#endif
}
