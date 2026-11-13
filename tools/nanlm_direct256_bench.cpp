// Matched byte-level benchmark: raw NaN16 context memory vs order-0,
// byte-bigram and context-2 references on the same held-out positions.
//
// The system row is computed entirely by the guest:
//   - opcode 40 mode 3 trains/updates the context class memory;
//   - opcode 40 mode 6 returns the full 16x16 top-5 and target loss.
// The host only transports bytes, sorts the guest's five classes, and writes
// reference baselines with the same split and the same evaluation positions.
#include "nanlm/byte_model.hpp"
#include "nanlm/context2.hpp"
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <numeric>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
struct Metrics {
    double bpb = 0.0;
    double top1 = 0.0;
    double top5 = 0.0;
    std::size_t samples = 0;
};

std::uint32_t context4_key(const std::vector<std::uint8_t>& data,
                           std::size_t i) {
    return (static_cast<std::uint32_t>(data[i - 4]) << 24) |
           (static_cast<std::uint32_t>(data[i - 3]) << 16) |
           (static_cast<std::uint32_t>(data[i - 2]) << 8) |
           static_cast<std::uint32_t>(data[i - 1]);
}

template <typename Score>
std::array<std::uint8_t, 5> top5_classes(const Score& score) {
    std::array<std::uint8_t, 256> order{};
    for (unsigned i = 0; i < 256u; ++i)
        order[i] = static_cast<std::uint8_t>(i);
    std::partial_sort(order.begin(), order.begin() + 5, order.end(),
                      [&](std::uint8_t a, std::uint8_t b) {
                          if (score(a) != score(b))
                              return score(a) > score(b);
                          return a < b;
                      });
    return {order[0], order[1], order[2], order[3], order[4]};
}

bool contains(const std::array<std::uint8_t, 5>& top, std::uint8_t target) {
    return std::find(top.begin(), top.end(), target) != top.end();
}

