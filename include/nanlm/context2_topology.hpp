// Topology-backed context-2 memory.
//
// The router chart has 256 heads: one per first context byte. Each open child
// universe stores a 256x256 count matrix in its pair cells:
//
//   child(a).pair_cell(b,c).s_plus().payload() = count(a,b,c)
//
// This is the actual child-universe layout; the compact Context2Model is the
// same math without materializing 8 MiB pages.
#pragma once

#include "nanlm/global.hpp"
#include "nanlm/router.hpp"

#include <array>
#include <cstdint>

namespace nanlm {

class Context2Topology {
public:
    explicit Context2Topology(GlobalTopology& topology, PageId router = PageId::root())
        : topology_(&topology), router_(std::move(router)) {}

    bool observe(std::uint8_t a, std::uint8_t b, std::uint8_t c,
                 std::uint32_t count = 1);
    std::uint32_t count(std::uint8_t a, std::uint8_t b, std::uint8_t c) const;
    std::uint8_t predict(std::uint8_t a, std::uint8_t b) const;

    bool has_universe(std::uint8_t a) const { return open_[a]; }
    PageId universe(std::uint8_t a) const { return child_[a]; }
    std::size_t universes() const;

private:
    bool ensure_universe(std::uint8_t a);

    GlobalTopology* topology_;
    PageId router_;
    std::array<PageId, 256> child_{};
    std::array<bool, 256> open_{};
};

} // namespace nanlm
