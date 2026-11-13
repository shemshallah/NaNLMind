// One-VM byte/word/token top-5 measurement.
//
// All three full projection tables are trained/evaluated through the same
// ProjectionRuntime/field_driver VM. The host only tokenizes, selects context
// rows, transports data and serializes receipts.
#include "nanlm/projection_runtime.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <numeric>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

using namespace nanlm;

namespace {
constexpr std::size_t kTokenChunk = 262144;

std::vector<std::uint8_t> read_bytes(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("cannot read " + path);
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

std::vector<std::string> words(const std::vector<std::uint8_t>& data) {
    std::vector<std::string> out;
    std::string word;
    for (std::uint8_t b : data) {
        const unsigned char c = b;
        if (std::isalnum(c) || c == '\'') {
            word.push_back(static_cast<char>(std::tolower(c)));
        } else if (!word.empty()) {
            out.push_back(word);
            word.clear();
        }
    }
    if (!word.empty()) out.push_back(word);
    return out;
}

std::uint32_t context4(const std::vector<std::uint8_t>& data, std::size_t i) {
    return (static_cast<std::uint32_t>(data[i - 4]) << 24) |
           (static_cast<std::uint32_t>(data[i - 3]) << 16) |
           (static_cast<std::uint32_t>(data[i - 2]) << 8) |
           static_cast<std::uint32_t>(data[i - 1]);
}

struct Score {
    double value = 0.0;
    std::size_t n = 0;
};

void add_bits(Score& s, float nats, std::size_t count, double divisor) {
    s.value += static_cast<double>(nats) / std::log(2.0) / divisor;
    s.n += count;
}
} // namespace

int main(int argc, char** argv) {
    const std::string text_path = argc > 1 ? argv[1] : "data/alice_full.txt";
    const std::string token_path = argc > 2 ? argv[2]
        : "state/lexor/1B_tokens/LLM_training_data_1B.bin";
    const std::string out_path = argc > 3 ? argv[3]
        : "state/benchmarks/system_top5.json";
    const std::size_t token_train = argc > 4 ? std::stoull(argv[4]) : 100000u;
    const std::size_t token_eval = argc > 5 ? std::stoull(argv[5]) : 5000u;
    try {
        ProjectionRuntime runtime("build");
        if (!runtime.load(ProjectionRuntime::Kind::Byte))
            throw std::runtime_error("byte runtime: " + runtime.error());

        // Byte direct-256 measurement.
        const auto bytes = read_bytes(text_path);
        const std::size_t byte_split = bytes.size() * 4u / 5u;
        std::vector<std::size_t> byte_train, byte_eval;
        for (std::size_t i = 4; i < byte_split; ++i)
            if (bytes[i] < 255u) byte_train.push_back(i);
        for (std::size_t i = byte_split; i < bytes.size(); ++i)
            if (bytes[i] < 255u) byte_eval.push_back(i);
        std::vector<std::uint32_t> keys;
        keys.reserve(byte_train.size());
        for (std::size_t i : byte_train) keys.push_back(context4(bytes, i));
        if (!runtime.byte_build(keys.data(), keys.size()) ||
            !runtime.byte_reset(6000, 10384))
            throw std::runtime_error("byte setup: " + runtime.error());
        for (std::size_t i : byte_train) {
            std::uint32_t bucket = 0;
            bool exact = false;
            if (!runtime.byte_step(bytes[i], context4(bytes, i), bucket, exact))
                throw std::runtime_error("byte train: " + runtime.error());
        }
        std::size_t b_top1 = 0, b_top5 = 0;
        double b_bits = 0.0;
        for (std::size_t i : byte_eval) {
            std::array<std::uint8_t, 5> top{};
            float loss = 0.0f;
            if (!runtime.byte_top5(bytes[i], context4(bytes, i), top, loss))
                throw std::runtime_error("byte eval: " + runtime.error());
            b_bits += static_cast<double>(loss) / std::log(2.0);
            b_top1 += top[0] == bytes[i] ? 1u : 0u;
            b_top5 += std::find(top.begin(), top.end(), bytes[i]) != top.end()
                ? 1u : 0u;
        }

        // Word projection measurement. The tables are disjoint from byte.
        const auto tokens = words(bytes);
        const std::size_t word_split = tokens.size() * 4u / 5u;
        std::vector<std::string> vocab;
        for (std::size_t i = 0; i < word_split; ++i) vocab.push_back(tokens[i]);
        std::sort(vocab.begin(), vocab.end());
        vocab.erase(std::unique(vocab.begin(), vocab.end()), vocab.end());
        if (vocab.size() + 1u > 2292u)
            throw std::runtime_error("word vocabulary exceeds unified layout");
        std::unordered_map<std::string, std::uint32_t> ids;
        for (std::uint32_t i = 0; i < vocab.size(); ++i) ids[vocab[i]] = i;
        const std::uint32_t unk = static_cast<std::uint32_t>(vocab.size());
        const std::size_t word_v = vocab.size() + 1u;
        std::vector<std::uint32_t> train_ids;
        for (std::size_t i = 0; i < word_split; ++i)
            train_ids.push_back(ids.at(tokens[i]));
        if (!runtime.word_clear(word_v) ||
            !runtime.word_build(train_ids, word_v))
            throw std::runtime_error("word setup: " + runtime.error());
        std::size_t w_top1 = 0, w_top5 = 0, w_in_n = 0, w_in_top5 = 0;
        double w_bits = 0.0;
        std::size_t w_bytes = 0;
        for (std::size_t i = word_split; i < tokens.size(); ++i) {
            const auto it = ids.find(tokens[i]);
            const bool oov = it == ids.end();
            const std::uint32_t target = oov ? unk : it->second;
            const auto cit = ids.find(tokens[i - 1]);
            const std::uint32_t context = cit == ids.end() ? unk : cit->second;
            std::array<std::uint32_t, 5> top{};
            float loss = 0.0f;
            if (!runtime.word_top5(target, context, word_v,
                                   static_cast<std::uint32_t>(train_ids.size()),
                                   top, loss))
                throw std::runtime_error("word eval: " + runtime.error());
            w_bits += static_cast<double>(loss) / std::log(2.0);
            w_bytes += tokens[i].size() + 1u;
            w_top1 += top[0] == target ? 1u : 0u;
            const bool hit5 = std::find(top.begin(), top.end(), target) != top.end();
            w_top5 += hit5 ? 1u : 0u;
            if (!oov) {
                ++w_in_n;
                w_in_top5 += hit5 ? 1u : 0u;
            }
        }

        // Token projection measurement, full 50,257-way table.
        std::ifstream tin(token_path, std::ios::binary);
        if (!tin) throw std::runtime_error("cannot read " + token_path);
        tin.seekg(0, std::ios::end);
        const std::uint64_t token_bytes = static_cast<std::uint64_t>(tin.tellg());
        tin.seekg(0, std::ios::beg);
        const std::size_t token_total = static_cast<std::size_t>(token_bytes / 2u);
        if (token_train == 0u || token_train + token_eval > token_total)
            throw std::runtime_error("token train/eval budget exceeds stream");
        std::vector<std::uint64_t> prev_freq(65536u, 0u);
        std::size_t seen = 0;
        while (seen < token_train) {
            const std::size_t n = std::min(kTokenChunk, token_train - seen);
            std::vector<std::uint16_t> raw(n);
            tin.read(reinterpret_cast<char*>(raw.data()),
                     static_cast<std::streamsize>(n * 2u));
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
        if (!runtime.token_clear(50257, 257) || !runtime.token_rowmap(rowmap))
            throw std::runtime_error("token setup: " + runtime.error());
        tin.clear();
        tin.seekg(0, std::ios::beg);
        std::uint32_t previous = 0xFFFFFFFFu;
        seen = 0;
        while (seen < token_train) {
            const std::size_t n = std::min(kTokenChunk, token_train - seen);
            std::vector<std::uint16_t> raw(n);
            tin.read(reinterpret_cast<char*>(raw.data()),
                     static_cast<std::streamsize>(n * 2u));
            std::vector<std::uint32_t> ids(raw.begin(), raw.end());
            if (!runtime.token_batch(ids, 50257, 257, previous))
                throw std::runtime_error("token train: " + runtime.error());
            previous = ids.back();
            seen += n;
        }
        tin.clear();
        tin.seekg(static_cast<std::streamoff>(token_train * 2u), std::ios::beg);
        std::size_t t_top1 = 0, t_top5 = 0, t_n = 0;
        double t_bits = 0.0;
        while (t_n < token_eval) {
            const std::size_t n = std::min(kTokenChunk, token_eval - t_n);
            std::vector<std::uint16_t> raw(n);
            tin.read(reinterpret_cast<char*>(raw.data()),
                     static_cast<std::streamsize>(n * 2u));
            for (std::uint16_t id : raw) {
                const std::uint32_t row = previous == 0xFFFFFFFFu
                    ? 256u : rowmap[previous];
                std::array<std::uint32_t, 5> top{};
                float loss = 0.0f;
                if (!runtime.token_top5(id, row, 50257,
                                        static_cast<std::uint32_t>(token_train),
                                        top, loss))
                    throw std::runtime_error("token eval: " + runtime.error());
                t_bits += static_cast<double>(loss) / std::log(2.0);
                t_top1 += top[0] == id ? 1u : 0u;
                t_top5 += std::find(top.begin(), top.end(), id) != top.end()
                    ? 1u : 0u;
                previous = id;
                ++t_n;
            }
        }

        const double bn = static_cast<double>(byte_eval.size());
        const double wn = static_cast<double>(tokens.size() - word_split);
        const double tn = static_cast<double>(t_n);
        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.system-top5/1\","
               "\"same_vm\":true,"
               "\"resident_tables\":[\"byte\",\"word\",\"token\"],"
               "\"byte\":{\"samples\":" << byte_eval.size()
            << ",\"bpb\":" << b_bits / bn
            << ",\"top1\":" << static_cast<double>(b_top1) / bn
            << ",\"top5\":" << static_cast<double>(b_top5) / bn
            << "},\"word\":{\"samples\":" << (tokens.size() - word_split)
            << ",\"vocab\":" << word_v
            << ",\"bpb\":" << w_bits / static_cast<double>(w_bytes)
            << ",\"top1\":" << static_cast<double>(w_top1) / wn
            << ",\"top5\":" << static_cast<double>(w_top5) / wn
            << ",\"in_vocab_top5\":"
            << (w_in_n ? static_cast<double>(w_in_top5) / w_in_n : 0.0)
            << "},\"token\":{\"samples\":" << t_n
            << ",\"train_tokens\":" << token_train
            << ",\"vocab\":50257"
            << ",\"bits_per_token\":" << t_bits / tn
            << ",\"top1\":" << static_cast<double>(t_top1) / tn
            << ",\"top5\":" << static_cast<double>(t_top5) / tn
            << "},\"scope\":\"byte BPB is byte-level; word BPB is word-byte "
               "normalized; token bits/top-k are GPT-2 subword level\"}\n";
        std::cout << "system_top5 byte_top5=" << static_cast<double>(b_top5) / bn
                  << " word_top5=" << static_cast<double>(w_top5) / wn
                  << " token_top5=" << static_cast<double>(t_top5) / tn
                  << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "system_top5_error: " << e.what() << "\n";
        return 1;
    }
}
