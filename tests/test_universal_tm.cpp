#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    Universe u(0x55544D31);
    UniversalTuringMachine utm(u);

    // Machine 1: binary increment.
    CHECK(utm.load_machine({
        {0, 1, 0, -1, 0, false},
        {0, 0, 1, 0, 0, true},
        {0, 2, 1, 0, 0, true},
    }, "1011", 3));
    utm.run(100);
    CHECK(utm.halted());
    CHECK_EQ(utm.tape(0, 4), std::string("1100"));

    // Machine 2: unary increment, loaded into the same UTM instance.
    CHECK(utm.load_machine({
        {0, 1, 1, 1, 0, false},
        {0, 2, 1, 0, 0, true},
    }, "111", 0));
    utm.run(100);
    CHECK(utm.halted());
    CHECK_EQ(utm.tape(0, 4), std::string("1111"));

    // The encoded description is on the tape; the UTM step is fixed.
    CHECK(utm.tape_pages() >= 1u);
    return test_done("universal TM: one fixed step interprets encoded machines");
}
