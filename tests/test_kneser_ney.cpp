#include "nanlm/slot_memory.hpp"
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

    KneserNey bi(1);
    bi.train(train);
    const SlotEval b1 = bi.evaluate(test, 1, test.size());
    KneserNey tri(2);
    tri.train(train);
    const SlotEval b2 = tri.evaluate(test, 2, test.size());
    std::cout << "KN1 acc=" << b1.accuracy << " bpc=" << b1.bits_per_byte << "\n";
    std::cout << "KN2 acc=" << b2.accuracy << " bpc=" << b2.bits_per_byte << "\n";
    CHECK(b1.bytes > 0);
    CHECK(b1.bits_per_byte < 4.681); // better than order-0
    CHECK(b2.bits_per_byte <= b1.bits_per_byte); // trigram should not be worse
    CHECK(b2.accuracy > 0.3);

    return test_done("Kneser-Ney byte baselines");
}
