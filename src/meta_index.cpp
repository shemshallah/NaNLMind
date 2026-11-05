#include "nanlm/meta_index.hpp"

namespace nanlm {

MetaIndex::MetaIndex(PageId router) : router_(std::move(router)) {
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const std::uint8_t row = matrix_row(a);
        const std::uint8_t col = matrix_col(a);
        MetaEntry e;
        e.row = row;
        e.col = col;
        if (row == col) {
            e.portal = true;
            e.child = PageId::child(router_, row);
            e.route_addr = a;
        } else {
            e.route_addr = canonical16(a);
        }
        entries_[i] = e;
    }
}

} // namespace nanlm
