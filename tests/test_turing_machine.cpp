#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    Universe u(0x544D4143);
    TuringMachine tm(u);
    // Binary increment: rightmost bit starts at head=3.
    // q0,1 -> write 0, left, q0
    // q0,0 -> write 1, stay, HALT
    // q0,blank -> write 1, stay, HALT
    tm.load({
        {0, 1, 0, -1, 0, false},
        {0, 0, 1, 0, 0, true},
        {0, 2, 1, 0, 0, true},
    });
    tm.set_tape("1011", 3);
    tm.run(100);
    CHECK(tm.halted());
    CHECK_EQ(tm.tape(0, 4), std::string("1100"));
    CHECK(tm.tape_pages() >= 1u);

    // 111 + 1 = 1000 (the head writes the carry into a new blank cell).
    tm.set_tape("111", 2);
    tm.run(100);
    CHECK(tm.halted());
    CHECK_EQ(tm.tape(-1, 3), std::string("1000"));

    return test_done("general Turing machine: binary increment");
}
