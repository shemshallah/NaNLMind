#include "nanlm/ledger.hpp"

#include <cstring>
#include <sstream>

namespace nanlm {
namespace {

constexpr char kLedgerMagic[8] = {'N', 'L', 'M', 'L', 'E', 'D', 'G', '1'};

void put_u64(std::vector<std::uint8_t>& out, std::uint64_t v) {
    for (int i = 0; i < 8; ++i) out.push_back(static_cast<std::uint8_t>((v >> (i * 8)) & 0xFFu));
}

Hash256 event_hash(const Hash256& parent, const Event& e) {
    std::vector<std::uint8_t> buf;
    buf.reserve(8 + 8 + 8 + 2 + 8 + 32 + 32);
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
    std::vector<std::uint8_t> out;
    out.reserve(8 + 32 + 32 + 8 + events_.size() * sizeof(Event));
    out.insert(out.end(), kLedgerMagic, kLedgerMagic + sizeof(kLedgerMagic));
    out.insert(out.end(), genesis_.begin(), genesis_.end());
    out.insert(out.end(), head_.begin(), head_.end());
    put_u64(out, events_.size());
    const auto* p = reinterpret_cast<const std::uint8_t*>(events_.data());
    out.insert(out.end(), p, p + events_.size() * sizeof(Event));
    return out;
}

Ledger Ledger::from_bytes(const std::uint8_t* data, std::size_t len) {
    Ledger l;
    std::size_t off = 0;
    if (len < 8 + 32 + 32 + 8) return l;
    if (std::memcmp(data, kLedgerMagic, sizeof(kLedgerMagic)) != 0) return l;
    off += 8;
    std::memcpy(l.genesis_.data(), data + off, 32);
    off += 32;
    std::memcpy(l.head_.data(), data + off, 32);
    off += 32;
    std::uint64_t count = 0;
    if (!read_u64(data, len, off, count)) return l;
    if (off + count * sizeof(Event) > len) return l;
    l.events_.resize(static_cast<std::size_t>(count));
    std::memcpy(l.events_.data(), data + off, static_cast<std::size_t>(count) * sizeof(Event));
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
