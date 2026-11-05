#include "nanlm/pager.hpp"
#include "test_util.hpp"

#include <memory>

using namespace nanlm;

int main() {
    PageTable table;
    auto root = std::make_shared<Universe>(0);
    CHECK(table.map(PageId::root(), root));
    CHECK(table.contains(PageId::root()));
    CHECK_EQ(table.size(), 1u);

    const auto cell = matrix_addr(10, 20);
    const BitAddress bit{PageId::root(), cell, 0, 7};
    CHECK(table.write_bit(bit, true));
    bool value = false;
    CHECK(table.read_bit(bit, value));
    CHECK(value);
    CHECK_EQ(table.dirty_cell_count(PageId::root()), 1u);
    CHECK(table.is_dirty(PageId::root()));

    const ByteAddress byte{PageId::root(), cell, 0, 1};
    CHECK(table.write_byte(byte, 0xA5));
    std::uint8_t byte_value = 0;
    CHECK(table.read_byte(byte, byte_value));
    CHECK_EQ(byte_value, 0xA5u);

    const NanWord word = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, 0x12345678u);
    CHECK(table.write_word(PageId::root(), cell, 1, word));
    NanWord read_word;
    CHECK(table.read_word(PageId::root(), cell, 1, read_word));
    CHECK_EQ(read_word.raw, word.raw);

    // COW through an alias.
    const PageId alias = PageId::child(PageId::root(), 7);
    CHECK(table.map(alias, table.resolve(PageId::root())));
    CHECK_EQ(table.entry(PageId::root())->page, table.entry(alias)->page);
    const BitAddress alias_bit{alias, cell, 0, 7};
    CHECK(table.write_bit(alias_bit, false));
    CHECK(table.entry(PageId::root())->page != table.entry(alias)->page);
    bool root_value = false;
    bool alias_value = true;
    CHECK(table.read_bit(bit, root_value));
    CHECK(table.read_bit(alias_bit, alias_value));
    CHECK(root_value);
    CHECK(!alias_value);

    // Read-only pages reject writes.
    const PageId ro = PageId::child(PageId::root(), 8);
    CHECK(table.map(ro, std::make_shared<Universe>(1), kPermRead));
    CHECK(!table.write_bit({ro, cell, 0, 0}, true));

    // Flush clears dirty state and updates the base hash.
    CHECK(table.is_dirty(PageId::root()));
    CHECK(table.flush(PageId::root()));
    CHECK(!table.is_dirty(PageId::root()));
    CHECK_EQ(table.dirty_cell_count(PageId::root()), 0u);

    // Root hash changes after a write and is stable afterward.
    const Hash256 before = table.root_hash();
    CHECK(table.write_bit(bit, false));
    const Hash256 after = table.root_hash();
    CHECK(!(before == after));
    CHECK(table.root_hash() == after);

    // Bit address encoding round-trips for all depths and fields.
    for (int depth = 0; depth <= 4; ++depth) {
        BitAddress a;
        a.page.depth = static_cast<std::uint8_t>(depth);
        for (int i = 0; i < 4; ++i) a.page.path[i] = static_cast<std::uint8_t>(i * 37 + depth);
        a.cell = static_cast<std::uint16_t>(depth * 1000 + 7);
        a.word = static_cast<std::uint8_t>(depth % 4);
        a.bit = static_cast<std::uint8_t>(depth * 11 % 64);
        const BitAddress b = BitAddress::decode(a.encode());
        CHECK(a == b);
    }

    // Ref helpers preserve the bit address.
    const BitAddress original{PageId::child(PageId::root(), 3), cell, 2, 9};
    const Ref ref = Ref::from_bit(original);
    BitAddress back;
    CHECK(ref.as_bit(back));
    CHECK(original == back);
    CHECK_EQ(ref.to_string().find("bit@3"), 0u);

    // Backend round-trip.
    MemoryBackend backend;
    CHECK(table.flush_to(backend));
    CHECK(backend.contains(PageId::root()));
    PageTable restored;
    CHECK(restored.load_from(backend));
    CHECK_EQ(restored.size(), table.size());
    CHECK(restored.root_hash() == table.root_hash());

    // Empty backend miss.
    std::vector<std::uint8_t> missing;
    CHECK(!backend.read(PageId::child(PageId::root(), 99), missing));

    // Page permissions and depth limits.
    PageId deep = PageId::root();
    for (int i = 0; i < 4; ++i) deep = PageId::child(deep, static_cast<std::uint8_t>(i));
    CHECK_EQ(deep.depth, 4u);
    CHECK_EQ(deep.to_string(), "0.1.2.3");

    return test_done("pager and bit addressing");
}
