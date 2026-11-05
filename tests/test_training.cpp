#include "nanlm/head.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    auto u = std::make_unique<Universe>(0x1234);
    HeadArray heads(*u, PageId::root());
    std::string err;
    CHECK(heads.verify(&err));

    HeadView h = heads.at(0);
    h.reset_boolean_learner();
    for (int rep = 0; rep < 100; ++rep) {
        for (std::uint32_t a = 0; a < 2; ++a) {
            for (std::uint32_t b = 0; b < 2; ++b) {
                h.train_boolean(a, b, ((a ^ b) & 1u) != 0);
            }
        }
    }
    CHECK_EQ(h.boolean_rule(), 6u); // XOR
    CHECK(h.boolean_score(6) > 0);
    CHECK(h.boolean_score(0) <= 0);
    CHECK_EQ(h.boolean_mask(), 1u << 6);
    CHECK(h.history().size() >= 1);

    // The learned rule evaluates from the scratchpad.
    h.scratch().local()[0] = 0xCC;
    h.scratch().local()[1] = 0xCC;
    h.scratch().local()[2] = 0xCC;
    h.scratch().local()[3] = 0xCC;
    h.scratch().local()[4] = 0xAA;
    h.scratch().local()[5] = 0xAA;
    h.scratch().local()[6] = 0xAA;
    h.scratch().local()[7] = 0xAA;
    CHECK_EQ(h.eval_boolean_from_scratch(), 0x66666666u);

    // Re-learn AND from a clean score table.
    h.reset_boolean_learner();
    for (int rep = 0; rep < 100; ++rep) {
        for (std::uint32_t a = 0; a < 2; ++a) {
            for (std::uint32_t b = 0; b < 2; ++b) {
                h.train_boolean(a, b, (a & b) != 0);
            }
        }
    }
    CHECK_EQ(h.boolean_rule(), 8u); // AND
    CHECK_EQ(h.boolean_mask(), 1u << 8);
    CHECK(h.boolean_score(8) > 0);
    CHECK(heads.verify(&err));

    return test_done("integer head training");
}
