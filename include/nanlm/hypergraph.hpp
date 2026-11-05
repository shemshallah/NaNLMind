// Palindromic temporal hypergraph.
//
// The ordinary graph is the 32,640 mirror-pair cells: one edge per unordered
// pair of the 256 heads. Hyperedges are first-class objects that connect any
// number of cells, including cells in different universes/spaces. A single
// NaN cell can therefore participate in many relations across many spaces.
//
// Formally:
//   V = all NaN cells (union over all universes)
//   E = ordinary pair connections
//   H = hyperedges, h = (m1..mk; label, weight, epoch)
//   T = temporal transitions (epoch/ledger order)
//   P = palindrome involution (canonicalization + mirror pairing)
//
// Hyperedges are stored at KB resolution; their member lists are Refs, so a
// member may be a bit, byte, word, cell, KB block, page, or superpage.
#pragma once

#include "nanlm/pager.hpp"
#include "nanlm/sha256.hpp"

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace nanlm {

inline constexpr std::uint16_t kHyperDirected = 1u << 0;
inline constexpr std::uint16_t kHyperTemporal = 1u << 1;
inline constexpr std::uint16_t kHyperMirror = 1u << 2;
inline constexpr std::uint16_t kHyperCrossSpace = 1u << 3;
inline constexpr std::uint16_t kHyperLearned = 1u << 4;

struct Hyperedge {
    std::uint32_t id = 0;
    std::uint16_t flags = 0;
    std::uint32_t weight = 65536; // Q16.16
    std::uint64_t label = 0;
    std::uint64_t epoch = 0;
    std::vector<Ref> members;
};

class Hypergraph {
public:
    std::uint32_t add(Hyperedge edge);
    bool remove(std::uint32_t id);
    const Hyperedge* get(std::uint32_t id) const;
    std::vector<std::uint32_t> incident(const Ref& member) const;
    std::vector<Ref> neighbors(const Ref& member) const;
    std::vector<Ref> members_of(std::uint32_t id) const;
    std::size_t size() const { return edges_.size(); }
    std::uint32_t next_id() const { return next_id_; }

    // Temporal slice: hyperedges active at epoch, optionally filtered.
    std::vector<std::uint32_t> at_epoch(std::uint64_t epoch) const;
    std::vector<std::uint32_t> between(std::uint64_t begin, std::uint64_t end) const;

    // Integer hypergraph diffusion. Each incident hyperedge distributes its
    // weight across its members. Returns the next energy map.
    std::unordered_map<Ref, std::int32_t, RefHash>
    diffuse(const std::unordered_map<Ref, std::int32_t, RefHash>& energy) const;

    Hash256 digest() const;
    std::vector<std::uint8_t> serialize() const;
    static Hypergraph from_bytes(const std::uint8_t* data, std::size_t len);

private:
    std::unordered_map<std::uint32_t, Hyperedge> edges_;
    std::unordered_map<Ref, std::vector<std::uint32_t>, RefHash> incidence_;
    std::uint32_t next_id_ = 1;
};

} // namespace nanlm
