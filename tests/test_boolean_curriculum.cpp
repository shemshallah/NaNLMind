#include "nanlm/head.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>

using namespace nanlm;

namespace {
void set_operands(HeadView& h, std::uint32_t a, std::uint32_t b) {
    std::uint8_t* l = h.scratch().local();
    for (int i = 0; i < 4; ++i) {
        l[i] = static_cast<std::uint8_t>((a >> (8 * i)) & 0xFFu);
        l[4 + i] = static_cast<std::uint8_t>((b >> (8 * i)) & 0xFFu);
    }
}
} // namespace

int main() {
    auto u = std::make_unique<Universe>(0x1234);
    HeadArray heads(*u, PageId::root());
    std::string err;
    CHECK(heads.verify(&err));

    const std::array<std::uint32_t, 5> a_values{
        0x00000000u, 0xFFFFFFFFu, 0xAAAAAAAAu, 0x55555555u, 0x12345678u};
    const std::array<std::uint32_t, 5> b_values{
        0xFFFFFFFFu, 0x00000000u, 0x55555555u, 0xAAAAAAAAu, 0x9ABCDEF0u};

    std::size_t rules = 0;
    std::size_t bit_vectors = 0;
    std::size_t self_mods = 0;
    for (std::uint16_t index = 0; index < 256; ++index) {
        HeadView h = heads.at(static_cast<std::uint8_t>(index));
        const std::uint8_t target = static_cast<std::uint8_t>(index & 15u);
        h.reset_boolean_learner();
        for (int rep = 0; rep < 100; ++rep) {
            for (std::uint32_t a = 0; a < 2; ++a) {
                for (std::uint32_t b = 0; b < 2; ++b) {
                    const bool truth = ((target >> (2u * a + b)) & 1u) != 0;
                    h.train_boolean(a, b, truth);
                }
            }
        }
        CHECK_EQ(h.boolean_rule(), target);
        CHECK_EQ(h.boolean_mask(), static_cast<std::uint16_t>(1u << target));
        CHECK(h.boolean_score(target) > 0);
        ++rules;

        for (std::size_t i = 0; i < a_values.size(); ++i) {
            set_operands(h, a_values[i], b_values[i]);
            const std::uint32_t got = h.eval_boolean_from_scratch();
            const std::uint32_t expected = NanWord::eval_bool(target, a_values[i], b_values[i]);
            CHECK_EQ(got, expected);
            ++bit_vectors;
        }

        // Individual self-modification: patch one bit, then restore.
        const std::uint16_t patch = static_cast<std::uint16_t>(
            1u << ((target + 1u) & 15u));
        const std::uint16_t before = h.boolean_mask();
        CHECK(h.self_modify_boolean(patch));
        CHECK_EQ(h.boolean_mask(), static_cast<std::uint16_t>(before ^ patch));
        CHECK(h.self_modify_boolean(patch));
        CHECK_EQ(h.boolean_mask(), before);
        ++self_mods;
    }
    CHECK_EQ(rules, 256u);
    CHECK_EQ(bit_vectors, 256u * a_values.size());
    CHECK_EQ(self_mods, 256u);
    CHECK(heads.verify(&err));

    return test_done("256-head Boolean curriculum and bit manipulation");
}
