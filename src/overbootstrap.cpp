#include "nanlm/overbootstrap.hpp"

#include <algorithm>
#include <cstring>
#include <vector>
#include <sys/mman.h>

namespace nanlm {

OverbootstrapMap::OverbootstrapMap() {
#if defined(__ANDROID__)
    // Android is an 8 MiB edge universe. It must never map the bootstrap bank.
    base_ = nullptr;
#else
    void* p = mmap(nullptr, kOverbootstrapBytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (p != MAP_FAILED) base_ = static_cast<std::uint8_t*>(p);
#endif
}

OverbootstrapMap::~OverbootstrapMap() {
    if (base_) munmap(base_, kOverbootstrapBytes);
}

bool OverbootstrapMap::prefault() {
    if (!base_) return false;
    for (std::uint32_t page = 0; page < kOverbootstrapPages; ++page) {
        if (!ensure_page(page)) return false;
    }
    return true;
}

bool OverbootstrapMap::ensure_page(std::uint32_t page) {
    if (!base_ || page >= kOverbootstrapPages) return false;
    if (!touched_[page]) {
        std::memset(base_ + static_cast<std::size_t>(page) * kOverbootstrapPageBytes,
                    0, kOverbootstrapPageBytes);
        touched_[page] = true;
        resident_bytes_ += kOverbootstrapPageBytes;
    }
    if (!dirty_[page]) {
        dirty_[page] = true;
        ++dirty_pages_;
    }
    return true;
}

std::uint8_t* OverbootstrapMap::page_data(std::uint32_t page) {
    if (!base_ || page >= kOverbootstrapPages || !touched_[page]) return nullptr;
    return base_ + static_cast<std::size_t>(page) * kOverbootstrapPageBytes;
}

const std::uint8_t* OverbootstrapMap::page_data(std::uint32_t page) const {
    if (!base_ || page >= kOverbootstrapPages || !touched_[page]) return nullptr;
    return base_ + static_cast<std::size_t>(page) * kOverbootstrapPageBytes;
}

bool OverbootstrapMap::zero(const RegionRef& region) {
    if (!region.valid()) return false;
    if (region.page + (region.offset + region.bytes + kOverbootstrapPageBytes - 1) /
                           kOverbootstrapPageBytes > kOverbootstrapPages) {
        return false;
    }
    std::vector<std::uint8_t> zeros(region.bytes, 0);
    return write(region, 0, zeros.data(), zeros.size());
}

bool OverbootstrapMap::write(const RegionRef& region, std::uint32_t offset,
                             const std::uint8_t* data, std::size_t bytes) {
    if (!base_ || !region.valid() || !data) return false;
    if (offset > region.bytes || bytes > region.bytes - offset) return false;
    std::size_t done = 0;
    while (done < bytes) {
        const std::uint32_t absolute = region.offset + offset + static_cast<std::uint32_t>(done);
        const std::uint32_t page = region.page + absolute / kOverbootstrapPageBytes;
        const std::uint32_t in_page = absolute % kOverbootstrapPageBytes;
        if (page >= kOverbootstrapPages) return false;
        if (!ensure_page(page)) return false;
        const std::size_t n = std::min<std::size_t>(
            bytes - done, kOverbootstrapPageBytes - in_page);
        std::memcpy(page_data(page) + in_page, data + done, n);
        done += n;
    }
    return true;
}

bool OverbootstrapMap::read(const RegionRef& region, std::uint32_t offset,
                            std::uint8_t* out, std::size_t bytes) const {
    if (!base_ || !region.valid() || !out) return false;
    if (offset > region.bytes || bytes > region.bytes - offset) return false;
    std::size_t done = 0;
    while (done < bytes) {
        const std::uint32_t absolute = region.offset + offset + static_cast<std::uint32_t>(done);
        const std::uint32_t page = region.page + absolute / kOverbootstrapPageBytes;
        const std::uint32_t in_page = absolute % kOverbootstrapPageBytes;
        const std::uint8_t* p = page_data(page);
        if (!p) {
            // Dense mapping: untouched pages read as zero.
            std::memset(out + done, 0, std::min<std::size_t>(bytes - done,
                                                            kOverbootstrapPageBytes - in_page));
            done += std::min<std::size_t>(bytes - done, kOverbootstrapPageBytes - in_page);
            continue;
        }
        const std::size_t n = std::min<std::size_t>(
            bytes - done, kOverbootstrapPageBytes - in_page);
        std::memcpy(out + done, p + in_page, n);
        done += n;
    }
    return true;
}

bool OverbootstrapMap::write_u64(const RegionRef& region, std::uint32_t offset,
                                 std::uint64_t value) {
    return write(region, offset, reinterpret_cast<const std::uint8_t*>(&value),
                 sizeof(value));
}

bool OverbootstrapMap::read_u64(const RegionRef& region, std::uint32_t offset,
                                std::uint64_t& value) const {
    return read(region, offset, reinterpret_cast<std::uint8_t*>(&value),
                sizeof(value));
}

std::size_t OverbootstrapMap::resident_pages() const {
    std::size_t n = 0;
    for (bool t : touched_) if (t) ++n;
    return n;
}

bool OverbootstrapMap::commit() {
    for (auto& d : dirty_) d = false;
    dirty_pages_ = 0;
    ++generation_;
    return true;
}

Hash256 OverbootstrapMap::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'O', 'V', 'B', '0', '1', ' '};
    h.update(tag, sizeof(tag));
    const std::uint64_t virtual_bytes = kOverbootstrapBytes;
    const std::uint32_t page_bytes = kOverbootstrapPageBytes;
    h.update(&virtual_bytes, sizeof(virtual_bytes));
    h.update(&page_bytes, sizeof(page_bytes));
    h.update(&generation_, sizeof(generation_));
    for (std::uint32_t p = 0; p < kOverbootstrapPages; ++p) {
        const std::uint8_t* data = page_data(p);
        if (!data) continue;
        h.update(&p, sizeof(p));
        h.update(data, kOverbootstrapPageBytes);
    }
    return h.final();
}

