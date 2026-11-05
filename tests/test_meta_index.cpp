#include "nanlm/meta_index.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    MetaIndex index(PageId::child(PageId::root(), 0));
    std::uint32_t portals = 0, routes = 0;
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const auto& e = index.at(a);
        if (e.portal) {
            ++portals;
            CHECK(e.child.depth == 2);
            CHECK(e.child.path[0] == 0);
            CHECK(e.child.path[1] == matrix_row(a));
            CHECK(is_palindrome16(a));
        } else {
            ++routes;
            CHECK_EQ(e.route_addr, canonical16(a));
            CHECK_EQ(index.at(reverse16(a)).route_addr, e.route_addr);
        }
    }
    CHECK_EQ(portals, 256u);
    CHECK_EQ(routes, 65280u);
    CHECK_EQ(index.route_address(3, 7), canonical16(matrix_addr(3, 7)));
    CHECK_EQ(index.portal(3).path[0], 0u);
    CHECK_EQ(index.portal(3).path[1], 3u);

    return test_done("65,536-entry meta index");
}
