#include "nanlm/nlhe2_arena.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>
#include <vector>

using namespace nanlm;

namespace {
Nlhe2Record golden_record() {
    Nlhe2Record r{};
    r.flags = kNlhe2FlagDirected | kNlhe2FlagCrossSpace;
    r.logical_edge_id = 0x1122334455667788ull;
    r.label = 0xCAFEu;
    r.weight_q16 = 65536u;
    r.epoch = 7u;
    r.home = *TensorPointRef::make(3, 7, 2);
    r.members = {
        {*TensorPointRef::make(3, 7, 2),
         kNlhe2RoleMember | kNlhe2RoleRepresentative, 0},
        {*TensorPointRef::make(7, 7, 7),
         kNlhe2RoleMember | kNlhe2RoleTail, 12},
        {*TensorPointRef::make(2, 2, 2),
         kNlhe2RoleMember | kNlhe2RoleHead, 7},
    };
    return r;
}

const std::array<std::uint8_t, 72> kGolden = {
    0x4E,0x4C,0x48,0x45,0x02,0x00,0x09,0x00,
    0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11,
    0xFE,0xCA,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x01,0x00,
    0x02,0xE0,0x03,0x4E,
    0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x02,0xE0,0x03,0x4E,0x03,0x00,0x00,0x00,
    0x07,0xE0,0x07,0x4E,0x05,0x0C,0x00,0x00,
    0x02,0x40,0x02,0x4E,0x09,0x07,0x00,0x00,
};

Nlhe2Record at_point(unsigned h, unsigned a, unsigned b,
                     std::uint64_t id, std::uint64_t label) {
    Nlhe2Record r{};
    r.flags = 0;
    r.logical_edge_id = id;
    r.label = label;
    r.weight_q16 = 65536u;
    r.home = *TensorPointRef::make(h, a, b);
    r.members = {
        {*TensorPointRef::make(h, a, b),
         kNlhe2RoleMember | kNlhe2RoleRepresentative, 0},
        {*TensorPointRef::make(h, a, b), kNlhe2RoleMember, 0},
    };
    // Duplicate member is invalid; use a second valid distinct point.
    r.members[1].point = *TensorPointRef::make(h, a, (b + 1u) % 255u);
    return r;
}
} // namespace

int main() {
    // Point identity and arena-index parity.
    CHECK_EQ(pal16(0), 0x0000u);
    CHECK_EQ(pal16(1), 0x8001u);
    CHECK_EQ(pal16(2), 0x4002u);
    CHECK_EQ(addr16(0, 1), 0x0001u);
    CHECK_EQ(addr16(1, 0), 0x8000u);
    for (unsigned h : {0u, 1u, 127u, 254u}) {
        for (unsigned a : {0u, 1u, 63u, 254u}) {
            for (unsigned b : {0u, 2u, 64u, 254u}) {
                if (a == b) continue;
                const auto p = TensorPointRef::make(h, a, b);
                CHECK(p.has_value());
                CHECK_EQ(p->index(), DualTensor256Arena::index(h, a, b));
                CHECK_EQ(p->byte_offset(1),
                         DualTensor256Arena::byte_offset(h, a, b, 1));
                CHECK(p->mirror().mirror() == *p);
            }
        }
    }
    CHECK(!TensorPointRef::make(255, 1, 2).has_value());
    CHECK(!TensorPointRef::from_bits(0x4E00FF01u).has_value());

    // Canonical codec golden vector.
    const auto bytes = encode_nlhe2(golden_record());
    CHECK_EQ(bytes.size(), kGolden.size());
    CHECK(bytes == std::vector<std::uint8_t>(kGolden.begin(), kGolden.end()));
    const auto decoded = decode_nlhe2(bytes);
    CHECK(static_cast<bool>(decoded));
    CHECK(decoded.record == golden_record());
    CHECK(valid_nlhe2_payload(bytes));

    auto bad = bytes;
    bad[5] = 1;
    CHECK(!valid_nlhe2_payload(bad));
    bad = bytes;
    bad[0] = 0;
    CHECK(!valid_nlhe2_payload(bad));
    bad = bytes;
    bad.push_back(0);
    CHECK(!valid_nlhe2_payload(bad));

    // Typed leaf validation and append-only arena attach/replay/conflict.
    DualTensor256Arena arena(std::string(64, 'a'), std::string(64, 'b'));
    arena.set_all_candidate_writer_permissions(true);
    arena.begin_candidate();
    const std::string digest(64, 'c');
    const auto record = golden_record();
    auto attached = attach_nlhe2_candidate(arena, 3, record, digest);
    CHECK(attached.status == Nlhe2AttachStatus::Attached);
    CHECK_EQ(attached.entries_at_point, 1u);
    auto leaves = arena.candidate_leaves(3, 7, 2);
    CHECK_EQ(leaves.size(), 1u);
    CHECK(leaves[0].kind == TensorLeafKind::HyperedgeRecordV2);
    CHECK(valid_tensor_leaf_payload(leaves[0]));

    TensorDataLeaf malformed{};
    malformed.kind = TensorLeafKind::HyperedgeRecordV2;
    malformed.logical_leaf_id = 1;
    malformed.source_generation = 0;
    malformed.source_sha256 = digest;
    malformed.payload = bytes;
    malformed.payload[0] = 0;
    CHECK(!valid_tensor_leaf_payload(malformed));

    const auto replayed = attach_nlhe2_candidate(arena, 3, record, digest);
    CHECK(replayed.status == Nlhe2AttachStatus::Replayed);
    CHECK_EQ(replayed.entries_at_point, 1u);

    auto conflict = record;
    conflict.label = 0xCAFFu;
    const auto conflicted = attach_nlhe2_candidate(arena, 3, conflict, digest);
    CHECK(conflicted.status == Nlhe2AttachStatus::Conflict);
    CHECK_EQ(conflicted.entries_at_point, 1u);

    const auto view = newest_nlhe2(arena, record.home, record.logical_edge_id);
    CHECK(view.has_value());
    CHECK(view->record == record);
    CHECK_EQ(view->source_generation, 0u);

    // Per-point quota: 16 total leaves at one point.
    for (unsigned i = 0; i < 15; ++i) {
        const auto extra = at_point(3, 7, 2, 100u + i, i + 1u);
        const auto r = attach_nlhe2_candidate(arena, 3, extra, digest);
        CHECK(r.status == Nlhe2AttachStatus::Attached);
    }
    const auto over = attach_nlhe2_candidate(
        arena, 3, at_point(3, 7, 2, 999u, 999u), digest);
    CHECK(over.status == Nlhe2AttachStatus::Quota);

    // Candidate abort must leave ACTIVE untouched.
    arena.abort_candidate();
    CHECK(arena.active_leaves(3, 7, 2).empty());
    CHECK(arena.active(3, 7, 2) == 0.0f);

    return test_done("NLHE2 hyperedge codec and typed-leaf store");
}
