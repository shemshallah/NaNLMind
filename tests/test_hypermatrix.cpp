#include "nanlm/global.hpp"
#include "nanlm/hypermatrix.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>
#include <vector>

using namespace nanlm;

int main() {
    // Mapped hypermatrix rows and exact/dense scoring.
    {
        Universe u;
        Hypermatrix matrix(u);
        matrix.set(1, 2, 3);
        CHECK(matrix.has(1, 2, 3));
        CHECK_EQ(matrix.exact_support(1, 2, 3), 3u);
        CHECK_EQ(matrix.exact_support(2, 1, 3), 3u);
        CHECK_EQ(matrix.score(1, 2, 3), matrix.exact_support(1, 2, 3) * 4u + matrix.dense_support(1, 2, 3) + matrix.head_coupling(1, 2, 3));

        // A dense pair contraction survives even when the exact triple was
        // never stored. This is the generalization path the ablation uses.
        u.pair_cell(1, 2).q_plus() = NanWord::make(
            NanType::QuietPositive, NanType::QuietPositive, 7);
        u.pair_cell(2, 3).q_plus() = NanWord::make(
            NanType::QuietPositive, NanType::QuietPositive, 9);
        u.pair_cell(1, 3).q_plus() = NanWord::make(
            NanType::QuietPositive, NanType::QuietPositive, 0);
        CHECK_EQ(matrix.dense_support(1, 2, 3), 1u);
        CHECK_EQ(matrix.score(1, 2, 3), matrix.exact_support(1, 2, 3) * 4u + matrix.dense_support(1, 2, 3) + matrix.head_coupling(1, 2, 3));
        CHECK(u.hypermatrix_nonzero() >= 3u);

        // An unstored triple still receives a contribution from its two
        // constituent mirror pairs. This is the ablation-relevant path.
        Universe dense;
        dense.pair_cell(10, 11).q_plus() = NanWord::make(
            NanType::QuietPositive, NanType::QuietPositive, 3);
        dense.pair_cell(11, 12).q_plus() = NanWord::make(
            NanType::QuietPositive, NanType::QuietPositive, 4);
        dense.pair_cell(10, 12).q_plus() = NanWord::make(
            NanType::QuietPositive, NanType::QuietPositive, 0);
        Hypermatrix unstored(dense);
        CHECK(!unstored.has(10, 11, 12));
        CHECK_EQ(unstored.exact_support(10, 11, 12), 0u);
        CHECK_EQ(unstored.dense_support(10, 11, 12), 1u);
        CHECK_EQ(unstored.score(10, 11, 12), 1u + unstored.head_coupling(10, 11, 12));

        // Three-level Q16.16 gains scale the same mapped readout. A 0.5
        // local + group + field gain must halve the base score.
        Universe scaled;
        Hypermatrix base_matrix(scaled);
        TriadField::set_local_gain(scaled, 1, 32768);
        TriadField::set_local_gain(scaled, 2, 32768);
        TriadField::set_local_gain(scaled, 3, 32768);
        TriadField::set_group_gain(scaled, 0, 32768);
        TriadField::set_field_gain(scaled, 32768);
        const std::uint32_t base_score =
            base_matrix.exact_support(1, 2, 3) * 4u +
            base_matrix.dense_support(1, 2, 3) +
            base_matrix.head_coupling(1, 2, 3);
        CHECK_EQ(base_matrix.score(1, 2, 3), base_score / 2u);

        // The matrix is part of the chart digest and survives serialization.
        const auto before = u.digest();
        const auto bytes = u.serialize();
        auto restored = Universe::from_bytes(bytes.data(), bytes.size());
        CHECK(restored != nullptr);
        if (restored) {
            CHECK(restored->digest() == before);
            Hypermatrix reloaded(*restored);
            CHECK(reloaded.has(1, 2, 3));
            CHECK_EQ(reloaded.score(1, 2, 3), matrix.score(1, 2, 3));
        }
    }

    // First-class hyperedge projection into the mapped matrix.
    {
        GlobalTopology g;
        Hyperedge edge;
        edge.flags = kHyperLearned;
        edge.label = 42;
        edge.epoch = 1;
        edge.members = {
            Ref::from_bit(BitAddress{PageId::root(), matrix_addr(1, 1), 0, 0}),
            Ref::from_bit(BitAddress{PageId::root(), matrix_addr(2, 2), 0, 0}),
            Ref::from_bit(BitAddress{PageId::root(), matrix_addr(3, 3), 0, 0}),
        };
        const auto id = g.add_hyperedge(edge);
        CHECK(id != 0);
        CHECK_EQ(g.hypergraph().size(), 1u);
        CHECK(g.hypermatrix_nonzero() >= 3u);
        CHECK(g.hypermatrix_score(1, 2, 3) >= 12u);
    }

    // Triad voting: two of three members accept a head patch.
    {
        Universe u;
        HeadArray heads(u, PageId::root());
        for (std::uint8_t h = 0; h < 6; ++h) {
            HeadView view = heads.at(h);
            CHECK(view.set_boolean_mask(0x0001));
        }
        TriadField::clear(u, 0);
        CHECK(!TriadField::vote(u, 0, true));
        CHECK(!TriadField::accepted(u, 0));
        CHECK(TriadField::vote(u, 1, true));
        CHECK(TriadField::accepted(u, 0));
        CHECK_EQ(TriadField::votes(u, 0), 3u);

        // Rule 0 is false; XOR patch 0x0002 selects rule 1 (NOR), which
        // is true for a=0,b=0,target=true. All three members improve.
        CHECK(TriadField::apply_patch(u, heads, 0, 0x0003, 0, 0, true));
        for (std::uint8_t h = 0; h < 3; ++h) {
            CHECK_EQ(heads.at(h).boolean_mask(), 0x0002u);
            CHECK_EQ(heads.at(h).boolean_rule(), 1u);
        }
        CHECK_EQ(TriadField::update_field(u), 1u);
        CHECK(!TriadField::field_accepted(u));

        // The vote mask and field counter are part of the chart state.
        const auto bytes = u.serialize();
        auto restored = Universe::from_bytes(bytes.data(), bytes.size());
        CHECK(restored != nullptr);
        if (restored) {
            CHECK_EQ(TriadField::votes(*restored, 0), 7u);
            CHECK(TriadField::accepted(*restored, 0));
        }
    }

    // Field vote: 43 of 85 triads is a majority of the one field.
    {
        Universe u;
        for (std::uint8_t t = 0; t < 43; ++t) {
            const std::uint8_t leader = static_cast<std::uint8_t>(t * 3u);
            CHECK(!TriadField::vote(u, leader, true));
            CHECK(TriadField::vote(u, static_cast<std::uint8_t>(leader + 1u), true));
        }
        CHECK_EQ(TriadField::update_field(u), 43u);
        CHECK(TriadField::field_accepted(u));
    }

    return test_done("mapped hypermatrix + triadic head-field voting");
}
