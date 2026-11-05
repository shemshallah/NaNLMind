// Hierarchical page table for bit/byte/word/cell/KB/page addressing.
//
// A PageId is a path of head indices. Depth 0 is the root universe; depth 1
// is the child universe owned by head h; depth d is a path of d heads.
// Multiple PageIds may alias the same Universe; writes clone-on-write.
#pragma once

#include "nanlm/universe.hpp"

#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace nanlm {

inline constexpr std::uint8_t kPermRead = 1u << 0;
inline constexpr std::uint8_t kPermWrite = 1u << 1;
inline constexpr std::uint8_t kPermExec = 1u << 2;
inline constexpr std::uint8_t kPermAll = kPermRead | kPermWrite | kPermExec;

struct PageId {
    std::uint8_t depth = 0;
    std::array<std::uint8_t, 4> path{};

    static PageId root() { return PageId{}; }
    static PageId child(const PageId& parent, std::uint8_t head) {
        PageId p;
        p.depth = static_cast<std::uint8_t>(parent.depth + 1);
        p.path = parent.path;
        if (p.depth <= p.path.size()) p.path[p.depth - 1] = head;
        return p;
    }

    std::string to_string() const;
    bool operator==(const PageId& other) const {
        return depth == other.depth && path == other.path;
    }
};

struct PageIdHash {
    std::size_t operator()(const PageId& id) const noexcept;
};

// A single bit inside a universe register.
struct BitAddress {
    PageId page{};
    std::uint16_t cell = 0;
    std::uint8_t word = 0; // 0..3
    std::uint8_t bit = 0;  // 0..63

    // Compact 59-bit encoding: depth[3] path[32] cell[16] word[2] bit[6].
    std::uint64_t encode() const;
    static BitAddress decode(std::uint64_t value);
    bool operator==(const BitAddress& other) const {
        return page == other.page && cell == other.cell && word == other.word && bit == other.bit;
    }
};

struct ByteAddress {
    PageId page{};
    std::uint16_t cell = 0;
    std::uint8_t word = 0; // 0..3
    std::uint8_t byte = 0; // 0..7
};

// A capability-style reference at a chosen resolution. The same memory can
// be named as one bit, one byte, one 64-bit word, one cell, one 1 KiB block,
// one 4 MiB page, or a 1 GiB superpage (256 pages).
struct Ref {
    enum class Kind : std::uint8_t {
        None = 0,
        Bit,
        Byte,
        Word,
        Cell,
        Kilobyte,
        Page,
        SuperPage,
    };

    Kind kind = Kind::None;
    std::uint8_t flags = 0;
    std::uint64_t offset = 0;
    PageId page{};

    static Ref from_bit(const BitAddress& address) {
        Ref r;
        r.kind = Kind::Bit;
        r.page = address.page;
        r.offset = (static_cast<std::uint64_t>(address.cell) << 8) |
                   (static_cast<std::uint64_t>(address.word) << 6) |
                   static_cast<std::uint64_t>(address.bit);
        return r;
    }

    bool as_bit(BitAddress& out) const {
        if (kind != Kind::Bit) return false;
        out.page = page;
        out.cell = static_cast<std::uint16_t>((offset >> 8) & 0xFFFFu);
        out.word = static_cast<std::uint8_t>((offset >> 6) & 0x3u);
        out.bit = static_cast<std::uint8_t>(offset & 0x3Fu);
        return true;
    }

    std::string to_string() const;
    bool operator==(const Ref& other) const {
        return kind == other.kind && flags == other.flags && offset == other.offset &&
               page == other.page;
    }
};

struct RefHash {
    std::size_t operator()(const Ref& r) const noexcept;
};

class StorageBackend {
public:
    virtual ~StorageBackend() = default;
    virtual bool read(const PageId& id, std::vector<std::uint8_t>& out) = 0;
    virtual bool write(const PageId& id, const std::vector<std::uint8_t>& in) = 0;
    virtual bool contains(const PageId& id) const = 0;
    virtual Hash256 hash(const PageId& id) const = 0;
    virtual std::vector<PageId> list() const = 0;
};

class MemoryBackend final : public StorageBackend {
public:
    bool read(const PageId& id, std::vector<std::uint8_t>& out) override;
    bool write(const PageId& id, const std::vector<std::uint8_t>& in) override;
    bool contains(const PageId& id) const override;
    Hash256 hash(const PageId& id) const override;
    std::vector<PageId> list() const override;

private:
    std::unordered_map<PageId, std::vector<std::uint8_t>, PageIdHash> pages_;
};

class PageTable {
public:
    using PagePtr = std::shared_ptr<Universe>;

    struct Entry {
        PagePtr page;
        std::uint64_t version = 0;
        std::uint8_t perms = kPermAll;
        bool dirty = false;
        std::vector<std::uint64_t> dirty_cells; // one bit per canonical cell
        std::string backing;
        Hash256 base_hash{};
    };

    PageTable();

    bool map(const PageId& id, PagePtr page, std::uint8_t perms = kPermAll);
    bool replace(const PageId& id, PagePtr page, const Hash256& expected_base);
    bool unmap(const PageId& id);
    bool contains(const PageId& id) const;
    PagePtr resolve(const PageId& id);
    const Entry* entry(const PageId& id) const;

    bool read_bit(const BitAddress& address, bool& out) const;
    bool write_bit(const BitAddress& address, bool value, bool cow = true);
    bool read_byte(const ByteAddress& address, std::uint8_t& out) const;
    bool write_byte(const ByteAddress& address, std::uint8_t value, bool cow = true);
    bool read_word(const PageId& page, std::uint16_t cell, std::uint8_t word, NanWord& out) const;
    bool write_word(const PageId& page, std::uint16_t cell, std::uint8_t word, NanWord value,
                    bool cow = true);

    bool is_dirty(const PageId& id) const;
    std::size_t dirty_cell_count(const PageId& id) const;
    bool flush(const PageId& id);
    std::size_t size() const { return pages_.size(); }
    std::vector<PageId> pages() const;
    Hash256 root_hash() const;

    bool flush_to(StorageBackend& backend);
    bool load_from(StorageBackend& backend);

private:
    Entry* get(const PageId& id);
    const Entry* get(const PageId& id) const;
    bool ensure_writable(const PageId& id, Entry& entry);
    void mark_dirty(Entry& entry, std::uint16_t cell);
    static std::uint64_t bit_mask(std::uint16_t cell);

    std::unordered_map<PageId, Entry, PageIdHash> pages_;
};

} // namespace nanlm
