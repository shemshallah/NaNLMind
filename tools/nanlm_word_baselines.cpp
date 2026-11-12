// Word-level n-gram baselines with BPB and full-vocabulary top-1/top-5.
// Not the 48M frontier decoder and not a native head-worker metric.
#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

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
struct Eval { double bpb=0, top1=0, top5=0; };
} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "data/alice_full.txt";
    const std::string out_path = argc > 2 ? argv[2]
        : "state/benchmarks/word_baselines.json";
    try {
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("cannot read " + path);
        std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
        const auto tokens = words(data);
        if (tokens.size() < 200) throw std::runtime_error("corpus too small");
        const std::size_t split = tokens.size() * 4u / 5u;
        std::unordered_map<std::string, std::uint64_t> ug;
        std::unordered_map<std::string, std::unordered_map<std::string, std::uint64_t>> bg;
        for (std::size_t i = 0; i < split; ++i) {
            ++ug[tokens[i]];
            if (i > 0) ++bg[tokens[i - 1]][tokens[i]];
        }
        std::vector<std::string> vocab;
        vocab.reserve(ug.size() + 1);
        for (const auto& kv : ug) vocab.push_back(kv.first);
        std::sort(vocab.begin(), vocab.end());
        const std::string unk = "<unk>";
        vocab.push_back(unk);
        std::unordered_map<std::string, std::uint32_t> id;
        for (std::uint32_t i = 0; i < vocab.size(); ++i) id[vocab[i]] = i;
        const double alpha = 0.01;
        const double lambda = 0.7;
        std::uint64_t train_total = split;
        std::vector<std::uint64_t> ug_count(vocab.size(), 0);
        for (const auto& kv : ug) ug_count[id[kv.first]] = kv.second;
        auto unigram_prob = [&](std::uint32_t target) {
            return (static_cast<double>(ug_count[target]) + alpha) /
                   (static_cast<double>(train_total) + alpha * vocab.size());
        };
        auto bigram_prob = [&](const std::string& ctx, std::uint32_t target) {
            const double u = unigram_prob(target);
            auto it = bg.find(ctx);
            if (it == bg.end()) return u;
            std::uint64_t total = 0;
            for (const auto& kv : it->second) total += kv.second;
            const auto jt = it->second.find(vocab[target]);
            const double b = ((jt == it->second.end() ? 0.0 :
                static_cast<double>(jt->second)) + alpha) /
                (static_cast<double>(total) + alpha * vocab.size());
            return lambda * b + (1.0 - lambda) * u;
        };
        Eval uni{}, bi{};
        double ubits = 0, bbits = 0;
        std::size_t bytes = 0, oov = 0, in_vocab_n = 0;
        std::size_t uni_top1 = 0, uni_top5 = 0, bi_top1 = 0, bi_top5 = 0;
        std::size_t uni_in_top1 = 0, uni_in_top5 = 0, bi_in_top1 = 0, bi_in_top5 = 0;
        for (std::size_t i = split; i < tokens.size(); ++i) {
            const std::string& target_word = tokens[i];
            const auto tid = id.find(target_word);
            const bool is_oov = tid == id.end();
            const std::uint32_t target = is_oov ? id[unk] : tid->second;
            const std::string ctx = i == 0 ? unk :
                (id.count(tokens[i - 1]) ? tokens[i - 1] : unk);
            std::vector<std::pair<double, std::uint32_t>> up, bp;
            up.reserve(vocab.size());
            for (std::uint32_t v = 0; v < vocab.size(); ++v)
                up.emplace_back(unigram_prob(v), v);
            const std::size_t topn = std::min<std::size_t>(5u, vocab.size());
            std::partial_sort(up.begin(), up.begin() + topn, up.end(),
                              [](const auto& a, const auto& b) {
                                  if (a.first != b.first) return a.first > b.first;
                                  return a.second < b.second;
                              });
            for (std::uint32_t v = 0; v < vocab.size(); ++v)
                bp.emplace_back(bigram_prob(ctx, v), v);
            std::partial_sort(bp.begin(), bp.begin() + topn, bp.end(),
                              [](const auto& a, const auto& b) {
                                  if (a.first != b.first) return a.first > b.first;
                                  return a.second < b.second;
                              });
            auto rank = [&](const std::vector<std::pair<double, std::uint32_t>>& v) {
                for (std::size_t k = 0; k < topn; ++k)
                    if (v[k].second == target) return k;
                return topn;
            };
            const double pu = unigram_prob(target);
            const double pb = bigram_prob(ctx, target);
            ubits += -std::log2(pu);
            bbits += -std::log2(pb);
            if (rank(up) == 0) ++uni_top1;
            if (rank(up) < topn) ++uni_top5;
            if (rank(bp) == 0) ++bi_top1;
            if (rank(bp) < topn) ++bi_top5;
            if (!is_oov) {
                ++in_vocab_n;
                if (rank(up) == 0) ++uni_in_top1;
                if (rank(up) < topn) ++uni_in_top5;
                if (rank(bp) == 0) ++bi_in_top1;
                if (rank(bp) < topn) ++bi_in_top5;
            }
            bytes += target_word.size() + 1u;
            if (is_oov) ++oov;
        }
        const double n = static_cast<double>(tokens.size() - split);
        uni = {ubits / static_cast<double>(bytes),
               static_cast<double>(uni_top1) / n,
               static_cast<double>(uni_top5) / n};
        bi = {bbits / static_cast<double>(bytes),
              static_cast<double>(bi_top1) / n,
              static_cast<double>(bi_top5) / n};
        std::ofstream out(out_path, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write " + out_path);
        out << "{\"schema\":\"nanlm.word-baselines/1\","
               "\"corpus\":\"" << path << "\","
               "\"train_tokens\":" << split << ","
               "\"test_tokens\":" << (tokens.size() - split) << ","
               "\"vocab\":" << vocab.size() << ","
               "\"bytes_denominator\":" << bytes << ","
               "\"scope\":\"word n-gram baseline over training vocabulary + <unk>; not 48M frontier\","
               "\"unigram\":{\"bpb\":" << uni.bpb
            << ",\"top1\":" << uni.top1 << ",\"top5\":" << uni.top5
            << ",\"in_vocab_top1\":" << (in_vocab_n ? static_cast<double>(uni_in_top1) / in_vocab_n : 0.0)
            << ",\"in_vocab_top5\":" << (in_vocab_n ? static_cast<double>(uni_in_top5) / in_vocab_n : 0.0)
            << "},"
               "\"bigram\":{\"bpb\":" << bi.bpb
            << ",\"top1\":" << bi.top1 << ",\"top5\":" << bi.top5
            << ",\"in_vocab_top1\":" << (in_vocab_n ? static_cast<double>(bi_in_top1) / in_vocab_n : 0.0)
            << ",\"in_vocab_top5\":" << (in_vocab_n ? static_cast<double>(bi_in_top5) / in_vocab_n : 0.0)
            << "},\"oov_rate\":" << (n ? static_cast<double>(oov) / n : 0.0)
            << "}\n";
        std::cout << "word_baselines vocab=" << vocab.size()
                  << " unigram_bpb=" << uni.bpb
                  << " bigram_bpb=" << bi.bpb
                  << " bigram_top5=" << bi.top5 << " output=" << out_path << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "word_baselines_error: " << e.what() << "\n";
        return 1;
    }
}
