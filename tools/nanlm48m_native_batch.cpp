// Native NaN16 shortlist batch proposal adapter.
//
// One guest ABI call (opcode 118) evaluates every candidate word in the
// shortlist through the existing six-slot CORDIC attention and Poincare
// kernel.  Host code only tokenizes text, transports IDs and serializes the
// guest's typed receipt.  It computes no attention, trigonometry or model
// score.
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

static std::string read_text(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("cannot read " + path);
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

static std::string json_quote(const std::string& text) {
    std::string out = "\"";
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
        else if (c < 0x20) { out += "\\u00"; const char* hex="0123456789abcdef"; out += hex[c>>4]; out += hex[c&15]; }
        else out += static_cast<char>(c);
    }
    out += "\"";
    return out;
}

static std::vector<std::uint32_t> words(RawFieldVM& vm,
                                        const std::string& text) {
    std::vector<std::uint32_t> w, s, m;
    std::size_t wc = 0, sc = 0;
    if (!vm.tokenize(text, 256, w, s, m, wc, sc))
        throw std::runtime_error("native tokenizer: " + vm.error());
    return w;
}

int main(int argc, char** argv) {
    if (argc != 6) {
        std::cerr << "Usage: nanlm48m-native-batch <previous-window> "
                     "<current-window> <context> <wordlist> <out.json>\n";
        return 2;
    }
    try {
        const std::string previous = read_text(argv[1]);
        const std::string current = read_text(argv[2]);
        const std::string context = argv[3];
        std::ifstream list_in(argv[4]);
        if (!list_in) throw std::runtime_error("cannot read wordlist");
        std::vector<std::string> words_list;
        std::string line;
        while (std::getline(list_in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (!line.empty()) words_list.push_back(line);
        }
        if (words_list.empty() || words_list.size() > 64)
            throw std::runtime_error("wordlist must contain 1..64 words");

        RawFieldVM vm("build/field_driver.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        auto context_words = words(vm, current);
        if (context_words.empty()) context_words = words(vm, previous);
        if (context_words.empty()) throw std::runtime_error("no context words");
        if (context_words.size() > 6)
            context_words.erase(context_words.begin(),
                                context_words.end() - 6);
        std::array<std::uint32_t, 6> ctx{};
        std::uint32_t mask = 0;
        for (std::size_t i = 0; i < context_words.size(); ++i) {
            ctx[i] = context_words[i];
            mask |= 1u << i;
        }
        std::vector<std::uint32_t> candidates;
        for (const auto& word : words_list) {
            const auto ids = words(vm, word);
            if (ids.size() != 1 || ids[0] == 0)
                throw std::runtime_error("candidate must tokenize to one guest word: " + word);
            candidates.push_back(ids[0]);
        }
        std::vector<NativeShortlistCandidate> proposals;
        std::size_t accepted = 0;
        if (!vm.native_shortlist_batch(ctx, static_cast<std::uint8_t>(mask), 1,
                                       0, 0, candidates, proposals, accepted))
            throw std::runtime_error("native shortlist: " + vm.error());

        std::ofstream out(argv[5], std::ios::binary | std::ios::trunc);
        if (!out) throw std::runtime_error("cannot open output");
        out << "{\"schema\":\"nanlm.48m-native-batch/1\","
               "\"context\":" << json_quote(context) <<
               ",\"candidate_count\":" << words_list.size() <<
               ",\"accepted\":" << accepted <<
               ",\"native_log_weights\":{";
        for (std::size_t i = 0; i < words_list.size(); ++i) {
            if (i) out << ',';
            out << json_quote(words_list[i]) << ':'
                << (proposals[i].accepted ? proposals[i].poincare_x : 0.0f);
        }
        out << "},\"native_evidence\":[";
        for (std::size_t i = 0; i < proposals.size(); ++i) {
            if (i) out << ',';
            out << "{\"word\":" << json_quote(words_list[i])
                << ",\"accepted\":" << (proposals[i].accepted ? "true" : "false")
                << ",\"x\":" << proposals[i].poincare_x
                << ",\"y\":" << proposals[i].poincare_y
                << ",\"radius\":" << proposals[i].radius
                << ",\"distance\":" << proposals[i].radial_distance << '}';
        }
        out << "]}\n";
        std::cout << "native_shortlist_batch candidates=" << candidates.size()
                  << " accepted=" << accepted << " output=" << argv[5] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "native_shortlist_batch_error: " << e.what() << "\n";
        return 1;
    }
}