bool RunnerMap::initialize(OverbootstrapMap& map) {
    universe = RegionRef{0, 0, kOverbootstrapPageBytes};
    head_arena = RegionRef{1, 0, kOverbootstrapPageBytes};
    if (!map.zero(universe) || !map.zero(head_arena)) return false;
    for (std::uint16_t h = 0; h < kOverbootstrapHeadCount; ++h) {
        heads[h] = RegionRef{1, static_cast<std::uint32_t>(h) * kHeadRegionBytes,
                             kHeadRegionBytes};
    }
    return true;
}

bool RunnerMap::write_head(OverbootstrapMap& map, std::uint16_t head,
                           std::uint32_t offset, const std::uint8_t* data,
                           std::size_t bytes) const {
    if (head >= kOverbootstrapHeadCount) return false;
    return map.write(heads[head], offset, data, bytes);
}

bool RunnerMap::read_head(const OverbootstrapMap& map, std::uint16_t head,
                          std::uint32_t offset, std::uint8_t* out,
                          std::size_t bytes) const {
    if (head >= kOverbootstrapHeadCount) return false;
    return map.read(heads[head], offset, out, bytes);
}

RunnerRing::RunnerRing() {
    assign();
}

void RunnerRing::assign() {
    for (std::uint16_t h = 0; h < kOverbootstrapHeadCount; ++h) {
        owner_[h] = static_cast<std::uint8_t>(h % kRunnerRingSlots);
    }
}

std::uint8_t RunnerRing::owner(std::uint16_t head) const {
    if (head >= kOverbootstrapHeadCount) return 0xFFu;
    return owner_[head];
}

std::array<std::uint16_t, kRunnerRingSlots> RunnerRing::counts() const {
    std::array<std::uint16_t, kRunnerRingSlots> out{};
    for (std::uint8_t o : owner_) ++out[o];
    return out;
}

} // namespace nanlm
