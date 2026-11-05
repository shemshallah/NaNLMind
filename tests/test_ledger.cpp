#include "nanlm/ledger.hpp"
#include "test_util.hpp"

#include <memory>

using namespace nanlm;

int main() {
    Ledger ledger;
    std::string err;
    CHECK(ledger.verify(&err));
    CHECK_EQ(ledger.size(), 0u);

    for (int i = 0; i < 64; ++i) {
        Hash256 before{};
        Hash256 after{};
        before[0] = static_cast<std::uint8_t>(i);
        after[0] = static_cast<std::uint8_t>(i + 1);
        ledger.append(static_cast<std::uint8_t>(i % 5), static_cast<std::uint8_t>(i % 3),
                      static_cast<std::uint64_t>(i * 17), before, after);
    }
    CHECK_EQ(ledger.size(), 64u);
    CHECK(ledger.verify(&err));

    const Hash256 head = ledger.head();
    const auto bytes = ledger.serialize();
    Ledger restored = Ledger::from_bytes(bytes.data(), bytes.size());
    CHECK_EQ(restored.size(), ledger.size());
    CHECK(restored.verify(&err));
    CHECK(restored.head() == head);

    // Tamper with one byte of one event.
    auto tampered = bytes;
    const std::size_t event_offset = 8 + 32 + 32 + 8;
    tampered[event_offset + 20 * 154 + 3] ^= 0x01u;
    Ledger broken = Ledger::from_bytes(tampered.data(), tampered.size());
    CHECK(!broken.verify(&err));

    CHECK_EQ(bytes.size(), 8u + 32u + 32u + 8u + 64u * 154u);
    auto truncated = bytes; truncated.pop_back();
    CHECK(!Ledger::from_bytes(truncated.data(), truncated.size()).verify(&err));
    auto trailing = bytes; trailing.push_back(0);
    CHECK(!Ledger::from_bytes(trailing.data(), trailing.size()).verify(&err));

    // A bad magic is rejected.
    auto bad = bytes;
    bad[0] = 'X';
    Ledger bad_ledger = Ledger::from_bytes(bad.data(), bad.size());
    CHECK_EQ(bad_ledger.size(), 0u);

    // Replica hosting and optimistic commit against the one global ledger.
    PageTable table;
    auto page = std::make_shared<Universe>(0);
    const PageId root = PageId::root();
    table.map(root, page);
    const Hash256 base = page->digest();

    Ledger global_ledger;
    Replica replica(1, {root});
    CHECK(replica.hosts(root));
    CHECK(!replica.hosts(PageId::child(root, 1)));

    Delta delta;
    delta.page = root;
    delta.base = base;
    delta.next = base;
    delta.epoch = 1;
    delta.cells_changed = 1;
    CHECK(replica.validate(delta, table).ok);

    // Change the page, flush, and the stale base must be rejected.
    const BitAddress change{root, matrix_addr(0, 1), 0, 0};
    bool current = false;
    CHECK(table.read_bit(change, current));
    table.write_bit(change, !current);
    table.flush(root);
    CHECK(!replica.validate(delta, table).ok);

    Delta fresh;
    fresh.page = root;
    fresh.base = table.entry(root)->page->digest();
    fresh.next = fresh.base;
    fresh.epoch = 2;
    CHECK(replica.commit(fresh, table, global_ledger).ok);
    CHECK_EQ(global_ledger.size(), 1u);

    // A replica cannot commit a page it does not host.
    Delta foreign;
    foreign.page = PageId::child(root, 2);
    foreign.base = base;
    foreign.next = base;
    CHECK(!replica.validate(foreign, table).ok);

    return test_done("ledger and replica commits");
}
