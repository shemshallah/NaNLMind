#include "nanlm/turing_machine.hpp"
#include "test_util.hpp"
using namespace nanlm;
int main() {
    Universe u(0x544D4143); TuringMachine tm(u);
    const std::vector<TmTransition> program{{0,1,0,-1,0,false},{0,0,1,0,0,true},{0,2,1,0,0,true}};
    CHECK(tm.load(program)); tm.set_tape("1011",3); CHECK(tm.step());
    CHECK(u.verify());
    const auto tape=tm.serialize_tape(); const auto chart=u.serialize();
    auto restored_chart=Universe::from_bytes(chart.data(),chart.size()); CHECK(restored_chart!=nullptr);
    CHECK(restored_chart->verify());
    TuringMachine resumed(*restored_chart);
    CHECK(resumed.restore_tape(tape.data(),tape.size())); resumed.run(100);
    CHECK(resumed.halted()); CHECK_EQ(resumed.tape(0,4),std::string("1100"));
    CHECK(tm.load(program)); tm.set_tape("111",2); tm.run(100);
    CHECK(tm.halted()); CHECK_EQ(tm.tape(-1,3),std::string("1000"));
    auto bad=tape; bad.pop_back(); CHECK(!resumed.restore_tape(bad.data(),bad.size()));
    return test_done("Turing machine tape persistence");
}
