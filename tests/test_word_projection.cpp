#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/word_worker.nan");
    CHECK(vm.ready());
    constexpr std::size_t vocab = 8;
    CHECK(vm.word_projection_clear(vocab));
    const std::vector<std::uint32_t> ids = {0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7};
    CHECK(vm.word_projection_build(ids, vocab));

    std::array<std::uint32_t, 5> top{};
    float loss = 0.0f;
    CHECK(vm.word_projection_top5(1, 0, vocab,
                                  static_cast<std::uint32_t>(ids.size()),
                                  top, loss));
    CHECK_EQ(top[0], 1u);
    CHECK(std::isfinite(loss));
    CHECK(loss > 0.0f);
    std::array<bool, vocab> seen{};
    for (std::size_t i = 0; i < top.size(); ++i) {
        CHECK(top[i] < vocab);
        CHECK(!seen[top[i]]);
        seen[top[i]] = true;
    }

    CHECK(vm.word_projection_top5(0, 1, vocab,
                                  static_cast<std::uint32_t>(ids.size()),
                                  top, loss));
    CHECK_EQ(top[0], 0u);

    return test_done("native full-vocabulary word projection");
}
