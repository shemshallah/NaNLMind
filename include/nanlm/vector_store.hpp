// Addressable vector bins and macro-associative memory.
//
// This is the layer between the scalar topology and a word model:
//
//   address/point  --portal-->  bin(slot)  --vector-->  dot-product recall
//
// A bin is a formatted, immutable-by-generation block of int16 vectors. A point
// (for example 16254) can be bound to a bin without changing the point's address
// algebra. Heads and a word layer read the same BinRef.
//
// This is not a transformer. It is a deterministic integer associative memory.
#pragma once

#include "nanlm/sha256.hpp"
#include "nanlm/universe.hpp"

#include <array>
#include <cstdint>
#include <vector>

namespace nanlm {

using BinId = std::uint32_t;
inline constexpr BinId kInvalidBin = 0;
inline constexpr std::uint32_t kVectorBinMagic = 0x4E4C5642u; // "NLVB"

struct BinHeader {
    std::uint32_t magic = kVectorBinMagic;
    std::uint16_t dim = 0;
    std::uint16_t count = 0;
    std::uint16_t dtype = 1; // 1 = int16
    std::uint16_t flags = 0;
    std::uint32_t generation = 0;
    std::uint64_t payload_bytes = 0;
};

struct BinRef {
    BinId bin = kInvalidBin;
    std::uint16_t slot = 0;

    bool valid() const { return bin != kInvalidBin; }
    bool operator==(const BinRef& other) const {
        return bin == other.bin && slot == other.slot;
    }
};

struct Vec2BinRefHash {
    std::size_t operator()(const BinRef& r) const noexcept {
        return (static_cast<std::size_t>(r.bin) << 16) ^ r.slot;
    }
};

class BinStore {
public:
    BinId create(std::uint16_t dim, std::uint16_t count,
                 std::int16_t fill = 0);
    bool write(BinId bin, std::uint16_t slot, const std::vector<std::int16_t>& values);
    bool read(BinId bin, std::uint16_t slot, std::vector<std::int16_t>& out) const;
    const BinHeader* header(BinId bin) const;
    const std::int16_t* vector(BinId bin, std::uint16_t slot) const;
    std::size_t size() const { return bins_.empty() ? 0 : bins_.size() - 1; }
    Hash256 digest() const;

private:
    struct Bin {
        BinHeader header;
        std::vector<std::int16_t> values;
    };
    std::vector<Bin> bins_{{}}; // index 0 is the invalid bin
};

// A point is an address in the 65,536-point chart. The portal map is separate
// from the point's scalar cell, so mapping a point to a bin does not move it.
class PointBinMap {
public:
    bool bind(std::uint16_t point, BinRef ref);
    bool unbind(std::uint16_t point);
    BinRef resolve(std::uint16_t point) const;
    std::size_t bindings() const;

private:
    std::array<BinRef, 65536> map_{};
};

struct AssocEntry {
    std::uint32_t id = 0;
    std::vector<BinRef> keys;   // macro key: all key vectors contribute
    std::vector<BinRef> values; // retrieved value bins
    std::uint32_t weight = 65536; // Q16.16
    std::uint64_t label = 0;
    std::uint64_t epoch = 0;
};

struct AssocMatch {
    std::uint32_t id = 0;
    std::int64_t score = 0;
    std::vector<BinRef> values;
};

class AssocMemory {
public:
    explicit AssocMemory(BinStore& store) : store_(&store) {}

    std::uint32_t bind(const std::vector<BinRef>& keys,
                       const std::vector<BinRef>& values,
                       std::uint32_t weight = 65536,
                       std::uint64_t label = 0,
                       std::uint64_t epoch = 0);
    bool remove(std::uint32_t id);
    const AssocEntry* get(std::uint32_t id) const;
    std::size_t size() const { return entries_.size(); }

    std::vector<AssocMatch> recall(const std::vector<std::int16_t>& query,
                                   std::size_t top_k = 1) const;
    // Read a query vector from a head's 768-byte work scratchpad. The values
    // are little-endian int16; this is the head-to-vector handoff.
    std::vector<AssocMatch> recall_from_head(const HeadScratch& scratch,
                                             std::uint16_t dim,
                                             std::size_t top_k = 1) const;

    Hash256 digest() const;

private:
    std::int64_t score(const AssocEntry& entry,
                       const std::vector<std::int16_t>& query) const;
    BinStore* store_;
    std::vector<AssocEntry> entries_;
    std::uint32_t next_id_ = 1;
};

} // namespace nanlm
