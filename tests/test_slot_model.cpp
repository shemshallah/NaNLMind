#include "nanlm/slot_memory.hpp"
#include "test_util.hpp"

#include <fstream>
#include <iterator>

using namespace nanlm;

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());

    SlotMemory slot(2);
    slot.train(train);
    const SlotEval eval = slot.evaluate(test, 1, test.size());
    CHECK(eval.bytes > 0);
    CHECK(eval.accuracy > 0.0);
    CHECK(eval.accuracy > 0.35); // longer context improves top-1
    CHECK(eval.bits_per_byte < 5.0); // interpolation keeps the model usable
    SlotMemory order1(1);
    order1.train(train);
    const SlotEval one = order1.evaluate(test, 1, test.size());
    std::cout << "slot1 acc=" << one.accuracy << " bpc=" << one.bits_per_byte << "\n";
    std::cout << "slot2 acc=" << eval.accuracy << " bpc=" << eval.bits_per_byte << "\n";
    CHECK(one.bytes == eval.bytes);
    CHECK(eval.bits_per_byte > 0.0);

    return test_done("context-2 slot memory baseline");
}
