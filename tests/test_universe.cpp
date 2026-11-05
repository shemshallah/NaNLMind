#include "nanlm/universe.hpp"
#include "test_util.hpp"

#include <memory>
#include <string>

using namespace nanlm;

int main() {
    CHECK_EQ(sizeof(NanCell), 64u);
    CHECK_EQ(sizeof(AddressReg), 32u);
    CHECK_EQ(sizeof(Descriptor), 48u);
    CHECK_EQ(sizeof(Head), 32u);
    CHECK_EQ(kRegisterBytes, 2'105'344u);
    CHECK_EQ(kAddressTableBytes, 2'097'152u);
    CHECK_EQ(kDescriptorTableBytes, 1'579'008u);
    CHECK_EQ(kPageBytes, 8u * 1024u * 1024u);
    CHECK(kRegisterBytes + kDescriptorTableBytes + kAddressTableBytes + kIndexBytes +
              kCanonicalIndexBytes + kPairIndexBytes + kHeadBytes * kHeadCount +
              kAdjacencyBytes + kDirtyBytes + kAddressDirtyBytes <
          kPageBytes);

    auto u = std::make_unique<Universe>(0x0123456789ABCDEFull);
    std::string err;
    CHECK(u->verify(&err));

    CHECK_EQ(u->canonical_count(), 32896u);
    CHECK_EQ(u->pair_count(), 32640u);

    // Every one of the 256 palindromic addresses is a head.
    std::uint32_t heads = 0;
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (is_palindrome16(a)) {
            ++heads;
            const auto& c = u->at_addr(a);
            CHECK(c.is_head());
            CHECK(c.is_portal());
            CHECK_EQ(c.owner, static_cast<std::uint16_t>(matrix_row(a)));
            CHECK_EQ(u->head(matrix_row(a)).fixed_addr, a);
        } else {
            CHECK(!u->at_addr(a).is_head());
            CHECK(u->at_addr(a).is_pair());
        }
    }
    CHECK_EQ(heads, 256u);

    // Every address, including both mirrors, has its own register.
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const AddressReg& r = u->address_reg(a);
        CHECK_EQ(r.addr, a);
        CHECK_EQ(r.mirror, reverse16(a));
        CHECK_EQ(u->address_reg(r.mirror).mirror, a);
        CHECK_EQ(r.meta, u->index_of_addr(a));
        CHECK(r.can_read() && r.can_write() && r.can_exec());
        if (is_palindrome16(a)) {
            CHECK(r.is_fixed());
            CHECK(r.is_canonical());
            CHECK(r.is_upper());
            CHECK_EQ(r.pair, static_cast<std::uint16_t>(kMirrorPairCount));
        } else {
            CHECK(r.is_paired());
            CHECK(r.is_canonical() != r.is_upper());
        }
    }

    // Per-address capabilities are independent of the mirror register.
    CHECK(u->set_capability(0x0080, 0x3));
    CHECK_EQ(u->address_reg(0x0080).caps, 0x3u);
    CHECK_EQ(u->address_reg(0x0100).caps, 0x7u);
    CHECK(u->address_dirty(0x0080));
    CHECK_EQ(u->address_dirty_count(), 1u);
    CHECK(u->set_capability(0x0080, 0x7));
    u->clear_address_dirty();
    CHECK_EQ(u->address_dirty_count(), 0u);

    // Every mirror pair is one physical cell with two rails.
    for (std::uint32_t p = 0; p < 32640; ++p) {
        const auto [a, b] = pair_heads(p);
        const std::uint16_t ab = matrix_addr(a, b);
        const std::uint16_t ba = matrix_addr(b, a);
        CHECK(u->index_of_addr(ab) == u->index_of_addr(ba));
        const auto& c = u->at_addr(ab);
        CHECK(c.is_pair());
        CHECK(c.is_dual());
        CHECK_EQ(c.owner, static_cast<std::uint16_t>(a));
        CHECK_EQ(u->descriptor_pair(p).head_a, a);
        CHECK_EQ(u->descriptor_pair(p).head_b, b);
        CHECK(u->adjacent(a, b));
        CHECK(u->adjacent(b, a));
    }

    // Descriptor and cell checksums are consistent.
    for (std::uint32_t idx = 0; idx < 32896; ++idx) {
        CHECK_EQ(u->descriptor_index(idx).checksum,
                 Universe::cell_checksum(u->cells()[idx]));
    }

    // Deterministic genesis and serialization.
    auto u2 = std::make_unique<Universe>(0x0123456789ABCDEFull);
    CHECK(u->digest() == u2->digest());
    const auto bytes = u->serialize();
    auto u3 = Universe::from_bytes(bytes.data(), bytes.size());
    CHECK(u3 != nullptr);
    if (u3) {
        CHECK(u3->verify(&err));
        CHECK(u3->digest() == u->digest());
    }

    // A different genome changes the state but keeps the topology.
    auto u4 = std::make_unique<Universe>(0);
    CHECK(!(u4->digest() == u->digest()));
    CHECK(u4->verify(&err));

    // The four words are independent rails.
    auto& c = u->pair_cell(3, 7);
    const auto s_plus = c.s_plus().payload();
    const auto s_minus = c.s_minus().payload();
    const auto q_plus = c.q_plus().payload();
    const auto q_minus = c.q_minus().payload();
    CHECK(!(s_plus == s_minus));
    CHECK_EQ(c.q_plus().opcode(), 0u);  // +s, +s
    CHECK_EQ(c.q_minus().opcode(), 5u); // -s, -s

    // Operator masks are non-empty and select a valid function.
    for (std::uint32_t p = 0; p < 32640; ++p) {
        const auto [a, b] = pair_heads(p);
        const auto& pc = u->pair_cell(a, b);
        CHECK(pc.ops != 0);
        CHECK(pc.rule < 16);
    }

    // Adjacency bitmap has exactly C(256,2) undirected edges.
    std::uint32_t edges = 0;
    for (int a = 0; a < 256; ++a) {
        for (int b = a + 1; b < 256; ++b) {
            if (u->adjacent(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b))) ++edges;
        }
    }
    CHECK_EQ(edges, 32640u);

    return test_done("register-file universe");
}
