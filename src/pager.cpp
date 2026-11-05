#include "nanlm/pager.hpp"

#include <algorithm>
#include <cstring>
#include <sstream>

namespace nanlm {

std::string PageId::to_string() const {
    if (depth == 0) return "root";
    std::ostringstream os;
    for (std::uint8_t i = 0; i < depth; ++i) {
        if (i != 0) os << '.';
        os << static_cast<unsigned>(path[i]);
    }
    return os.str();
}

std::size_t PageIdHash::operator()(const PageId& id) const noexcept {
    std::uint64_t h = 1469598103934665603ull;
    h ^= id.depth;
    h *= 1099511628211ull;
    for (std::uint8_t i = 0; i < id.depth && i < id.path.size(); ++i) {
        h ^= id.path[i];
        h *= 1099511628211ull;
    }
    return static_cast<std::size_t>(h);
}

std::uint64_t BitAddress::encode() const {
    std::uint64_t v = bit & 0x3Fu;
    v |= static_cast<std::uint64_t>(word & 0x3u) << 6;
    v |= static_cast<std::uint64_t>(cell) << 8;
    for (std::uint8_t i = 0; i < 4; ++i) {
        v |= static_cast<std::uint64_t>(page.path[i]) << (24 + i * 8);
    }
    v |= static_cast<std::uint64_t>(page.depth & 0x7u) << 56;
    return v;
}

BitAddress BitAddress::decode(std::uint64_t value) {
    BitAddress a;
    a.bit = static_cast<std::uint8_t>(value & 0x3Fu);
    a.word = static_cast<std::uint8_t>((value >> 6) & 0x3u);
    a.cell = static_cast<std::uint16_t>((value >> 8) & 0xFFFFu);
    for (std::uint8_t i = 0; i < 4; ++i) {
        a.page.path[i] = static_cast<std::uint8_t>((value >> (24 + i * 8)) & 0xFFu);
    }
    a.page.depth = static_cast<std::uint8_t>((value >> 56) & 0x7u);
    return a;
}

std::string Ref::to_string() const {
    const char* k = "none";
    switch (kind) {
        case Kind::None: k = "none"; break;
        case Kind::Bit: k = "bit"; break;
        case Kind::Byte: k = "byte"; break;
        case Kind::Word: k = "word"; break;
        case Kind::Cell: k = "cell"; break;
        case Kind::Kilobyte: k = "kb"; break;
        case Kind::Page: k = "page"; break;
        case Kind::SuperPage: k = "superpage"; break;
    }
    std::ostringstream os;
    os << k << '@' << page.to_string() << ':' << offset;
    return os.str();
}

std::size_t RefHash::operator()(const Ref& r) const noexcept {
    std::uint64_t h = 1469598103934665603ull;
    h ^= static_cast<std::uint64_t>(r.kind);
    h *= 1099511628211ull;
    h ^= r.offset;
    h *= 1099511628211ull;
    h ^= PageIdHash{}(r.page);
    return static_cast<std::size_t>(h);
}

// ---------------------------------------------------------------------------
// MemoryBackend
// ---------------------------------------------------------------------------
bool MemoryBackend::read(const PageId& id, std::vector<std::uint8_t>& out) {
    auto it = pages_.find(id);
    if (it == pages_.end()) return false;
    out = it->second;
    return true;
}

bool MemoryBackend::write(const PageId& id, const std::vector<std::uint8_t>& in) {
    pages_[id] = in;
    return true;
}

bool MemoryBackend::contains(const PageId& id) const {
    return pages_.find(id) != pages_.end();
}

Hash256 MemoryBackend::hash(const PageId& id) const {
    auto it = pages_.find(id);
    if (it == pages_.end()) return {};
    return Sha256::hash(it->second.data(), it->second.size());
}

std::vector<PageId> MemoryBackend::list() const {
    std::vector<PageId> out;
    out.reserve(pages_.size());
    for (const auto& kv : pages_) out.push_back(kv.first);
    std::sort(out.begin(), out.end(), [](const PageId& a, const PageId& b) {
        return a.to_string() < b.to_string();
    });
    return out;
}

// ---------------------------------------------------------------------------
// PageTable
// ---------------------------------------------------------------------------
PageTable::PageTable() = default;

std::uint64_t PageTable::bit_mask(std::uint16_t cell) {
    return 1ull << (cell & 63u);
}

PageTable::Entry* PageTable::get(const PageId& id) {
    auto it = pages_.find(id);
    return it == pages_.end() ? nullptr : &it->second;
}

const PageTable::Entry* PageTable::get(const PageId& id) const {
    auto it = pages_.find(id);
    return it == pages_.end() ? nullptr : &it->second;
}

bool PageTable::map(const PageId& id, PagePtr page, std::uint8_t perms) {
    if (!page) return false;
    Entry e;
    e.page = std::move(page);
    e.perms = perms;
    e.version = 1;
    e.dirty = false;
    e.dirty_cells.assign((kCanonicalCount + 63) / 64, 0);
    e.base_hash = e.page->digest();
    pages_[id] = std::move(e);
    return true;
}

bool PageTable::replace(const PageId& id, PagePtr page, const Hash256& expected_base) {
    Entry* e = get(id);
    if (!e || !page) return false;
    if (!(e->page->digest() == expected_base)) return false;
    e->page = std::move(page);
    e->dirty = false;
    std::fill(e->dirty_cells.begin(), e->dirty_cells.end(), 0);
    e->page->clear_address_dirty();
    e->base_hash = e->page->digest();
    ++e->version;
    return true;
}

bool PageTable::unmap(const PageId& id) { return pages_.erase(id) != 0; }

bool PageTable::contains(const PageId& id) const { return get(id) != nullptr; }

PageTable::PagePtr PageTable::resolve(const PageId& id) {
    Entry* e = get(id);
    return e ? e->page : nullptr;
}

const PageTable::Entry* PageTable::entry(const PageId& id) const { return get(id); }

bool PageTable::ensure_writable(const PageId& id, Entry& entry) {
    if ((entry.perms & kPermWrite) == 0) return false;
    if (entry.page.use_count() > 1) {
        auto clone = std::make_shared<Universe>(*entry.page);
        entry.page = std::move(clone);
        ++entry.version;
    }
    (void)id;
    return true;
}

void PageTable::mark_dirty(Entry& entry, std::uint16_t cell) {
    const std::uint32_t idx = entry.page->index_of_addr(cell);
    if (idx >= kCanonicalCount) return;
    entry.dirty_cells[idx >> 6] |= bit_mask(static_cast<std::uint16_t>(idx));
    entry.page->mark_address_dirty(cell);
    entry.dirty = true;
}

bool PageTable::read_bit(const BitAddress& address, bool& out) const {
    const Entry* e = get(address.page);
    if (!e || address.word > 3 || address.bit > 63) return false;
    const NanCell& cell = e->page->at_addr(address.cell);
    const std::uint64_t word = cell.words[address.word].raw;
    out = ((word >> address.bit) & 1ull) != 0;
    return true;
}

bool PageTable::write_bit(const BitAddress& address, bool value, bool cow) {
    Entry* e = get(address.page);
    if (!e || address.word > 3 || address.bit > 63) return false;
    if (cow && !ensure_writable(address.page, *e)) return false;
    if ((e->perms & kPermWrite) == 0) return false;

    NanCell& cell = e->page->at_addr(address.cell);
    std::uint64_t& word = cell.words[address.word].raw;
    const std::uint64_t mask = 1ull << address.bit;
    if (value) word |= mask;
    else word &= ~mask;
    mark_dirty(*e, address.cell);
    return true;
}

bool PageTable::read_byte(const ByteAddress& address, std::uint8_t& out) const {
    const Entry* e = get(address.page);
    if (!e || address.word > 3 || address.byte > 7) return false;
    const NanCell& cell = e->page->at_addr(address.cell);
    out = static_cast<std::uint8_t>((cell.words[address.word].raw >> (address.byte * 8)) & 0xFFu);
    return true;
}

bool PageTable::write_byte(const ByteAddress& address, std::uint8_t value, bool cow) {
    Entry* e = get(address.page);
    if (!e || address.word > 3 || address.byte > 7) return false;
    if (cow && !ensure_writable(address.page, *e)) return false;
    if ((e->perms & kPermWrite) == 0) return false;

    NanCell& cell = e->page->at_addr(address.cell);
    std::uint64_t& word = cell.words[address.word].raw;
    const unsigned shift = address.byte * 8u;
    word = (word & ~(0xFFull << shift)) | (static_cast<std::uint64_t>(value) << shift);
    mark_dirty(*e, address.cell);
    return true;
}

bool PageTable::read_word(const PageId& page, std::uint16_t cell, std::uint8_t word,
                          NanWord& out) const {
    const Entry* e = get(page);
    if (!e || word > 3) return false;
    out = e->page->at_addr(cell).words[word];
    return true;
}

bool PageTable::write_word(const PageId& page, std::uint16_t cell, std::uint8_t word,
                           NanWord value, bool cow) {
    Entry* e = get(page);
    if (!e || word > 3) return false;
    if (cow && !ensure_writable(page, *e)) return false;
    if ((e->perms & kPermWrite) == 0) return false;
    e->page->at_addr(cell).words[word] = value;
    mark_dirty(*e, cell);
    return true;
}

bool PageTable::is_dirty(const PageId& id) const {
    const Entry* e = get(id);
    return e && e->dirty;
}

std::size_t PageTable::dirty_cell_count(const PageId& id) const {
    const Entry* e = get(id);
    if (!e) return 0;
    std::size_t n = 0;
    for (std::uint64_t w : e->dirty_cells) n += static_cast<std::size_t>(std::popcount(w));
    return n;
}

bool PageTable::flush(const PageId& id) {
    Entry* e = get(id);
    if (!e) return false;
    std::fill(e->dirty_cells.begin(), e->dirty_cells.end(), 0);
    e->page->clear_address_dirty();
    e->dirty = false;
    e->base_hash = e->page->digest();
    ++e->version;
    return true;
}

std::vector<PageId> PageTable::pages() const {
    std::vector<PageId> out;
    out.reserve(pages_.size());
    for (const auto& kv : pages_) out.push_back(kv.first);
    std::sort(out.begin(), out.end(), [](const PageId& a, const PageId& b) {
        return a.to_string() < b.to_string();
    });
    return out;
}

Hash256 PageTable::root_hash() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'R', 'O', 'O', 'T', '1'};
    h.update(tag, sizeof(tag));
    for (const PageId& id : pages()) {
        const std::uint8_t d = id.depth;
        h.update(&d, 1);
        h.update(id.path.data(), id.path.size());
        const Entry* e = get(id);
        const Hash256 ph = e->page->digest();
        h.update(ph.data(), ph.size());
    }
    return h.final();
}

bool PageTable::flush_to(StorageBackend& backend) {
    for (const PageId& id : pages()) {
        const Entry* e = get(id);
        if (!e) continue;
        if (!backend.write(id, e->page->serialize())) return false;
    }
    return true;
}

bool PageTable::load_from(StorageBackend& backend) {
    for (const PageId& id : backend.list()) {
        std::vector<std::uint8_t> bytes;
        if (!backend.read(id, bytes)) return false;
        auto u = Universe::from_bytes(bytes.data(), bytes.size());
        if (!u) return false;
        if (!map(id, std::move(u))) return false;
    }
    return true;
}

} // namespace nanlm
