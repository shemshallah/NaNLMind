// Sparse 2 GiB overbootstrap register and 8 MiB runner mapping.
//
// The map is virtual. Only touched 8 MiB pages are allocated. This lets the
// bootstrap runner host the 8 MiB universe and 256 head regions without
// reserving 2 GiB in tests.
#pragma once

#include "nanlm/sha256.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace nanlm {

inline constexpr std::uint64_t kOverbootstrapBytes = 2ull * 1024ull * 1024ull * 1024ull;
inline constexpr std::uint32_t kOverbootstrapPageBytes = 8u * 1024u * 1024u;
inline constexpr std::uint32_t kOverbootstrapPages = 256;
inline constexpr std::uint32_t kHeadRegionBytes = 32u * 1024u;
inline constexpr std::uint16_t kOverbootstrapHeadCount = 256;
inline constexpr std::uint8_t kRunnerRingSlots = 6;

static_assert(kOverbootstrapBytes ==
              static_cast<std::uint64_t>(kOverbootstrapPages) * kOverbootstrapPageBytes);
static_assert(static_cast<std::uint64_t>(kOverbootstrapHeadCount) * kHeadRegionBytes ==
              kOverbootstrapPageBytes);

struct RegionRef {
    std::uint32_t page = 0;
    std::uint32_t offset = 0;
    std::uint32_t bytes = 0;

    bool valid() const { return bytes != 0; }
};

class OverbootstrapMap {
public:
    OverbootstrapMap();
    ~OverbootstrapMap();
    OverbootstrapMap(const OverbootstrapMap&) = delete;
    OverbootstrapMap& operator=(const OverbootstrapMap&) = delete;

    bool valid() const { return base_ != nullptr; }
    // Commit every page in the 2 GiB region. This is the full-density runner
    // mode; Android never calls it.
    bool prefault();
    bool zero(const RegionRef& region);
    bool write(const RegionRef& region, std::uint32_t offset,
               const std::uint8_t* data, std::size_t bytes);
    bool read(const RegionRef& region, std::uint32_t offset,
              std::uint8_t* out, std::size_t bytes) const;
    bool write_u64(const RegionRef& region, std::uint32_t offset, std::uint64_t value);
    bool read_u64(const RegionRef& region, std::uint32_t offset, std::uint64_t& value) const;

    std::uint64_t virtual_bytes() const { return kOverbootstrapBytes; }
    std::uint32_t page_bytes() const { return kOverbootstrapPageBytes; }
    std::uint32_t page_count() const { return kOverbootstrapPages; }
    std::uint64_t resident_bytes() const { return resident_bytes_; }
    std::size_t resident_pages() const;
    std::size_t dirty_pages() const { return dirty_pages_; }
    std::uint64_t generation() const { return generation_; }
    bool commit();
    Hash256 digest() const;

private:
    bool ensure_page(std::uint32_t page);
    std::uint8_t* page_data(std::uint32_t page);
    const std::uint8_t* page_data(std::uint32_t page) const;

    std::uint8_t* base_ = nullptr;
    std::array<bool, kOverbootstrapPages> touched_{};
    std::array<bool, kOverbootstrapPages> dirty_{};
    std::uint64_t resident_bytes_ = 0;
    std::size_t dirty_pages_ = 0;
    std::uint64_t generation_ = 0;
};

struct RunnerMap {
    RegionRef universe{};
    RegionRef head_arena{};
    std::array<RegionRef, kOverbootstrapHeadCount> heads{};

    bool initialize(OverbootstrapMap& map);
    bool write_head(OverbootstrapMap& map, std::uint16_t head,
                    std::uint32_t offset, const std::uint8_t* data,
                    std::size_t bytes) const;
    bool read_head(const OverbootstrapMap& map, std::uint16_t head,
                   std::uint32_t offset, std::uint8_t* out,
                   std::size_t bytes) const;
};

class RunnerRing {
public:
    RunnerRing();
    void assign();
    std::uint8_t owner(std::uint16_t head) const;
    std::array<std::uint16_t, kRunnerRingSlots> counts() const;

private:
    std::array<std::uint8_t, kOverbootstrapHeadCount> owner_{};
};

} // namespace nanlm
