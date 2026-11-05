#include "nanlm/semiring.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    BoolMatrix a;
    for (std::uint32_t i = 0; i + 1 < 256; ++i) a[i].set(i + 1);
    const BoolMatrix t = bool_transpose(a);
    CHECK(t[1].test(0));
    CHECK(!t[0].test(1));
    const BoolMatrix c = bool_closure(a);
    CHECK(bool_reachable(c, 0, 255));
    CHECK(bool_reachable(c, 42, 255));
    CHECK(!bool_reachable(c, 255, 0));
    CHECK_EQ(bool_multiply(a, t)[0].test(0), true);

    BoolMatrix cyc;
    cyc[0].set(1);
    cyc[1].set(0);
    const BoolMatrix cc = bool_closure(cyc);
    CHECK(bool_reachable(cc, 0, 1));
    CHECK(bool_reachable(cc, 0, 0));
    return test_done("Boolean semiring closure");
}
