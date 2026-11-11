// Paged 255 x 1 MiB head-weight arena.
//
// This is host page storage only; it does not execute model mathematics.
// The guest remains the only place where a head block performs QKV/MLP,
// attention, Poincare or credit arithmetic.  Pages are demand-mapped so the
// process does not need 255 MiB resident at startup.
#pragma once
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>

#if defined(__linux__) || defined(__ANDROID__)
#include <sys/mman.h>
#include <unistd.h>
#endif

namespace nanlm {

class HeadPageArena {
public:
    static constexpr std::size_t kHeadCount = 255;
    static constexpr std::size_t kPageBytes = 1024u * 1024u;
    static constexpr std::size_t kTotalBytes = kHeadCount * kPageBytes;

    HeadPageArena() {
#if defined(__linux__) || defined(__ANDROID__)
        base_ = static_cast<std::uint8_t*>(
            ::mmap(nullptr, kTotalBytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0));
        if (base_ == MAP_FAILED) {
            base_ = nullptr;
            throw std::runtime_error("head page arena mmap failed");
        }
#else
        throw std::runtime_error("head page arena requires mmap");
#endif
    }

    ~HeadPageArena() {
#if defined(__linux__) || defined(__ANDROID__)
        if (base_) ::munmap(base_, kTotalBytes);
#endif
    }

    HeadPageArena(const HeadPageArena&) = delete;
    HeadPageArena& operator=(const HeadPageArena&) = delete;

    bool valid() const noexcept { return base_ != nullptr; }
    static constexpr std::size_t page_offset(std::size_t head) noexcept {
        return head * kPageBytes;
    }

    std::uint8_t* page(std::size_t head) {
        if (head >= kHeadCount || !base_) throw std::out_of_range("head page index");
        return base_ + page_offset(head);
    }
    const std::uint8_t* page(std::size_t head) const {
        if (head >= kHeadCount || !base_) throw std::out_of_range("head page index");
        return base_ + page_offset(head);
    }

    void clear_page(std::size_t head) {
        std::uint8_t* p = page(head);
        for (std::size_t i = 0; i < kPageBytes; ++i) p[i] = 0;
    }

    void load_page(std::size_t head, const std::uint8_t* data,
                   std::size_t bytes) {
        if (!data || bytes != kPageBytes)
            throw std::invalid_argument("head page must be exactly 1 MiB");
        std::uint8_t* p = page(head);
        for (std::size_t i = 0; i < kPageBytes; ++i) p[i] = data[i];
    }

private:
    std::uint8_t* base_ = nullptr;
};

} // namespace nanlm
