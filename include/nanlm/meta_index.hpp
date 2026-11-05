// The 65,536-entry final-layer directory over a router chart.
#pragma once

#include "nanlm/nan16.hpp"
#include "nanlm/pager.hpp"

#include <array>
#include <cstdint>

namespace nanlm {

struct MetaEntry {
    PageId child{};
    std::uint16_t route_addr = 0;
    bool portal = false;
    std::uint8_t row = 0;
    std::uint8_t col = 0;
};

class MetaIndex {
public:
    explicit MetaIndex(PageId router);

    const MetaEntry& at(std::uint16_t address) const { return entries_[address]; }
    PageId portal(std::uint8_t head) const { return PageId::child(router_, head); }
    std::uint16_t route_address(std::uint8_t src, std::uint8_t dst) const {
        return canonical16(matrix_addr(src, dst));
    }
    static constexpr std::size_t portal_count() { return 256; }
    static constexpr std::size_t route_count() { return 32640; }
    const PageId& router() const { return router_; }

private:
    PageId router_;
    std::array<MetaEntry, 65536> entries_{};
};

} // namespace nanlm
