#include "nanlm/context2.hpp"
#include "test_util.hpp"

#include <fstream>
#include <iterator>

using namespace nanlm;

int main() {
    std::ifstream f("data/alice_full.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());

    Context2Model model;
    model.train(train);
    const Context2Eval eval = model.evaluate(test, 2, test.size());
    std::cout << "ctx2 slabs=" << model.slabs() << " acc=" << eval.accuracy
              << " bpc=" << eval.bits_per_byte << "\n";
    CHECK(model.slabs() > 0);
    CHECK(eval.bytes > 0);
    CHECK(eval.bits_per_byte < 4.713); // better than order-0
    CHECK(eval.accuracy > 0.0);

    // The count table is addressable as a 256x256 child-chart layout.
    model.observe('A', 'B', 'C', 7);
    CHECK_EQ(model.count('A', 'B', 'C'), 7u);
    CHECK_EQ(model.predict('A', 'B'), static_cast<std::uint8_t>('C'));

    return test_done("context-2 child-chart layout");
}
