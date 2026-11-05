// Temporally split state space and bidirectional memory.
//
// The 256 palindromic fixed points are the "present" anchors. A mirror pair
// {a,b} is a bidirectional temporal relation: S+ stores the forward (past ->
// future) direction, S- stores the reverse (future -> past) direction. The
// ledger supplies the global epoch; this module supplies the local directed
// links, including branches and reversible links.
#pragma once

#include "nanlm/pager.hpp"
#include "nanlm/sha256.hpp"

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace nanlm {

inline constexpr std::uint16_t kTemporalReversible = 1u << 0;
inline constexpr std::uint16_t kTemporalBranch = 1u << 1;
inline constexpr std::uint16_t kTemporalMirror = 1u << 2;
inline constexpr std::uint16_t kTemporalConsolidated = 1u << 3;

struct TemporalLink {
    std::uint32_t id = 0;
    Ref past{};
    Ref future{};
    std::uint64_t epoch = 0;
    std::uint16_t flags = 0;
    std::uint32_t weight = 65536; // Q16.16
};

class BidirectionalMemory {
public:
    std::uint32_t link(const Ref& past, const Ref& future, std::uint64_t epoch = 0,
                       std::uint16_t flags = 0, std::uint32_t weight = 65536);
    bool remove(std::uint32_t id);

    bool forward(const Ref& past, Ref& future, std::uint64_t at_epoch = UINT64_MAX) const;
    bool backward(const Ref& future, Ref& past, std::uint64_t at_epoch = UINT64_MAX) const;

    std::vector<Ref> futures(const Ref& past) const;
    std::vector<Ref> pasts(const Ref& future) const;
    std::vector<TemporalLink> links() const;
    std::vector<TemporalLink> at_epoch(std::uint64_t epoch) const;
    std::vector<TemporalLink> between(std::uint64_t begin, std::uint64_t end) const;

    std::size_t size() const { return links_.size(); }
    Hash256 digest() const;

private:
    std::unordered_map<std::uint32_t, TemporalLink> links_;
    std::unordered_map<Ref, std::vector<std::uint32_t>, RefHash> forward_index_;
    std::unordered_map<Ref, std::vector<std::uint32_t>, RefHash> backward_index_;
    std::uint32_t next_id_ = 1;
};

} // namespace nanlm
