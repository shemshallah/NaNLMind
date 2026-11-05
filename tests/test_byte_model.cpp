#include "nanlm/byte_model.hpp"
#include "test_util.hpp"

#include <fstream>
#include <iterator>

using namespace nanlm;

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    CHECK(data.size() > 1000);
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());

    Universe u(0x1234);
    ByteModel model(u);
    model.train(train);
    const ByteEval eval = model.evaluate(test, 1, test.size());
    const ByteEval ref = ByteModel::reference(train, test);
    const ByteEval order0 = ByteModel::order0_reference(train, test);
    CHECK(eval.bytes > 0);
    CHECK(eval.accuracy > 0.0);
    CHECK(eval.bits_per_byte < 8.0);
    CHECK_EQ(eval.correct, ref.correct);
    CHECK(std::abs(eval.accuracy - ref.accuracy) < 1e-12);
    CHECK(std::abs(eval.bits_per_byte - ref.bits_per_byte) < 1e-9);
    CHECK(eval.bits_per_byte < order0.bits_per_byte);

    // The topology predicts exactly what the host bigram predicts.
    for (int a = 0; a < 256; ++a) {
        const std::uint8_t p = model.predict(static_cast<std::uint8_t>(a));
        std::uint32_t best = 0;
        std::uint8_t best_b = 0;
        for (int b = 0; b < 256; ++b) {
            const std::uint32_t c = model.count(static_cast<std::uint8_t>(a),
                                                static_cast<std::uint8_t>(b));
            if (c > best) {
                best = c;
                best_b = static_cast<std::uint8_t>(b);
            }
        }
        if (best > 0) CHECK_EQ(p, best_b);
    }
    CHECK(u.verify());

    return test_done("single-universe byte bigram");
}
