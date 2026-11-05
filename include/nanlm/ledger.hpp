// Append-only, hash-chained ledger and shard commits.
//
// A ledger is a totally ordered sequence of events. Each event commits to the
// previous head, so replay from genesis is deterministic and tampering is
// localized. A shard owns a set of pages and may only commit deltas whose
// base hash matches the current page hash (optimistic concurrency).
#pragma once

#include "nanlm/pager.hpp"
#include "nanlm/sha256.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

struct Event {
    std::uint64_t seq = 0;
    std::uint64_t epoch = 0; // logical clock tick
    std::uint8_t actor = 0;
    std::uint8_t kind = 0;
    std::uint64_t addr = 0;
    Hash256 before{};
    Hash256 after{};
    Hash256 parent{};
    Hash256 hash{};
};

class Ledger {
public:
    Ledger();
    explicit Ledger(Hash256 genesis);

    Event append(std::uint8_t actor, std::uint8_t kind, std::uint64_t addr,
                 Hash256 before, Hash256 after, std::uint64_t epoch = 0);

    bool verify(std::string* error = nullptr) const;
    std::size_t size() const { return events_.size(); }
    const Event& at(std::size_t i) const { return events_[i]; }
    Hash256 head() const { return head_; }
    Hash256 genesis() const { return genesis_; }

    std::vector<std::uint8_t> serialize() const;
    static Ledger from_bytes(const std::uint8_t* data, std::size_t len);

private:
    Hash256 genesis_{};
    Hash256 head_{};
    std::vector<Event> events_;
    bool valid_encoding_ = true;
};

struct Delta {
    PageId page{};
    Hash256 base{};
    Hash256 next{};
    std::uint64_t epoch = 0;
    std::uint32_t cells_changed = 0;
};

struct CommitResult {
    bool ok = false;
    std::string error;
};

// A replica hosts a region of the one global topology. It is a placement and
// write-lease boundary, not an independent mind. The global ledger is passed
// in; replicas never own a separate history.
class Replica {
public:
    Replica() = default;
    Replica(std::uint8_t id, std::vector<PageId> hosted);

    std::uint8_t id() const { return id_; }
    bool hosts(const PageId& page) const;
    const std::vector<PageId>& hosted() const { return hosted_; }

    CommitResult validate(const Delta& delta, const PageTable& table) const;
    CommitResult commit(const Delta& delta, PageTable& table, Ledger& global_ledger,
                        std::uint8_t kind = 1);

private:
    std::uint8_t id_ = 0;
    std::vector<PageId> hosted_;
};

} // namespace nanlm
