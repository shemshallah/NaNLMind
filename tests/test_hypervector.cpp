#include "nanlm/hypervector.hpp"
#include "test_util.hpp"

#include <array>
#include <string>

using namespace nanlm;

int main() {
    HyperTripleStore a;
    a.add("penguin", "can", "swim");
    a.add("penguin", "cannot", "fly");
    a.add("eagle", "can", "fly");
    a.add("bird", "has", "wings");
    CHECK_EQ(a.triples(), 4u);
    CHECK_EQ(a.query("penguin", "can"), std::string("swim"));
    CHECK_EQ(a.query("penguin", "cannot"), std::string("fly"));
    CHECK_EQ(a.query("eagle", "can"), std::string("fly"));
    CHECK_EQ(a.query("bird", "has"), std::string("wings"));

    HyperTripleStore b;
    b.add("penguin", "can", "swim");
    b.add("eagle", "can", "fly");
    a.merge(b);
    CHECK_EQ(a.triples(), 6u);
    CHECK_EQ(a.query("penguin", "cannot"), std::string("fly"));

    const Hyper x = hyper_from_hash(7);
    CHECK(hyper_hamming(hyper_bind(x, x), Hyper{}) == 0u);
    CHECK(hyper_bind(x, hyper_from_hash(8)) == hyper_bind(hyper_from_hash(8), x));
    const Hyper p = hyper_permute(x, 7);
    CHECK(hyper_permute(p, kHyperBits - 7) == x);

    return test_done("XOR hypervector triple store");
}
