// Host-side page loader for the paged 255 x 1 MiB head bank.
//
// The loader copies a file-independent 1 MiB page into one of 20 guest slots.
// Guest code remains the only owner of head arithmetic; this class only
// transports bytes and maintains an LRU slot map.  Each 32-bit payload word is
// stored in one NaN word, so a 1 MiB page occupies 2 MiB of guest address
// space.
#pragma once
#include "nanlm/head_page_arena.hpp"
#include "nanlm/raw_field.hpp"

#include <array>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace nanlm {

class HeadPageLoader {
public:
    static constexpr std::size_t kSlots = 20;  // 16-page baseline + 4 frontier slots
    static constexpr std::size_t kWordsPerPage = 262144; // 1 MiB / 4 bytes
    static constexpr std::uint32_t kSlotBase = 0x00800000u;
    static constexpr std::uint32_t kSlotStride = 0x00040000u;

    explicit HeadPageLoader(RawFieldVM& vm, HeadPageArena& arena)
        : vm_(vm), arena_(arena) {
        slots_.fill(0xFFu);
        last_used_.fill(0);
    }

    static constexpr std::uint32_t slot_base(std::size_t slot) {
        if (slot >= kSlots) throw std::out_of_range("head page slot");
        return kSlotBase + static_cast<std::uint32_t>(slot) * kSlotStride;
    }

    // Load head 0..254 into a slot. Returns the slot. Evicts the least
    // recently used slot when all 20 are occupied.
    std::size_t load(std::size_t head) {
        if (head >= HeadPageArena::kHeadCount)
            throw std::out_of_range("head page index");
        for (std::size_t slot = 0; slot < kSlots; ++slot) {
            if (slots_[slot] == head) {
                last_used_[slot] = ++clock_;
                return slot;
            }
        }
        std::size_t slot = kSlots;
        for (std::size_t i = 0; i < kSlots; ++i) {
            if (slots_[i] == 0xFFu) { slot = i; break; }
        }
        if (slot == kSlots) {
            slot = 0;
            for (std::size_t i = 1; i < kSlots; ++i)
                if (last_used_[i] < last_used_[slot]) slot = i;
        }
        write_page(slot, head);
        slots_[slot] = static_cast<std::uint8_t>(head);
        last_used_[slot] = ++clock_;
        return slot;
    }

    bool resident(std::size_t head) const {
        for (std::uint8_t slot : slots_) if (slot == head) return true;
        return false;
    }

    std::size_t resident_count() const {
        std::size_t n = 0;
        for (std::uint8_t slot : slots_) if (slot != 0xFFu) ++n;
        return n;
    }

    int slot_of(std::size_t head) const {
        for (std::size_t slot = 0; slot < kSlots; ++slot)
            if (slots_[slot] == head) return static_cast<int>(slot);
        return -1;
    }

    void clear() {
        slots_.fill(0xFFu);
        last_used_.fill(0);
    }

    // Copy a resident slot back to packed 1 MiB page bytes.  This is host
    // transport only; the guest remains the writer of any page math.
    std::vector<std::uint8_t> export_page(std::size_t slot) const {
        if (slot >= kSlots) throw std::out_of_range("head page slot");
        const std::uint32_t base = slot_base(slot);
        std::vector<std::uint8_t> out(kWordsPerPage * 4u);
        for (std::size_t i = 0; i < kWordsPerPage; ++i) {
            const std::uint32_t word = vm_.read_payload_word(
                base + static_cast<std::uint32_t>(i));
            const std::size_t off = i * 4u;
            out[off + 0] = static_cast<std::uint8_t>(word & 0xFFu);
            out[off + 1] = static_cast<std::uint8_t>((word >> 8) & 0xFFu);
            out[off + 2] = static_cast<std::uint8_t>((word >> 16) & 0xFFu);
            out[off + 3] = static_cast<std::uint8_t>((word >> 24) & 0xFFu);
        }
        return out;
    }

private:
    void write_page(std::size_t slot, std::size_t head) {
        const std::uint8_t* src = arena_.page(head);
        const std::uint32_t base = slot_base(slot);
        for (std::size_t i = 0; i < kWordsPerPage; ++i) {
            const std::size_t off = i * 4;
            const std::uint32_t word =
                static_cast<std::uint32_t>(src[off]) |
                (static_cast<std::uint32_t>(src[off + 1]) << 8) |
                (static_cast<std::uint32_t>(src[off + 2]) << 16) |
                (static_cast<std::uint32_t>(src[off + 3]) << 24);
            if (!vm_.write_payload_word(base + static_cast<std::uint32_t>(i), word))
                throw std::runtime_error("head page guest write failed");
        }
    }

    RawFieldVM& vm_;
    HeadPageArena& arena_;
    std::array<std::uint8_t, kSlots> slots_{};
    std::array<std::uint64_t, kSlots> last_used_{};
    std::uint64_t clock_ = 0;
};

} // namespace nanlm
