#include "nanlm/word_vector.hpp"
#include "test_util.hpp"

#include <cctype>
#include <fstream>
#include <iterator>
#include <string>
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
} // namespace

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    const auto tokens = tokenize(data);
    if (tokens.size() < 100) return test_done("word-vector layer (skipped)");
    const std::size_t split = (tokens.size() * 4) / 5;

    BinStore store;
    WordVectorLayer layer(store);
    std::vector<std::string> train(tokens.begin(), tokens.begin() + split);
    CHECK(layer.train(train));
    CHECK(layer.vocab() > 0);
    CHECK(layer.associations() > 0);

    std::size_t correct = 0, n = 0;
    for (std::size_t i = split + 1; i < tokens.size(); ++i) {
        if (layer.predict(tokens[i - 1]) == tokens[i]) ++correct;
        ++n;
    }
    const double acc = n ? static_cast<double>(correct) / n : 0.0;
    std::cout << "word-vector vocab=" << layer.vocab()
              << " assoc=" << layer.associations()
              << " test=" << n << " top1=" << acc << "\n";
    CHECK(n > 0);
    CHECK(acc >= 0.07);
    CHECK(layer.digest() == layer.digest());
    return test_done("word-vector expert");
}
