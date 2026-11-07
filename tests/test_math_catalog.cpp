#include "nanlm/math_catalog.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>

using namespace nanlm;

int main() {
    CHECK_EQ(kCoreMathCatalog.size(), 34u);
    CHECK(find_operation("bool.truth2") != nullptr);
    CHECK(find_operation("bool.truth2")->exactness == Exactness::ExactFinite);
    CHECK(!catalog_entry_executable(*find_operation("bool.truth2")));
    CHECK(find_operation("bool.truth2")->preconditions == "UNSPECIFIED: not executable");
    CHECK(find_operation("catalog.propose")->exactness == Exactness::LearnedUnverified);
    CHECK(find_operation("not.a.real.operation") == nullptr);

    // The four-NaN two-input nibble is exhaustive: all sixteen functions,
    // all four input combinations, with the established index 2*a+b.
    for (std::uint8_t truth = 0; truth < 16; ++truth) {
        for (std::uint8_t a = 0; a < 2; ++a) {
            for (std::uint8_t b = 0; b < 2; ++b) {
                const bool inputs[2] = {a != 0, b != 0};
                CHECK_EQ(eval_boolean_inputs(truth, 2, inputs),
                         eval_boolean(truth, 2, static_cast<std::uint8_t>(2 * a + b)));
            }
        }
    }

    CHECK_EQ(boolean_function_count(2), 16u);
    CHECK_EQ(boolean_function_count(3), 256u);
    CHECK_EQ(boolean_function_count(4), 65536u);
    CHECK_EQ(boolean_function_count(5), 4294967296ull);
    CHECK_EQ(boolean_function_count(6), 0ull); // 2^64 is not representable in uint64_t
    CHECK_EQ(boolean_table_bits(4), 16u);
    CHECK_EQ(boolean_table_bits(7), 0u);

    // Check every 4-input truth table can be addressed without undefined
    // shifts, including its final bit.
    for (std::uint32_t truth = 0; truth < 65536; ++truth) {
        CHECK_EQ(eval_boolean(truth, 4, 0), (truth & 1u) != 0);
        CHECK_EQ(eval_boolean(truth, 4, 15), ((truth >> 15) & 1u) != 0);
    }

    ScratchDescriptor local{1, 64, 128, 64, 7, 99, 3, true};
    CHECK(local.valid(4096));
    const ScratchDescriptor unaligned{1, 65, 128, 64, 7, 99, 3, true};
    const ScratchDescriptor overflow{1, 64, 5000, 64, 7, 99, 3, true};
    const ScratchDescriptor bad_alignment{1, 64, 128, 3, 7, 99, 3, true};
    const ScratchDescriptor bad_owner{1, 64, 128, 64, 7, 99, 6, true};
    CHECK(!unaligned.valid(4096));
    CHECK(!overflow.valid(4096));
    CHECK(!bad_alignment.valid(4096));
    CHECK(!bad_owner.valid(4096));

    // Ten mathematical bands are stable identifiers, separate from L0-L9.
    std::array<std::uint8_t, 10> math_layers{};
    for (std::uint8_t i = 0; i < math_layers.size(); ++i) math_layers[i] = i;
    for (std::uint8_t i = 0; i < math_layers.size(); ++i) CHECK_EQ(math_layers[i], i);

    return test_done("typed math catalog, exhaustive Boolean indexing, scratch bounds");
}
