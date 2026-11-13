#include "nanlm/projection_runtime.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace nanlm;

int main() {
    ProjectionRuntime runtime("build");
    CHECK(runtime.load(ProjectionRuntime::Kind::Word));
    constexpr std::size_t vocab = 8;
    CHECK(runtime.word_clear(vocab));
    const std::vector<std::uint32_t> ids = {0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7};
    CHECK(runtime.word_build(ids, vocab));

    std::array<std::uint32_t, 5> top{};
    float loss = 0.0f;
    CHECK(runtime.word_top5(1, 0, vocab,
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

    CHECK(runtime.word_top5(0, 1, vocab,
                            static_cast<std::uint32_t>(ids.size()),
                            top, loss));
    CHECK_EQ(top[0], 0u);

    // Streaming batch counts must match the single-build counts, including
    // the bigram pair crossing the chunk boundary.
    CHECK(runtime.word_clear(vocab));
    const std::uint32_t sentinel = 0xFFFFFFFFu;
    std::vector<std::uint32_t> first(ids.begin(), ids.begin() + 7);
    std::vector<std::uint32_t> second(ids.begin() + 7, ids.end());
    CHECK(runtime.word_batch(first, vocab, sentinel));
    CHECK(runtime.word_batch(second, vocab, first.back()));
    std::array<std::uint32_t, 5> stream_top{};
    float stream_loss = 0.0f;
    CHECK(runtime.word_top5(0, 1, vocab,
                            static_cast<std::uint32_t>(ids.size()),
                            stream_top, stream_loss));
    CHECK(stream_top == top);
    CHECK(std::fabs(stream_loss - loss) < 1e-6f);

    return test_done("native full-vocabulary word projection");
}