void print_metrics(const char* name, const Metrics& m) {
    std::cout << name << " samples=" << m.samples
              << " bpb=" << m.bpb
              << " top1=" << m.top1
              << " top5=" << m.top5 << "\n";
}
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "data/alice_full.txt";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/system_byte_direct256.json";
    std::size_t exact = argc > 3 ? std::stoull(argv[3]) : 6000u;
    std::size_t fallback = argc > 4 ? std::stoull(argv[4]) : 10384u;
    std::size_t max_bytes = argc > 5 ? std::stoull(argv[5]) : 0u;
    try {
        if (exact > 8000u || fallback == 0u || fallback > 16384u ||
            exact + fallback > 16384u)
            throw std::runtime_error("exact<=8000, fallback 1..8192, exact+fallback<=16384 required");
        const std::size_t buckets = exact + fallback;
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
        if (max_bytes && data.size() > max_bytes) data.resize(max_bytes);
        if (data.size() < 2048u) throw std::runtime_error("corpus too small");
        const std::size_t split = data.size() * 4u / 5u;
        if (split < 8u || split >= data.size())
            throw std::runtime_error("invalid train/eval split");

        std::vector<std::size_t> train_positions;
        std::vector<std::size_t> eval_positions;
        for (std::size_t i = 4; i < split; ++i)
            if (data[i] < 255u) train_positions.push_back(i);
        for (std::size_t i = split; i < data.size(); ++i)
            if (data[i] < 255u) eval_positions.push_back(i);
        if (train_positions.empty() || eval_positions.empty())
            throw std::runtime_error("empty train/eval byte positions");

        RawFieldVM vm("build/field_driver.nan");
        if (!vm.ready())
            throw std::runtime_error("raw field VM unavailable: " + vm.error());
        if (!vm.reset_context_backoff())
            throw std::runtime_error("cannot reset context backoff: " + vm.error());

        std::vector<std::uint32_t> build_keys;
        build_keys.reserve(train_positions.size());
        for (std::size_t i : train_positions)
            build_keys.push_back(context4_key(data, i));
        std::size_t inserted = 0;
        if (!vm.context_backoff_build_batch(build_keys.data(), build_keys.size(),
                                            inserted))
            throw std::runtime_error("context backoff build failed: " + vm.error());
        ContextBackoffSelection selection;
        if (!vm.context_backoff_select(buckets, exact, selection))
            throw std::runtime_error("context backoff select failed: " + vm.error());
        if (!vm.reset_context_direct(selection.exact_count, selection.fallback))
            throw std::runtime_error("cannot reset direct context: " + vm.error());
        std::cout << "direct256_setup buckets=" << buckets
                  << " exact=" << selection.exact_count
                  << " fallback=" << selection.fallback
                  << " threshold=" << selection.threshold
                  << " unique=" << selection.unique
                  << " inserted=" << inserted
                  << " train_positions=" << train_positions.size()
                  << " eval_positions=" << eval_positions.size()
                  << "\n";
        for (std::size_t pos : train_positions) {
            std::uint32_t bucket = 0;
            bool is_exact = false;
            if (!vm.context_direct_step(data[pos], context4_key(data, pos),
                                        selection.exact_count,
                                        selection.fallback, bucket, is_exact))
                throw std::runtime_error("direct context train failed: " +
                                         vm.error());
        }
        std::cout << "direct256_train samples=" << train_positions.size()
                  << "\n";

        // Matched host references.  These are explicit reference floors, not
        // claims about the native context memory.
        std::array<std::uint64_t, 256> unigram{};
        std::vector<std::uint64_t> bigram(256u * 256u, 0u);
        for (std::uint8_t b : std::vector<std::uint8_t>(data.begin(),
                                                        data.begin() + split))
            ++unigram[b];
        for (std::size_t i = 1; i < split; ++i)
            ++bigram[static_cast<std::size_t>(data[i - 1]) * 256u + data[i]];
        Context2Model context2;
        context2.train(std::vector<std::uint8_t>(data.begin(),
                                                 data.begin() + split));

        Metrics system{}, order0{}, bigram_m{}, context2_m{};
        std::uint64_t order0_correct = 0, order0_top5 = 0;
        std::uint64_t bigram_correct = 0, bigram_top5 = 0;
        std::uint64_t c2_correct = 0, c2_top5 = 0;
        double system_bits = 0.0, order0_bits = 0.0;
        double bigram_bits = 0.0, c2_bits = 0.0;

        const auto rank_in_top5 = [](const std::array<std::uint8_t, 5>& top,
                                      std::uint8_t target) {
            return std::find(top.begin(), top.end(), target) != top.end();
        };

        for (std::size_t i : eval_positions) {
            const std::uint8_t target = data[i];
            std::array<std::uint8_t, 5> system_top{};
            float system_loss = 0.0f;
            if (!vm.readout_context_direct_top5(
                    target, context4_key(data, i), selection.exact_count,
                    selection.fallback, system_top, system_loss))
                throw std::runtime_error("direct context top5 failed: " +
                                         vm.error());
            system_bits += static_cast<double>(system_loss) / std::log(2.0);
            system.top1 += system_top[0] == target ? 1u : 0u;
            system.top5 += contains(system_top, target) ? 1u : 0u;

            const auto order0_top = top5_classes([&](std::uint8_t c) {
                return unigram[c];
            });
            const std::uint64_t uni_total = split;
            const double p0 = (static_cast<double>(unigram[target]) + 1.0) /
                              (static_cast<double>(uni_total) + 256.0);
            order0_bits += -std::log2(p0);
            order0_correct += order0_top[0] == target ? 1u : 0u;
            order0_top5 += rank_in_top5(order0_top, target) ? 1u : 0u;

            const std::uint8_t a = data[i - 1];
            const auto bigram_top = top5_classes([&](std::uint8_t c) {
                return bigram[static_cast<std::size_t>(a) * 256u + c];
            });
            std::uint64_t bigram_total = 0;
            for (unsigned c = 0; c < 256u; ++c)
                bigram_total += bigram[static_cast<std::size_t>(a) * 256u + c];
            const double pb =
                (static_cast<double>(bigram[static_cast<std::size_t>(a) * 256u +
                                            target]) + 1.0) /
                (static_cast<double>(bigram_total) + 256.0);
            bigram_bits += -std::log2(pb);
            bigram_correct += bigram_top[0] == target ? 1u : 0u;
            bigram_top5 += rank_in_top5(bigram_top, target) ? 1u : 0u;

            const std::uint8_t a2 = data[i - 2];
            const auto c2_top = top5_classes([&](std::uint8_t c) {
                return context2.probability(a2, a, c);
            });
            c2_bits += -std::log2(context2.probability(a2, a, target));
            c2_correct += c2_top[0] == target ? 1u : 0u;
            c2_top5 += rank_in_top5(c2_top, target) ? 1u : 0u;
        }

        const double n = static_cast<double>(eval_positions.size());
        system.samples = order0.samples = bigram_m.samples = context2_m.samples =
            eval_positions.size();
        system.bpb = system_bits / n;
        system.top1 = static_cast<double>(system.top1) / n;
        system.top5 = static_cast<double>(system.top5) / n;
        order0.bpb = order0_bits / n;
        order0.top1 = static_cast<double>(order0_correct) / n;
        order0.top5 = static_cast<double>(order0_top5) / n;
        bigram_m.bpb = bigram_bits / n;
        bigram_m.top1 = static_cast<double>(bigram_correct) / n;
        bigram_m.top5 = static_cast<double>(bigram_top5) / n;
        context2_m.bpb = c2_bits / n;
        context2_m.top1 = static_cast<double>(c2_correct) / n;
        context2_m.top5 = static_cast<double>(c2_top5) / n;

        print_metrics("system", system);
        print_metrics("order0_matched", order0);
        print_metrics("bigram_matched", bigram_m);
        print_metrics("context2_matched", context2_m);

        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.system-byte-bench/1\","
               "\"corpus\":\"" << path << "\","
               "\"corpus_bytes\":" << data.size() << ","
               "\"train_split\":" << split << ","
               "\"eval_positions\":" << eval_positions.size() << ","
               "\"configuration\":{\"buckets\":" << buckets
            << ",\"exact_limit\":" << exact
            << ",\"fallback_limit\":" << fallback
            << ",\"route\":\"direct 256-bin exact k=4 + hashed 2-byte fallback\"},"
               "\"route\":{\"exact\":" << selection.exact_count
            << ",\"fallback\":" << selection.fallback
            << ",\"threshold\":" << selection.threshold
            << ",\"unique\":" << selection.unique
            << ",\"inserted\":" << inserted << "},"
               "\"metric_scope\":\"matched byte-level positions i>=4 on the "
               "held-out 20% split; system top-5 is native opcode 40 mode 8 "
               "direct 256-bin context; references are host n-gram/context-2 "
               "floors\","
               "\"system\":{\"samples\":" << system.samples << ",\"bpb\":" << system.bpb
            << ",\"top1\":" << system.top1
            << ",\"top5\":" << system.top5 << "},"
               "\"order0_matched\":{\"samples\":" << order0.samples << ",\"bpb\":" << order0.bpb
            << ",\"top1\":" << order0.top1
            << ",\"top5\":" << order0.top5 << "},"
               "\"bigram_matched\":{\"samples\":" << bigram_m.samples << ",\"bpb\":" << bigram_m.bpb
            << ",\"top1\":" << bigram_m.top1
            << ",\"top5\":" << bigram_m.top5 << "},"
               "\"context2_matched\":{\"samples\":" << context2_m.samples << ",\"bpb\":" << context2_m.bpb
            << ",\"top1\":" << context2_m.top1
            << ",\"top5\":" << context2_m.top5 << "},"
               "\"delta_system_minus_context2\":{\"bpb\":"
            << (system.bpb - context2_m.bpb)
            << ",\"top1\":" << (system.top1 - context2_m.top1)
            << ",\"top5\":" << (system.top5 - context2_m.top5) << "}}\n";
        std::cout << "direct256_bench output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "direct256_bench_error: " << e.what() << "\n";
        return 1;
    }
}
