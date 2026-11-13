#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>

using namespace nanlm;

namespace {
std::uint32_t route_hash(std::uint32_t key, std::uint32_t exact,
                         std::uint32_t fallback) {
    std::uint32_t hash = 2166136261u;
    hash = (hash ^ (key & 0xFFu)) * 16777619u;
    hash = (hash ^ ((key >> 8) & 0xFFu)) * 16777619u;
    hash = (hash ^ ((key >> 16) & 0xFFu)) * 16777619u;
    return exact + hash % fallback;
}
} // namespace

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    if (!vm.ready()) return test_done("raw context backoff route");

    constexpr std::size_t buckets = 8;
    CHECK(vm.reset_context_readout(buckets));
    CHECK(vm.reset_context_backoff());

    const std::uint32_t key_a = 0x41424344u;  // ABCD
    const std::uint32_t key_b = 0x45464748u;  // EFGH
    const std::uint32_t key_c = 0x51525354u;  // QRST
    const std::uint32_t key_d = 0x55565758u;  // UVWX
    const std::uint32_t key_e = 0x59525354u;  // YRST shares the k=3 suffix

    bool inserted = false;
    for (int i = 0; i < 5; ++i) {
        CHECK(vm.context_backoff_build(key_a, &inserted));
        CHECK_EQ(inserted, i == 0);
    }
    for (int i = 0; i < 3; ++i) {
        CHECK(vm.context_backoff_build(key_b, &inserted));
        CHECK_EQ(inserted, i == 0);
    }
    CHECK(vm.context_backoff_build(key_c, &inserted));
    CHECK(inserted);
    CHECK(vm.context_backoff_build(key_d, &inserted));
    CHECK(inserted);

    ContextBackoffSelection selection;
    CHECK(vm.context_backoff_select(buckets, 2, selection));
    CHECK_EQ(selection.exact_count, 2u);
    CHECK_EQ(selection.fallback, 6u);
    CHECK_EQ(selection.threshold, 3u);
    CHECK_EQ(selection.unique, 4u);

    ContextBackoffStep step;
    CHECK(vm.readout_context_backoff(0x12u, 0.0f, key_a, buckets, step));
    CHECK(step.exact);
    const std::uint32_t slot_a = step.bucket;
    CHECK(slot_a < selection.exact_count);

    CHECK(vm.readout_context_backoff(0x12u, 0.0f, key_b, buckets, step));
    CHECK(step.exact);
    const std::uint32_t slot_b = step.bucket;
    CHECK(slot_b < selection.exact_count);
    CHECK(slot_a != slot_b);

    // The rare k=4 keys were not selected and must use the k=3 fallback.
    CHECK(vm.readout_context_backoff(0x12u, 0.0f, key_c, buckets, step));
    CHECK(!step.exact);
    CHECK_EQ(step.bucket, route_hash(key_c, 2u, 6u));
    const std::uint32_t fallback_c = step.bucket;

    // A different k=4 prefix with the same k=3 suffix hashes to the same slot.
    CHECK(vm.readout_context_backoff(0x12u, 0.0f, key_e, buckets, step));
    CHECK(!step.exact);
    CHECK_EQ(step.bucket, fallback_c);

    // One raw update must train the routed shared column.
    CHECK(vm.readout_context_backoff(0x12u, 1.0f, key_c, buckets, step));
    CHECK(vm.readout_context_backoff(0x12u, 0.0f, key_c, buckets, step));
    CHECK(step.correct);
    CHECK_EQ(step.predicted_high, 1u);
    CHECK_EQ(step.predicted_low, 2u);

    // The full 16x16 ranking must contain the just-trained target and use the
    // same routed column as the greedy step.
    std::array<std::uint8_t, 5> top{};
    float top_loss = 0.0f;
    CHECK(vm.readout_context_top5(0x12u, key_c, buckets, top, top_loss));
    CHECK_EQ(top[0], 0x12u);
    CHECK(std::isfinite(top_loss));
    bool contains_target = false;
    for (std::uint8_t c : top) contains_target |= c == 0x12u;
    CHECK(contains_target);

    // Raising the exact limit selects all four unique k=4 keys.
    CHECK(vm.context_backoff_select(buckets, 4, selection));
    CHECK_EQ(selection.exact_count, 4u);
    CHECK_EQ(selection.fallback, 4u);
    CHECK_EQ(selection.threshold, 1u);
    CHECK_EQ(selection.unique, 4u);
    std::array<bool, 4> seen{};
    for (const std::uint32_t key : {key_a, key_b, key_c, key_d}) {
        CHECK(vm.readout_context_backoff(0x12u, 0.0f, key, buckets, step));
        CHECK(step.exact);
        CHECK(step.bucket < 4u);
        CHECK(!seen[step.bucket]);
        seen[step.bucket] = true;
    }

    // Context-class bridge (command 31) must not collide with backoff (30).
    ContextClassInput cls;
    cls.direct = true;
    cls.buckets = buckets;
    cls.direct_high = 1;
    cls.direct_low = 0;
    std::array<std::int32_t, kTriadMemberCount> credits{};
    credits.fill(0);
    ContextClassResult mapped;
    CHECK(vm.context_class_credit(cls, ContextCreditInput{}, credits, mapped));
    CHECK_EQ(mapped.head, 16u);
    CHECK_EQ(mapped.triad, 5u);
    CHECK_EQ(mapped.member, 1u);
    CHECK(!mapped.field_head);

    cls.direct_high = 15;
    cls.direct_low = 15;
    ContextClassResult field;
    CHECK(vm.context_class_credit(cls, ContextCreditInput{}, credits, field));
    CHECK(field.field_head);
    CHECK_EQ(field.head, 255u);
    CHECK_EQ(field.triad, 0xFFFFu);
    CHECK_EQ(field.member, 0xFFFFu);

    return test_done("raw context backoff route");
}
