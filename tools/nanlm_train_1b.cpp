// Streaming native token-projection training for a uint16 token stream.
//
// Host work is limited to file I/O, vocabulary frequency selection, ID
// remapping for transport, and JSON. Unigram/bigram counts, interpolation,
// full-vocabulary top-5 and loss all execute in field_driver.nan unified projection.
#include "nanlm/projection_runtime.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

using namespace nanlm;

namespace {
constexpr std::size_t kChunk = 262144;
constexpr std::uint32_t kUnknown = 0xFFFFFFFFu;

std::vector<std::uint16_t> read_chunk(std::ifstream& in, std::size_t count) {
    std::vector<std::uint16_t> out(count);
    in.read(reinterpret_cast<char*>(out.data()),
            static_cast<std::streamsize>(count * sizeof(std::uint16_t)));
    const auto got = in.gcount();
    if (got != static_cast<std::streamsize>(count * sizeof(std::uint16_t)))
        throw std::runtime_error("short token read");
    return out;
}
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1]
        : "state/lexor/1B_tokens/LLM_training_data_1B.bin";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/train_1b.json";
    const std::size_t vocab_size = argc > 3 ? std::stoull(argv[3]) : 3000u;
    const std::size_t train_limit = argc > 4 ? std::stoull(argv[4]) : 1000000000ull;
    const std::size_t eval_limit = argc > 5 ? std::stoull(argv[5]) : 180000ull;
    try {
        if (vocab_size < 2u || vocab_size > 3000u)
            throw std::runtime_error("vocabulary 2..3000 required");
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        in.seekg(0, std::ios::end);
        const auto bytes = static_cast<std::uint64_t>(in.tellg());
        in.seekg(0, std::ios::beg);
        const std::size_t total = static_cast<std::size_t>(bytes / 2u);
        if (train_limit == 0u || train_limit + eval_limit > total)
            throw std::runtime_error("train/eval token budget exceeds stream");

        // Frequency pass over the training prefix.
        std::vector<std::uint64_t> freq(65536u, 0u);
        std::size_t seen = 0;
        while (seen < train_limit) {
            const std::size_t n = std::min(kChunk, train_limit - seen);
            const auto ids = read_chunk(in, n);
            for (std::uint16_t id : ids) ++freq[id];
            seen += n;
            if ((seen % 100000000ull) == 0ull)
                std::cout << "freq_seen=" << seen << "\n";
        }
        std::vector<std::uint16_t> order(65536u);
        std::iota(order.begin(), order.end(), 0u);
        std::partial_sort(order.begin(), order.begin() + (vocab_size - 1u),
                          order.end(), [&](std::uint16_t a, std::uint16_t b) {
                              if (freq[a] != freq[b]) return freq[a] > freq[b];
                              return a < b;
                          });
        const std::uint16_t unk = static_cast<std::uint16_t>(vocab_size - 1u);
        std::vector<std::uint16_t> remap(65536u, unk);
        std::vector<std::uint64_t> chosen(vocab_size, 0u);
        for (std::size_t i = 0; i + 1u < vocab_size; ++i) {
            remap[order[i]] = static_cast<std::uint16_t>(i);
            chosen[i] = freq[order[i]];
        }
        chosen[unk] = 0u;

        ProjectionRuntime runtime("build");
        if (!runtime.load(ProjectionRuntime::Kind::Word))
            throw std::runtime_error("word projection unavailable: " + runtime.error());
        const auto started = std::chrono::steady_clock::now();
        if (!runtime.word_clear(vocab_size))
            throw std::runtime_error("word clear failed: " + runtime.error());
        std::cout << "native_train start vocab=" << vocab_size
                  << " train=" << train_limit
                  << " eval=" << eval_limit << "\n";
        in.clear();
        in.seekg(0, std::ios::beg);
        std::uint32_t previous = kUnknown;
        std::size_t consumed = 0;
        std::vector<std::uint32_t> mapped;
        mapped.reserve(kChunk);
        while (consumed < train_limit) {
            const std::size_t n = std::min(kChunk, train_limit - consumed);
            const auto raw = read_chunk(in, n);
            mapped.clear();
            for (std::uint16_t id : raw)
                mapped.push_back(remap[id]);
            if (!runtime.word_batch(mapped, vocab_size, previous))
                throw std::runtime_error("word batch failed: " + runtime.error());
            previous = mapped.back();
            consumed += n;
            if ((consumed % 100000000ull) == 0ull) {
                const auto seconds = std::chrono::duration<double>(
                    std::chrono::steady_clock::now() - started).count();
                std::cout << "native_train tokens=" << consumed
                          << " seconds=" << seconds
                          << " tokens_per_second="
                          << static_cast<double>(consumed) / seconds << "\n";
            }
        }

        // Held-out suffix, preserving the cross-boundary context.
        in.clear();
        in.seekg(static_cast<std::streamoff>(train_limit * 2u), std::ios::beg);
        std::size_t n_eval = 0, top1 = 0, top5 = 0, oov = 0;
        double bits = 0.0;
        previous = mapped.empty() ? kUnknown : mapped.back();
        while (n_eval < eval_limit) {
            const std::size_t n = std::min(kChunk, eval_limit - n_eval);
            const auto raw = read_chunk(in, n);
            for (std::uint16_t id : raw) {
                const std::uint32_t target = remap[id];
                const std::uint32_t ctx = previous == kUnknown ? unk : previous;
                std::array<std::uint32_t, 5> top{};
                float loss = 0.0f;
                if (!runtime.word_top5(
                        target, ctx, vocab_size,
                        static_cast<std::uint32_t>(train_limit), top, loss))
                    throw std::runtime_error("word eval failed: " + runtime.error());
                top1 += top[0] == target ? 1u : 0u;
                top5 += std::find(top.begin(), top.end(), target) != top.end()
                    ? 1u : 0u;
                bits += static_cast<double>(loss) / std::log(2.0);
                if (target == unk) ++oov;
                previous = target;
                ++n_eval;
            }
        }
        const auto seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();

        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.native-token-train/1\","
               "\"corpus\":\"" << path << "\","
               "\"token_format\":\"uint16 little-endian\","
               "\"stream_tokens\":" << total
            << ",\"train_tokens\":" << train_limit
            << ",\"eval_tokens\":" << n_eval
            << ",\"vocab\":" << vocab_size
            << ",\"unknown_id\":" << unk
            << ",\"train_seconds\":" << seconds
            << ",\"tokens_per_second\":"
            << static_cast<double>(train_limit) / seconds
            << ",\"bits_per_token\":" << bits / static_cast<double>(n_eval)
            << ",\"top1\":" << static_cast<double>(top1) / n_eval
            << ",\"top5\":" << static_cast<double>(top5) / n_eval
            << ",\"unk_rate\":" << static_cast<double>(oov) / n_eval
            << ",\"scope\":\"native unified-field word token bigram projection; "
               "top-k on token IDs, not text words or bytes\"}\n";
        std::cout << "native_train done tokens=" << train_limit
                  << " seconds=" << seconds
                  << " bits_per_token=" << bits / static_cast<double>(n_eval)
                  << " top1=" << static_cast<double>(top1) / n_eval
                  << " top5=" << static_cast<double>(top5) / n_eval
                  << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "train_1b_error: " << e.what() << "\n";
        return 1;
    }
}
