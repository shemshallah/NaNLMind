// System word-level top-1/top-5 benchmark for the associative word layer.
//
// This is the existing integer associative-memory component, not the native
// 48M decoder. It reports top-k only; its recall scores are not normalized and
// therefore do not define a BPB claim.
#include "nanlm/word_vector.hpp"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>

using namespace nanlm;

namespace {
std::vector<std::string> tokenize(const std::vector<std::uint8_t>& data) {
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

bool contains_top(const std::vector<std::string>& top, const std::string& target) {
    return std::find(top.begin(), top.end(), target) != top.end();
}
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "data/alice_excerpt.txt";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/word_system.json";
    try {
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
        auto tokens = tokenize(data);
        if (tokens.size() < 200) throw std::runtime_error("corpus too small");
        const std::size_t split = tokens.size() * 4u / 5u;
        std::vector<std::string> train(tokens.begin(), tokens.begin() + split);
        std::unordered_set<std::string> train_vocab(train.begin(), train.end());

        BinStore store;
        WordVectorLayer layer(store);
        if (!layer.train(train))
            throw std::runtime_error("word layer training failed");
        if (split >= tokens.size())
            throw std::runtime_error("empty evaluation range");

        std::size_t n = 0, top1 = 0, top5 = 0;
        std::size_t in_vocab_n = 0, in_top1 = 0, in_top5 = 0;
        std::size_t oov = 0;
        for (std::size_t i = split; i < tokens.size(); ++i) {
            const std::string& target = tokens[i];
            const auto ranked = layer.predict_topk(tokens[i - 1], 5);
            ++n;
            const bool hit1 = !ranked.empty() && ranked.front() == target;
            const bool hit5 = contains_top(ranked, target);
            top1 += hit1 ? 1u : 0u;
            top5 += hit5 ? 1u : 0u;
            if (train_vocab.count(target)) {
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
        out << "{\"schema\":\"nanlm.word-system/1\","
               "\"corpus\":\"" << path << "\","
               "\"runtime\":\"integer associative word layer (host component)\","
               "\"scope\":\"full learned-vocabulary ranking over association "
               "dot-product scores; top-k only, no normalized BPB\","
               "\"train_tokens\":" << split
            << ",\"test_tokens\":" << n
            << ",\"vocab\":" << layer.vocab()
            << ",\"associations\":" << layer.associations()
            << ",\"oov_rate\":" << (n ? static_cast<double>(oov) / nd : 0.0)
            << ",\"top1\":" << (n ? static_cast<double>(top1) / nd : 0.0)
            << ",\"top5\":" << (n ? static_cast<double>(top5) / nd : 0.0)
            << ",\"in_vocab_top1\":"
            << (in_vocab_n ? static_cast<double>(in_top1) / invd : 0.0)
            << ",\"in_vocab_top5\":"
            << (in_vocab_n ? static_cast<double>(in_top5) / invd : 0.0)
            << ",\"bpb\":null}\n";
        std::cout << "word_system vocab=" << layer.vocab()
                  << " assoc=" << layer.associations()
                  << " test=" << n
                  << " top1=" << (n ? static_cast<double>(top1) / nd : 0.0)
                  << " top5=" << (n ? static_cast<double>(top5) / nd : 0.0)
                  << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "word_system_error: " << e.what() << "\n";
        return 1;
    }
}
