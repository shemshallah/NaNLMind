// Native full-vocabulary word projection benchmark.
//
// The host only tokenizes, assigns the training vocabulary IDs, transports the
// IDs, and maps returned IDs back to words.  Every unigram/bigram count,
// interpolation, full-vocabulary scan, top-5 and target loss runs in the
// word_worker.nan guest image.
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

using namespace nanlm;

namespace {
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
bool contains(const std::array<std::uint32_t, 5>& top, std::uint32_t id) {
    return std::find(top.begin(), top.end(), id) != top.end();
}
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "data/alice_full.txt";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/word_native.json";
    try {
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
        const auto tokens = words(data);
        if (tokens.size() < 200u) throw std::runtime_error("corpus too small");
        const std::size_t split = tokens.size() * 4u / 5u;

        std::vector<std::string> vocab;
        for (std::size_t i = 0; i < split; ++i)
            vocab.push_back(tokens[i]);
        std::sort(vocab.begin(), vocab.end());
        vocab.erase(std::unique(vocab.begin(), vocab.end()), vocab.end());
        if (vocab.size() + 1u > 3000u)
            throw std::runtime_error("word_worker vocabulary limit is 3000");
        std::unordered_map<std::string, std::uint32_t> ids;
        for (std::uint32_t i = 0; i < vocab.size(); ++i)
            ids[vocab[i]] = i;
        const std::uint32_t unk = static_cast<std::uint32_t>(vocab.size());
        vocab.push_back("<unk>");
        const std::size_t V = vocab.size();

        std::vector<std::uint32_t> train_ids;
        train_ids.reserve(split);
        for (std::size_t i = 0; i < split; ++i) {
            const auto it = ids.find(tokens[i]);
            if (it == ids.end()) throw std::logic_error("train OOV");
            train_ids.push_back(it->second);
        }

        RawFieldVM vm("build/word_worker.nan");
        if (!vm.ready())
            throw std::runtime_error("word worker unavailable: " + vm.error());
        if (!vm.word_projection_clear(V))
            throw std::runtime_error("word clear failed: " + vm.error());
        if (!vm.word_projection_build(train_ids, V))
            throw std::runtime_error("word build failed: " + vm.error());

        std::size_t n = 0, top1 = 0, top5 = 0;
        std::size_t in_vocab_n = 0, in_top1 = 0, in_top5 = 0, oov = 0;
        double bits = 0.0;
        std::size_t bytes = 0;
        for (std::size_t i = split; i < tokens.size(); ++i) {
            const std::string& target_word = tokens[i];
            const auto target_it = ids.find(target_word);
            const bool is_oov = target_it == ids.end();
            const std::uint32_t target = is_oov ? unk : target_it->second;
            const auto ctx_it = ids.find(tokens[i - 1]);
            const std::uint32_t context = ctx_it == ids.end()
                ? unk : ctx_it->second;
            std::array<std::uint32_t, 5> top{};
            float loss = 0.0f;
            if (!vm.word_projection_top5(
                    target, context, V,
                    static_cast<std::uint32_t>(train_ids.size()), top, loss))
                throw std::runtime_error("word top5 failed: " + vm.error());
            const bool hit1 = top[0] == target;
            const bool hit5 = contains(top, target);
            ++n;
            top1 += hit1 ? 1u : 0u;
            top5 += hit5 ? 1u : 0u;
            bits += static_cast<double>(loss) / std::log(2.0);
            bytes += target_word.size() + 1u;
            if (!is_oov) {
                ++in_vocab_n;
                in_top1 += hit1 ? 1u : 0u;
                in_top5 += hit5 ? 1u : 0u;
            } else {
                ++oov;
            }
        }

        const double nd = static_cast<double>(n);
        const double invd = static_cast<double>(in_vocab_n);
        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.word-native/1\","
               "\"corpus\":\"" << path << "\","
               "\"runtime\":\"word_worker.nan full-vocabulary native projection\","
               "\"train_tokens\":" << split
            << ",\"test_tokens\":" << n
            << ",\"vocab\":" << V
            << ",\"bytes_denominator\":" << bytes
            << ",\"bpb\":" << bits / static_cast<double>(bytes)
            << ",\"top1\":" << top1 / nd
            << ",\"top5\":" << top5 / nd
            << ",\"in_vocab_top1\":" << (in_vocab_n ? in_top1 / invd : 0.0)
            << ",\"in_vocab_top5\":" << (in_vocab_n ? in_top5 / invd : 0.0)
            << ",\"oov_rate\":" << (n ? static_cast<double>(oov) / nd : 0.0)
            << ",\"scope\":\"native full-training-vocabulary projection; "
               "same 80/20 token split as word_baselines\"}\n";
        std::cout << "word_native vocab=" << V
                  << " test=" << n
                  << " bpb=" << bits / static_cast<double>(bytes)
                  << " top1=" << top1 / nd
                  << " top5=" << top5 / nd
                  << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "word_native_error: " << e.what() << "\n";
        return 1;
    }
}
