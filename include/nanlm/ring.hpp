// Scaling arithmetic and 5-node ring planning.
#pragma once

#include "nanlm/nan16.hpp"
#include "nanlm/pager.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

using u128 = unsigned __int128;

struct ScalePlan {
    int depth = 0;
    u128 universes = 0;
    u128 addresses = 0;
    u128 canonical = 0;
    u128 pairs = 0;
    u128 fixed = 0;
    u128 dense_bytes = 0; // one 4 MiB page per universe
};

inline ScalePlan scale_plan(int depth) {
    if (depth < 0) depth = 0;
    if (depth > 8) depth = 8;
    u128 universes = 1;
    for (int i = 0; i < depth; ++i) universes *= 256;
    ScalePlan p;
    p.depth = depth;
    p.universes = universes;
    p.addresses = universes * kAddressCount;
    p.canonical = universes * kCanonicalCount;
    p.pairs = universes * kMirrorPairCount;
    p.fixed = universes * kFixedPointCount;
    p.dense_bytes = universes * kPageBytes;
    return p;
}

struct NodePlan {
    std::uint8_t id = 0;
    u128 universes = 0;
    u128 bytes = 0;
    bool fits_budget = false;
};

struct RingPlan {
    int depth = 0;
    int nodes = 0;
    u128 total_universes = 0;
    u128 total_bytes = 0;
    u128 per_node_universes = 0;
    u128 per_node_bytes = 0;
    std::uint64_t node_budget = 0;
    bool all_fit = false;
    std::vector<NodePlan> members;
};

inline RingPlan ring_plan(int depth, int nodes = 5,
                          std::uint64_t node_budget = 7ull * 1024 * 1024 * 1024) {
    RingPlan r;
    r.depth = depth;
    r.nodes = nodes < 1 ? 1 : nodes;
    r.node_budget = node_budget;
    const ScalePlan p = scale_plan(depth);
    r.total_universes = p.universes;
    r.total_bytes = p.dense_bytes;
    r.per_node_universes = (p.universes + static_cast<u128>(r.nodes) - 1) /
                           static_cast<u128>(r.nodes);
    r.per_node_bytes = r.per_node_universes * kPageBytes;
    r.all_fit = r.per_node_bytes <= static_cast<u128>(node_budget);
    for (int i = 0; i < r.nodes; ++i) {
        NodePlan n;
        n.id = static_cast<std::uint8_t>(i);
        n.universes = r.per_node_universes;
        n.bytes = r.per_node_bytes;
        n.fits_budget = n.bytes <= static_cast<u128>(node_budget);
        r.members.push_back(n);
    }
    return r;
}

inline std::uint32_t owner_of(const PageId& page, int nodes) {
    if (nodes < 1) return 0;
    std::uint64_t h = 1469598103934665603ull;
    h ^= page.depth;
    h *= 1099511628211ull;
    for (std::uint8_t i = 0; i < page.depth && i < page.path.size(); ++i) {
        h ^= page.path[i];
        h *= 1099511628211ull;
    }
    return static_cast<std::uint32_t>(h % static_cast<std::uint64_t>(nodes));
}

std::string u128_to_string(u128 v);
std::string human_bytes(u128 v);

} // namespace nanlm
