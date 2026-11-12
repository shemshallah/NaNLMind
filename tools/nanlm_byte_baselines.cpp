// Byte-level language-model baselines with BPB, top-1 and top-5 accuracy.
// This is a baseline harness, not a claim about the native head worker.
#include "nanlm/byte_model.hpp"
#include "nanlm/context2.hpp"
#include "nanlm/universe.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
struct Scores {
    double bpb = 0.0;
    double top1 = 0.0;
    double top5 = 0.0;
};

std::array<std::uint32_t, 256> byte_counts(const ByteModel& model,
                                            std::uint8_t a) {
    std::array<std::uint32_t, 256> counts{};
    for (unsigned b = 0; b < 256u; ++b)
        counts[b] = model.count(a, static_cast<std::uint8_t>(b));
    return counts;
}

std::array<double, 256> context2_probs(const Context2Model& model,
                                        std::uint8_t a, std::uint8_t b) {
    std::array<double, 256> probs{};
    for (unsigned c = 0; c < 256u; ++c)
        probs[c] = model.probability(a, b, static_cast<std::uint8_t>(c));
    return probs;
}

template <typename Counts>
std::size_t rank_of(Counts values, std::uint8_t target) {
    std::array<unsigned, 256> order{};
    for (unsigned i = 0; i < 256u; ++i) order[i] = i;
    std::stable_sort(order.begin(), order.end(), [&](unsigned a, unsigned b) {
        if (values[a] != values[b]) return values[a] > values[b];
        return a < b;
    });
    for (std::size_t i = 0; i < 5u; ++i)
        if (order[i] == target) return i;
    return 5;
}
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "data/alice_full.txt";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/byte_baselines.json";
    try {
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
        if (data.size() < 1000) throw std::runtime_error("corpus too small");
        const std::size_t split = data.size() * 4u / 5u;
        std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
        std::vector<std::uint8_t> test(data.begin() + split, data.end());

        Universe universe(0x1234);
        ByteModel bigram(universe);
        bigram.train(train);
        const ByteEval bigram_eval = bigram.evaluate(test, 1, test.size());
        std::size_t bigram_top5 = 0;
        for (std::size_t i = 1; i < test.size(); ++i) {
            const auto counts = byte_counts(bigram, test[i - 1]);
            if (rank_of(counts, test[i]) < 5u) ++bigram_top5;
        }
        const ByteEval order0 = ByteModel::order0_reference(train, test);
        // Order-0 top-5 uses the same unigram counts; the reference's prediction
        // is the argmax, so recompute ranks from the bigram model's totals.
        std::array<std::uint64_t, 256> unigram{};
        for (std::uint8_t b : train) ++unigram[b];
        std::size_t order0_top5 = 0;
        for (std::size_t i = 1; i < test.size(); ++i)
            if (rank_of(unigram, test[i]) < 5u) ++order0_top5;
        const double order0_top5_acc = static_cast<double>(order0_top5) /
            static_cast<double>(test.size() - 1u);

        Context2Model context2;
        context2.train(train);
        const Context2Eval c2_eval = context2.evaluate(test, 2, test.size());
        std::size_t c2_top5 = 0;
        for (std::size_t i = 2; i < test.size(); ++i) {
            const auto probs = context2_probs(context2, test[i - 2], test[i - 1]);
            if (rank_of(probs, test[i]) < 5u) ++c2_top5;
        }

        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.byte-baselines/1\","
               "\"corpus\":\"" << path << "\","
               "\"train_bytes\":" << train.size() << ","
               "\"test_bytes\":" << test.size() << ","
               "\"metric_scope\":\"byte-level BPB/top-1/top-5; not a native head-worker word metric\","
               "\"order0\":{\"bpb\":" << order0.bits_per_byte
            << ",\"top1\":" << order0.accuracy
            << ",\"top5\":" << order0_top5_acc << "},"
               "\"bigram\":{\"bpb\":" << bigram_eval.bits_per_byte
            << ",\"top1\":" << bigram_eval.accuracy
            << ",\"top5\":" << (static_cast<double>(bigram_top5) /
                                 static_cast<double>(test.size() - 1u))
            << "},"
               "\"context2\":{\"bpb\":" << c2_eval.bits_per_byte
            << ",\"top1\":" << c2_eval.accuracy
            << ",\"top5\":" << (static_cast<double>(c2_top5) /
                                 static_cast<double>(test.size() - 2u))
            << "}}\n";
        std::cout << "byte_baselines corpus=" << path
                  << " order0_bpb=" << order0.bits_per_byte
                  << " bigram_bpb=" << bigram_eval.bits_per_byte
                  << " context2_bpb=" << c2_eval.bits_per_byte
                  << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "byte_baselines_error: " << e.what() << "\n";
        return 1;
    }
}
