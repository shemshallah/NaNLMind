// 1B-token full-GPT2-vocabulary native token projection trainer.
//
// Full target vocabulary V=50,257; 256 most frequent previous-token IDs get
// their own context rows, every other previous token shares row 256. The host
// only performs I/O, frequency selection, row-map construction and transport.
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
constexpr std::size_t kChunk = 262144;
constexpr std::uint32_t kSentinel = 0xFFFFFFFFu;
constexpr std::size_t kGpt2Vocab = 50257;

std::vector<std::uint16_t> read_chunk(std::ifstream& in, std::size_t n) {
    std::vector<std::uint16_t> out(n);
    in.read(reinterpret_cast<char*>(out.data()),
            static_cast<std::streamsize>(n * 2u));
    if (in.gcount() != static_cast<std::streamsize>(n * 2u))
        throw std::runtime_error("short token read");
    return out;
}
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1]
        : "state/lexor/1B_tokens/LLM_training_data_1B.bin";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/train_1b_full.json";
    const std::size_t train_limit = argc > 3 ? std::stoull(argv[3])
        : 1000000000ull;
    const std::size_t eval_limit = argc > 4 ? std::stoull(argv[4]) : 20000ull;
    try {
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        in.seekg(0, std::ios::end);
        const auto bytes = static_cast<std::uint64_t>(in.tellg());
        in.seekg(0, std::ios::beg);
        const std::size_t total = static_cast<std::size_t>(bytes / 2u);
        if (train_limit + eval_limit > total)
            throw std::runtime_error("train/eval budget exceeds stream");

        std::vector<std::uint64_t> prev_freq(65536u, 0u);
        std::size_t seen = 0;
        while (seen < train_limit) {
            const std::size_t n = std::min(kChunk, train_limit - seen);
            const auto raw = read_chunk(in, n);
            for (std::size_t i = (seen == 0 ? 1u : 0u); i < raw.size(); ++i)
                ++prev_freq[raw[i - 1]];
            seen += n;
        }
        std::vector<std::uint16_t> order(65536u);
        std::iota(order.begin(), order.end(), 0u);
        std::partial_sort(order.begin(), order.begin() + 256u, order.end(),
                          [&](std::uint16_t a, std::uint16_t b) {
                              if (prev_freq[a] != prev_freq[b])
                                  return prev_freq[a] > prev_freq[b];
                              return a < b;
                          });
        std::array<std::uint16_t, 65536> rowmap{};
        rowmap.fill(256);
        for (std::size_t i = 0; i < 256u; ++i)
            rowmap[order[i]] = static_cast<std::uint16_t>(i);

        RawFieldVM vm("build/token_worker.nan");
        if (!vm.ready())
            throw std::runtime_error("token worker unavailable: " + vm.error());
        const auto started = std::chrono::steady_clock::now();
        if (!vm.token_projection_clear(kGpt2Vocab, 257))
            throw std::runtime_error("token clear failed: " + vm.error());
        if (!vm.token_projection_write_rowmap(rowmap))
            throw std::runtime_error("token rowmap failed: " + vm.error());
        std::cout << "full_token_train start train=" << train_limit
                  << " eval=" << eval_limit << " vocab=" << kGpt2Vocab
                  << " rows=257\n";

        in.clear();
        in.seekg(0, std::ios::beg);
        std::uint32_t previous = kSentinel;
        std::vector<std::uint32_t> ids;
        ids.reserve(kChunk);
        std::size_t consumed = 0;
        while (consumed < train_limit) {
            const std::size_t n = std::min(kChunk, train_limit - consumed);
            const auto raw = read_chunk(in, n);
            ids.clear();
            for (std::uint16_t id : raw) ids.push_back(id);
            if (!vm.token_projection_batch(ids, kGpt2Vocab, 257, previous))
                throw std::runtime_error("token batch failed: " + vm.error());
            previous = ids.back();
            consumed += n;
            if ((consumed % 100000000ull) == 0ull) {
                const auto seconds = std::chrono::duration<double>(
                    std::chrono::steady_clock::now() - started).count();
                std::cout << "full_token_train tokens=" << consumed
                          << " seconds=" << seconds
                          << " tokens_per_second="
                          << static_cast<double>(consumed) / seconds << "\n";
            }
        }

        // Held-out suffix, evaluate a bounded sample.
        in.clear();
        in.seekg(static_cast<std::streamoff>(train_limit * 2u), std::ios::beg);
        std::size_t n_eval = 0, top1 = 0, top5 = 0;
        double bits = 0.0;
        previous = ids.empty() ? kSentinel : ids.back();
        while (n_eval < eval_limit) {
            const std::size_t n = std::min(kChunk, eval_limit - n_eval);
            const auto raw = read_chunk(in, n);
            for (std::uint16_t id : raw) {
                const std::uint32_t target = id;
                const std::uint32_t row = previous == kSentinel
                    ? 256u : rowmap[previous];
                std::array<std::uint32_t, 5> top{};
                float loss = 0.0f;
                if (!vm.token_projection_top5(
                        target, row, kGpt2Vocab,
                        static_cast<std::uint32_t>(train_limit), top, loss))
                    throw std::runtime_error("token eval failed: " + vm.error());
                top1 += top[0] == target ? 1u : 0u;
                top5 += std::find(top.begin(), top.end(), target) != top.end()
                    ? 1u : 0u;
                bits += static_cast<double>(loss) / std::log(2.0);
                previous = target;
                ++n_eval;
            }
        }
        const auto seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.native-full-token-train/1\","
               "\"corpus\":\"" << path << "\","
               "\"train_tokens\":" << train_limit
            << ",\"eval_tokens\":" << n_eval
            << ",\"vocab\":" << kGpt2Vocab
            << ",\"context_rows\":257"
            << ",\"train_seconds\":" << seconds
            << ",\"tokens_per_second\":"
            << static_cast<double>(train_limit) / seconds
            << ",\"bits_per_token\":" << bits / static_cast<double>(n_eval)
            << ",\"top1\":" << static_cast<double>(top1) / n_eval
            << ",\"top5\":" << static_cast<double>(top5) / n_eval
            << ",\"scope\":\"full GPT-2 vocabulary; 256 hot previous-token "
               "rows plus fallback; token-level not text-word/byte\"}\n";
        std::cout << "full_token_train done tokens=" << train_limit
                  << " seconds=" << seconds
                  << " bits_per_token=" << bits / static_cast<double>(n_eval)
                  << " top1=" << static_cast<double>(top1) / n_eval
                  << " top5=" << static_cast<double>(top5) / n_eval
                  << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "train_1b_full_error: " << e.what() << "\n";
        return 1;
    }
}
