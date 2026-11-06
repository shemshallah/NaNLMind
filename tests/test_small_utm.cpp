#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <map>
#include <utility>
#include <vector>

using namespace nanlm;

namespace {
struct RefEntry {
    std::uint8_t write;
    std::int8_t move;
    std::uint8_t to;
};

struct RefMachine {
    std::map<std::pair<std::uint8_t, std::uint8_t>, RefEntry> table;
    std::map<std::int64_t, std::uint8_t> tape;
    std::uint8_t state = 0;
    std::int64_t head = 0;
    bool halted = false;

    std::uint8_t read(std::int64_t p) const {
        const auto it = tape.find(p);
        return it == tape.end() ? 2 : it->second;
    }

    bool step() {
        if (halted) return false;
        const auto it = table.find({state, read(head)});
        if (it == table.end()) {
            halted = true;
            return false;
        }
        const auto& e = it->second;
        tape[head] = e.write;
        state = e.to;
        head += e.move;
        return true;
    }
};

void add(std::vector<TmTransition>& out,
         std::map<std::pair<std::uint8_t, std::uint8_t>, RefEntry>& ref,
         std::uint8_t from, std::uint8_t read, std::uint8_t write,
         std::int8_t move, std::uint8_t to) {
    out.push_back(TmTransition{from, read, write, move, to, false});
    ref[{from, read}] = RefEntry{write, move, to};
}
} // namespace

int main() {
    // Neary-Woods U6,4, Table 12. g=0, b=1, c=2, delta=3; u1=0 ... u6=5.
    std::vector<TmTransition> table;
    std::map<std::pair<std::uint8_t, std::uint8_t>, RefEntry> ref_table;
    // u1
    add(table, ref_table, 0, 0, 1, -1, 0);
    add(table, ref_table, 0, 1, 0, -1, 0);
    add(table, ref_table, 0, 2, 3, -1, 0);
    add(table, ref_table, 0, 3, 2, +1, 1);
    // u2
    add(table, ref_table, 1, 0, 0, +1, 0);
    add(table, ref_table, 1, 1, 0, +1, 1);
    add(table, ref_table, 1, 2, 0, +1, 4);
    add(table, ref_table, 1, 3, 2, +1, 1);
    // u3
    add(table, ref_table, 2, 0, 1, -1, 2);
    add(table, ref_table, 2, 1, 1, -1, 4);
    add(table, ref_table, 2, 2, 3, -1, 2);
    add(table, ref_table, 2, 3, 3, -1, 4);
    // u4
    add(table, ref_table, 3, 0, 1, +1, 1);
    add(table, ref_table, 3, 1, 0, +1, 3);
    add(table, ref_table, 3, 2, 2, +1, 4);
    add(table, ref_table, 3, 3, 2, +1, 3);
    // u5
    add(table, ref_table, 4, 0, 1, -1, 5);
    add(table, ref_table, 4, 1, 0, +1, 5);
    add(table, ref_table, 4, 2, 1, -1, 2);
    add(table, ref_table, 4, 3, 3, +1, 4);
    // u6; (u6,c) is the undefined halt pair.
    add(table, ref_table, 5, 0, 1, -1, 3);
    add(table, ref_table, 5, 1, 0, +1, 4);
    add(table, ref_table, 5, 3, 0, +1, 0);
    CHECK_EQ(table.size(), 23u);

    Universe u(0x55363455);
    TuringMachine tm(u);
    CHECK(tm.load(table));
    tm.set_tape("", 0);

    RefMachine ref;
    ref.table = ref_table;
    for (int i = 0; i < 200; ++i) {
        const bool a = tm.step();
        const bool b = ref.step();
        CHECK_EQ(tm.state(), ref.state);
        CHECK_EQ(tm.head(), ref.head);
        CHECK_EQ(tm.halted(), ref.halted);
        if (tm.head() > -20 && tm.head() < 40) {
            for (std::int64_t p = -10; p < 30; ++p) {
                CHECK_EQ(tm.symbol(p), ref.read(p));
            }
        }
        if (!a || !b) break;
    }
    CHECK(tm.tape_pages() >= 1u);
    return test_done("explicit U6,4 finite table matches independent reference");
}
