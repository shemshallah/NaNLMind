#include "nanlm/head_catalog.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    static_assert(HeadCatalog::kCount == 255);
    static_assert(HeadCatalog::kFirst == 0);
    static_assert(HeadCatalog::kLast == 254);
    static_assert(HeadCatalog::kField == 255);
    static_assert(HeadCatalog::kFullSetLeafBytes == 0);
    CHECK(HeadCatalog::contains(0));
    CHECK(HeadCatalog::contains(254));
    CHECK(!HeadCatalog::contains(255));
    for (std::size_t i = 0; i < HeadCatalog::kCount; ++i) {
        const auto head = HeadCatalog::at(i);
        CHECK_EQ(head, static_cast<std::uint8_t>(i));
        CHECK_EQ(HeadCatalog::leaf_of(head), head);
        std::uint8_t roundtrip = 255;
        CHECK(HeadCatalog::head_of(HeadCatalog::leaf_of(head), roundtrip));
        CHECK_EQ(roundtrip, head);
    }
    std::uint8_t field = 0;
    CHECK(!HeadCatalog::head_of(HeadCatalog::kField, field));
    return test_done("compact head catalog");
}
