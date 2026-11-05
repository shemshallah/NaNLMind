#include "test_util.hpp"
#include <cstdint>

#include <cctype>
#include <fstream>
#include <iterator>
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

} // namespace

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    const auto tokens = words(data);
    if (tokens.size() < 100) return test_done("word-stream baseline (skipped)");
    const std::size_t split = (tokens.size() * 4) / 5;

    std::unordered_map<std::string, std::uint32_t> unigram;
    std::unordered_map<std::string, std::unordered_map<std::string, std::uint32_t>> bigram;
    for (std::size_t i = 0; i < split; ++i) {
        ++unigram[tokens[i]];
        if (i > 0) ++bigram[tokens[i - 1]][tokens[i]];
    }
    auto best = [](const auto& counts) {
        std::string out;
        std::uint32_t best_count = 0;
        for (const auto& kv : counts) {
            if (kv.second > best_count || (kv.second == best_count && kv.first < out)) {
                best_count = kv.second;
                out = kv.first;
            }
        }
        return out;
    };
    const std::string uni = best(unigram);

    std::size_t uni_correct = 0, bi_correct = 0, n = 0;
    for (std::size_t i = split + 1; i < tokens.size(); ++i) {
        const auto it = bigram.find(tokens[i - 1]);
        const std::string bi = it == bigram.end() ? uni : best(it->second);
        if (uni == tokens[i]) ++uni_correct;
        if (bi == tokens[i]) ++bi_correct;
        ++n;
    }
    const double ua = n ? static_cast<double>(uni_correct) / n : 0.0;
    const double ba = n ? static_cast<double>(bi_correct) / n : 0.0;
    std::cout << "words=" << tokens.size() << " vocab=" << unigram.size()
              << " test=" << n << " unigram=" << ua
              << " bigram=" << ba << " fallback=" << uni << "\n";
    CHECK(n > 0);
    CHECK(ba >= ua);
    CHECK(ba >= ua);
    return test_done("word-stream unigram/bigram baseline");
}
