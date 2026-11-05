#include "nan16_ptc.hpp"
#include <cassert>
#include <iostream>
using namespace nan16;
int main() {
    Topology t;
    assert(t.fixed_points().size() == 256);
    std::cout << "PASS: 256 fixed points\n";

    t.seed_linear_rule90(0x1000, 32, 0);
    t.at_address(0x1010).state = 1;
    std::string s0 = t.snapshot_line(0x1000, 32);
    for (int i = 0; i < 8; ++i) t.step_rule90_line(0x1000, 32);
    std::string s8 = t.snapshot_line(0x1000, 32);
    int ones = 0; for (char c : s8) if (c == '1') ++ones;
    assert(ones > 1 && s8 != s0);
    std::cout << "PASS: Rule 90 Sierpinski (" << ones << " ones)\n";

    auto sum = t.run_adder(0x3000, 22, 11, 8);
    assert(sum == 33);
    std::cout << "PASS: adder 22+11=" << sum << "\n";

    t.set_all_rule(RuleReversibleXOR);
    Cell& c = t.at_address(0x5000);
    auto orig = c.state = 0xA5;
    c.state ^= 3; c.state ^= 3;
    assert(c.state == orig);
    std::cout << "PASS: reversible XOR involution\n";

    std::cout << "ALL ROUND 3 TESTS PASSED\n";
    return 0;
}
