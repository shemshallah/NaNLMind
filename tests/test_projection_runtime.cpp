#include "nanlm/projection_runtime.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace nanlm;

int main() {
    ProjectionRuntime runtime("build");

    // Full-vocabulary token head.
    CHECK(runtime.load(ProjectionRuntime::Kind::Token));
    constexpr std::size_t token_v = 8;
    CHECK(runtime.token_clear(token_v, 3));
    std::array<std::uint16_t, 65536> rowmap{};
    rowmap.fill(2);
    rowmap[0] = 0;
    rowmap[1] = 1;
    CHECK(runtime.token_rowmap(rowmap));
    const std::vector<std::uint32_t> token_ids =
        {0, 1, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7};
    CHECK(runtime.token_batch(
        std::vector<std::uint32_t>(token_ids.begin(), token_ids.begin() + 9),
        token_v, 3, 0xFFFFFFFFu));
    CHECK(runtime.token_batch(
        std::vector<std::uint32_t>(token_ids.begin() + 9, token_ids.end()),
        token_v, 3, token_ids[8]));
    std::array<std::uint32_t, 5> token_top{};
    float token_loss = 0.0f;
    CHECK(runtime.token_top5(1, 0, token_v,
                             static_cast<std::uint32_t>(token_ids.size()),
                             token_top, token_loss));
    CHECK_EQ(token_top[0], 1u);
    CHECK(std::isfinite(token_loss));

    // Word head, after releasing the token VM.
    CHECK(runtime.load(ProjectionRuntime::Kind::Word));
    constexpr std::size_t word_v = 8;
    CHECK(runtime.word_clear(word_v));
    const std::vector<std::uint32_t> word_ids =
        {0, 1, 0, 1, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7};
    CHECK(runtime.word_build(word_ids, word_v));
    std::array<std::uint32_t, 5> word_top{};
    float word_loss = 0.0f;
    CHECK(runtime.word_top5(1, 0, word_v,
                            static_cast<std::uint32_t>(word_ids.size()),
                            word_top, word_loss));
    CHECK_EQ(word_top[0], 1u);
    CHECK(std::isfinite(word_loss));

    // Byte direct-256 head.
    CHECK(runtime.load(ProjectionRuntime::Kind::Byte));
    const std::array<std::uint32_t, 4> keys = {
        0x41424344u, 0x45464748u, 0x51525354u, 0x55565758u};
    CHECK(runtime.byte_build(keys.data(), keys.size()));
    CHECK(runtime.byte_reset(2, 2));
    std::uint32_t bucket = 0;
    bool exact = false;
    CHECK(runtime.byte_step(0x12u, keys[0], bucket, exact));
    CHECK(exact);
    std::array<std::uint8_t, 5> byte_top{};
    float byte_loss = 0.0f;
    CHECK(runtime.byte_top5(0x12u, keys[0], byte_top, byte_loss));
    CHECK_EQ(byte_top[0], 0x12u);
    CHECK(std::isfinite(byte_loss));

    runtime.unload();
    CHECK(!runtime.ready());
    return test_done("unified projection runtime");
}
