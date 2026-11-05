#include "nanlm/resonance.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    ResonanceLattice a;
    ResonanceLattice b;
    CHECK(a.digest() == b.digest());
    CHECK_EQ(a.coupling(0, 0), 0);
    for (int i = 0; i < 256; ++i) {
        for (int j = 0; j < 256; ++j) {
            CHECK_EQ(a.coupling(i, j), a.coupling(j, i));
        }
    }

    a.ping(0, 65536);
    CHECK_EQ(a.energy(0), 65536);
    const int steps = a.propagate(0, 255, 19661, 500);
    CHECK(steps > 0);
    CHECK(steps < 500);
    CHECK(a.coherence() >= 0);
    CHECK(a.coherence() <= 65536);

    a.reset(123);
    b.reset(123);
    CHECK(a.digest() == b.digest());
    a.step();
    b.step();
    CHECK(a.digest() == b.digest());

    // Energy is bounded.
    for (int i = 0; i < 256; ++i) {
        CHECK(a.energy(i) >= 0);
        CHECK(a.energy(i) <= (1 << 20));
    }

    // Different seeds produce different initial phases.
    ResonanceLattice c;
    c.reset(1);
    CHECK(!(a.digest() == c.digest()));

    return test_done("resonance lattice");
}
