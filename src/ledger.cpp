#include "nanlm/ledger.hpp"

#include <cstring>
#include <sstream>

namespace nanlm {
namespace {

constexpr char kLedgerMagic[8] = {'N', 'L', 'M', 'L', 'E', 'D', 'G', '2'};
constexpr std::size_t kEventWireBytes = 154;

void put_u64(std::vector<std::uint8_t>& out, std::uint64_t v) {
    for (int i = 0; i < 8; ++i) out.push_back(static_cast<std::uint8_t>((v >> (i * 8)) & 0xFFu));
}

Hash256 event_hash(const Hash256& parent, const Event& e) {
    std::vector<std::uint8_t> buf;
    buf.reserve(8 + 8 + 2 + 8 + 32 + 32 + 32);
    put_u64(buf, e.seq);
    put_u64(buf, e.epoch);
    buf.push_back(e.actor);
    buf.push_back(e.kind);
    put_u64(buf, e.addr);
    buf.insert(buf.end(), parent.begin(), parent.end());
    buf.insert(buf.end(), e.before.begin(), e.before.end());
    buf.insert(buf.end(), e.after.begin(), e.after.end());
    return Sha256::hash(buf.data(), buf.size());
}

bool read_u64(const std::uint8_t* data, std::size_t len, std::size_t& off, std::uint64_t& v) {
    if (off + 8 > len) return false;
    v = 0;
    for (int i = 0; i < 8; ++i) v |= static_cast<std::uint64_t>(data[off + i]) << (i * 8);
    off += 8;
    return true;
}

} // namespace

Ledger::Ledger() : genesis_{}, head_{} {}

Ledger::Ledger(Hash256 genesis) : genesis_(genesis), head_(genesis) {}

Event Ledger::append(std::uint8_t actor, std::uint8_t kind, std::uint64_t addr,
                     Hash256 before, Hash256 after, std::uint64_t epoch) {
    Event e;
    e.seq = events_.size();
    e.epoch = epoch;
    e.actor = actor;
    e.kind = kind;
    e.addr = addr;
    e.before = before;
    e.after = after;
    e.parent = head_;
    e.hash = event_hash(head_, e);
    events_.push_back(e);
    head_ = e.hash;
    return e;
}

bool Ledger::verify(std::string* error) const {
    if (!valid_encoding_) { if (error) *error = "invalid ledger encoding"; return false; }
    Hash256 parent = genesis_;
    for (std::size_t i = 0; i < events_.size(); ++i) {
        const Event& e = events_[i];
        if (e.seq != i) {
            if (error) *error = "sequence mismatch at event " + std::to_string(i);
            return false;
        }
        if (!(e.parent == parent)) {
            if (error) *error = "parent mismatch at event " + std::to_string(i);
            return false;
        }
        const Hash256 expected = event_hash(parent, e);
        if (!(e.hash == expected)) {
            if (error) *error = "hash mismatch at event " + std::to_string(i);
            return false;
        }
        parent = e.hash;
    }
    if (!(head_ == parent)) {
        if (error) *error = "head mismatch";
        return false;
    }
    if (error) error->clear();
    return true;
}

std::vector<std::uint8_t> Ledger::serialize() const {
    // Version 2: explicit little-endian fixed-width fields (154 bytes/event).
    std::vector<std::uint8_t> out;
    out.reserve(8 + 32 + 32 + 8 + events_.size() * kEventWireBytes);
    out.insert(out.end(), kLedgerMagic, kLedgerMagic + sizeof(kLedgerMagic));
    out.insert(out.end(), genesis_.begin(), genesis_.end());
    out.insert(out.end(), head_.begin(), head_.end());
    put_u64(out, static_cast<std::uint64_t>(events_.size()));
    for (const Event& e : events_) {
        put_u64(out, e.seq); put_u64(out, e.epoch);
        out.push_back(e.actor); out.push_back(e.kind); put_u64(out, e.addr);
        out.insert(out.end(), e.before.begin(), e.before.end());
        out.insert(out.end(), e.after.begin(), e.after.end());
        out.insert(out.end(), e.parent.begin(), e.parent.end());
        out.insert(out.end(), e.hash.begin(), e.hash.end());
    }
    return out;
}

Ledger Ledger::from_bytes(const std::uint8_t* data, std::size_t len) {
    Ledger invalid;
    invalid.valid_encoding_ = false;
    constexpr std::size_t header = 8 + 32 + 32 + 8;
    if (!data || len < header || std::memcmp(data, kLedgerMagic, sizeof(kLedgerMagic)) != 0)
        return invalid;
    std::size_t off = 8;
    Ledger l;
    std::memcpy(l.genesis_.data(), data + off, 32); off += 32;
    std::memcpy(l.head_.data(), data + off, 32); off += 32;
    std::uint64_t count = 0;
    if (!read_u64(data, len, off, count)) return invalid;
    if (count > (len - header) / kEventWireBytes ||
        len != header + static_cast<std::size_t>(count) * kEventWireBytes) return invalid;
    l.events_.reserve(static_cast<std::size_t>(count));
    for (std::uint64_t i = 0; i < count; ++i) {
        Event e;
        if (!read_u64(data, len, off, e.seq) || !read_u64(data, len, off, e.epoch) ||
            off + 2 > len) return invalid;
        e.actor = data[off++]; e.kind = data[off++];
        if (!read_u64(data, len, off, e.addr) || off + 128 > len) return invalid;
        std::memcpy(e.before.data(), data + off, 32); off += 32;
        std::memcpy(e.after.data(), data + off, 32); off += 32;
        std::memcpy(e.parent.data(), data + off, 32); off += 32;
        std::memcpy(e.hash.data(), data + off, 32); off += 32;
        l.events_.push_back(e);
    }
    std::string error;
    if (!l.verify(&error)) return invalid;
    return l;
}

Replica::Replica(std::uint8_t id, std::vector<PageId> hosted)
    : id_(id), hosted_(std::move(hosted)) {}

bool Replica::hosts(const PageId& page) const {
    for (const auto& p : hosted_) {
        if (p == page) return true;
    }
    return false;
}

CommitResult Replica::validate(const Delta& delta, const PageTable& table) const {
    CommitResult r;
    if (!hosts(delta.page)) {
        r.error = "page not hosted by replica";
        return r;
    }
    const auto* entry = table.entry(delta.page);
    if (!entry) {
        r.error = "page not present";
        return r;
    }
    if (!(entry->page->digest() == delta.base)) {
        r.error = "stale base hash";
        return r;
    }
    r.ok = true;
    return r;
}

CommitResult Replica::commit(const Delta& delta, PageTable& table, Ledger& global_ledger,
                             std::uint8_t kind) {
    CommitResult r = validate(delta, table);
    if (!r.ok) return r;
    const auto* entry = table.entry(delta.page);
    const Hash256 before = entry->page->digest();
    global_ledger.append(id_, kind, 0, before, delta.next, delta.epoch);
    table.flush(delta.page);
    r.ok = true;
    return r;
}

} // namespace nanlm
