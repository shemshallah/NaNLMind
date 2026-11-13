#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/token_worker.nan");
    CHECK(vm.ready());
    constexpr std::size_t V = 8;
    constexpr std::size_t rows = 3;
    CHECK(vm.token_projection_clear(V, rows));
    std::array<std::uint16_t, 65536> rowmap{};
    rowmap.fill(2);
    rowmap[0] = 0;
    rowmap[1] = 1;
    CHECK(vm.token_projection_write_rowmap(rowmap));

    const std::vector<std::uint32_t> ids = {
        0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7};
    const std::uint32_t sentinel = 0xFFFFFFFFu;
    CHECK(vm.token_projection_batch(
        std::vector<std::uint32_t>(ids.begin(), ids.begin() + 7),
        V, rows, sentinel));
    CHECK(vm.token_projection_batch(
        std::vector<std::uint32_t>(ids.begin() + 7, ids.end()),
        V, rows, ids[6]));

    std::array<std::uint32_t, 5> top{};
    float loss = 0.0f;
    CHECK(vm.token_projection_top5(1, 0, V,
                                   static_cast<std::uint32_t>(ids.size()),
                                   top, loss));
    CHECK_EQ(top[0], 1u);
    CHECK(std::isfinite(loss));
    CHECK(loss > 0.0f);
    std::array<bool, V> seen{};
    for (std::uint32_t id : top) {
        CHECK(id < V);
        CHECK(!seen[id]);
        seen[id] = true;
    }

    return test_done("native full-vocabulary token projection");
}
